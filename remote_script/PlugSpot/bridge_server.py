"""User-local Unix socket server that never touches Live objects on workers."""

import fcntl
import json
import os
import queue
import socket
import socketserver
import threading


class _PendingRequest:
    def __init__(self, line):
        self.line = line
        self.response = None
        self.completed = threading.Event()
        self.cancelled = False


class BridgeServer:
    SOCKET_RELATIVE_PATH = "~/Library/Application Support/PlugSpot/bridge.sock"
    LOCK_RELATIVE_PATH = "~/Library/Application Support/PlugSpot/bridge.lock"
    MAX_PENDING_REQUESTS = 64
    # Leave time for the Swift client's socket timeout to return Live's
    # structured timeout response instead of racing it at the same deadline.
    REQUEST_TIMEOUT_SECONDS = 7

    def __init__(self, logger=None):
        self._logger = logger
        self._pending = queue.Queue(maxsize=self.MAX_PENDING_REQUESTS)
        self._server = None
        self._thread = None
        self._lock_file = None
        self._socket_path = os.path.expanduser(self.SOCKET_RELATIVE_PATH)
        self._running = False

    @property
    def running(self):
        return self._running

    def start(self):
        if not hasattr(socket, "AF_UNIX"):
            raise RuntimeError("Unix domain sockets are unavailable in this Python runtime")

        directory = os.path.dirname(self._socket_path)
        os.makedirs(directory, mode=0o700, exist_ok=True)
        os.chmod(directory, 0o700)
        lock_path = os.path.expanduser(self.LOCK_RELATIVE_PATH)
        self._lock_file = open(lock_path, "a+")
        os.chmod(lock_path, 0o600)
        try:
            fcntl.flock(self._lock_file.fileno(), fcntl.LOCK_EX | fcntl.LOCK_NB)
        except OSError as exc:
            self._lock_file.close()
            self._lock_file = None
            raise RuntimeError("Another PlugSpot bridge owns the local socket") from exc

        # The exclusive process lock proves that any leftover socket is stale.
        if os.path.exists(self._socket_path):
            os.unlink(self._socket_path)

        owner = self

        class RequestHandler(socketserver.StreamRequestHandler):
            def handle(self):
                while owner._running:
                    line = self.rfile.readline(8 * 1024 * 1024 + 1)
                    if not line:
                        return
                    pending = _PendingRequest(line)
                    try:
                        owner._pending.put(pending, timeout=0.25)
                    except queue.Full:
                        self.wfile.write(owner._error_line(
                            "bridge_busy", "Bridge request queue is full", True,
                            owner._request_id(line),
                        ))
                        continue
                    if not pending.completed.wait(owner.REQUEST_TIMEOUT_SECONDS):
                        pending.cancelled = True
                        response = owner._error_line(
                            "live_timeout", "Live did not process the request in time", True,
                            owner._request_id(line),
                        )
                    else:
                        response = pending.response
                    try:
                        self.wfile.write(response)
                        self.wfile.flush()
                    except (BrokenPipeError, OSError):
                        return

        class UnixServer(socketserver.ThreadingUnixStreamServer):
            daemon_threads = True
            allow_reuse_address = False

        try:
            self._server = UnixServer(self._socket_path, RequestHandler)
            os.chmod(self._socket_path, 0o600)
            self._running = True
            self._thread = threading.Thread(
                target=self._server.serve_forever,
                kwargs={"poll_interval": 0.1},
                name="PlugSpot-UDS",
                daemon=True,
            )
            self._thread.start()
            self._log("PlugSpot bridge listening on user-local Unix socket")
        except Exception:
            if self._server is not None:
                self._server.server_close()
                self._server = None
            self._release_lock()
            raise

    def process_pending(self, dispatcher, maximum=16):
        """Run on Live's scheduled Control Surface callback, never a worker."""
        processed = 0
        while self._running and processed < maximum:
            try:
                pending = self._pending.get_nowait()
            except queue.Empty:
                break
            try:
                if not pending.cancelled:
                    pending.response = dispatcher.handle_line(pending.line)
            except Exception:
                pending.response = self._error_line("internal_error", "Bridge request failed", False)
            finally:
                pending.completed.set()
                self._pending.task_done()
            processed += 1
        return processed

    def stop(self):
        self._running = False
        if self._server is not None:
            self._server.shutdown()
            self._server.server_close()
            self._server = None
        if self._thread is not None:
            self._thread.join(timeout=1.0)
            self._thread = None
        if os.path.exists(self._socket_path):
            try:
                os.unlink(self._socket_path)
            except OSError as exc:
                self._log("Could not remove bridge socket: %s", exc)
        self._release_lock()
        self._log("PlugSpot bridge stopped")

    @staticmethod
    def _request_id(line):
        try:
            request = json.loads(line.decode("utf-8"))
            request_id = request.get("id") if isinstance(request, dict) else None
            if isinstance(request_id, str) and 0 < len(request_id) <= 128:
                return request_id
        except Exception:
            pass
        return ""

    @staticmethod
    def _error_line(code, message, retryable, request_id=""):
        return (
            json.dumps(
                {
                    "protocol_version": 1,
                    "id": request_id,
                    "ok": False,
                    "error": {"code": code, "message": message, "retryable": retryable},
                },
                separators=(",", ":"),
            ).encode("utf-8")
            + b"\n"
        )

    def _release_lock(self):
        if self._lock_file is not None:
            try:
                fcntl.flock(self._lock_file.fileno(), fcntl.LOCK_UN)
            finally:
                self._lock_file.close()
                self._lock_file = None

    def _log(self, message, *args):
        if self._logger is not None:
            self._logger.info(message, *args)
