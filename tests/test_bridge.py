import json
import socket
import sys
import tempfile
import threading
import time
import types
import unittest
from pathlib import Path

# The Remote Script package imports Ableton at package entry, which is
# unavailable in standalone tests. Load its pure-Python modules as a package.
package = types.ModuleType("remote_script.BubblePlug")
package.__path__ = [str(Path(__file__).resolve().parents[1] / "remote_script/BubblePlug")]
sys.modules["remote_script.BubblePlug"] = package

from remote_script.BubblePlug.bridge_dispatcher import BridgeDispatcher
from remote_script.BubblePlug.bridge_server import BridgeServer


class FakeLive:
    DEFAULT_PAGE_SIZE = 100

    def get_live_version(self):
        return "12.4.2"

    def get_python_version(self):
        return "3.11.0"

    def get_selected_track(self):
        return {"id": "1", "name": "Test"}

    def get_plugins(self, offset, limit):
        return {"items": [], "next_offset": None, "total": 0, "truncated": False}


def request(method="ping", **fields):
    return json.dumps({"protocol_version": 1, "id": "audit", "method": method, **fields}).encode() + b"\n"


class DispatcherTests(unittest.TestCase):
    def setUp(self):
        self.dispatcher = BridgeDispatcher(FakeLive())

    def response(self, line):
        return json.loads(self.dispatcher.handle_line(line))

    def test_ping_and_hello(self):
        self.assertEqual(self.response(request())["result"], {"pong": True})
        self.assertEqual(self.response(request("hello"))["result"]["live_version"], "12.4.2")

    def test_rejects_invalid_frames(self):
        for line, code in [
            (b"not json\n", "invalid_request"),
            (b"[]\n", "invalid_request"),
            (b'{"protocol_version":true,"id":"a","method":"ping"}\n', "unsupported_protocol"),
            (request("unknown"), "unknown_method"),
            (request("load_plugin"), "invalid_params"),
            (request("ping", params=[]), "invalid_params"),
        ]:
            with self.subTest(line=line[:40]):
                self.assertEqual(self.response(line)["error"]["code"], code)

    def test_rejects_oversize_frame(self):
        line = b"x" * (BridgeDispatcher.MAX_FRAME_BYTES + 1)
        self.assertEqual(self.response(line)["error"]["code"], "frame_too_large")


class ServerTests(unittest.TestCase):
    def test_socket_roundtrip_and_cleanup(self):
        with tempfile.TemporaryDirectory() as temporary:
            server = BridgeServer()
            server._socket_path = str(Path(temporary) / "bridge.sock")
            server.LOCK_RELATIVE_PATH = str(Path(temporary) / "bridge.lock")
            server.start()
            received = []

            def client():
                with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as connection:
                    connection.settimeout(3)
                    connection.connect(server._socket_path)
                    connection.sendall(request())
                    received.append(connection.makefile("rb").readline())

            worker = threading.Thread(target=client)
            worker.start()
            deadline = time.monotonic() + 3
            while worker.is_alive() and time.monotonic() < deadline:
                server.process_pending(BridgeDispatcher(FakeLive()))
                time.sleep(0.01)
            worker.join(timeout=1)
            self.assertFalse(worker.is_alive())
            self.assertEqual(json.loads(received[0])["result"], {"pong": True})
            server.stop()
            self.assertFalse(Path(server._socket_path).exists())


if __name__ == "__main__":
    unittest.main()
