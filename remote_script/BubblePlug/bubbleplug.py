"""Ableton Live Control Surface entry point for the BubblePlug bridge."""

import logging
import hashlib
import json
import os
import queue
import re
import subprocess
import sys
import tempfile
import threading
import time
import traceback

from ableton.v2.control_surface import ControlSurface

from .bridge_dispatcher import BridgeDispatcher
from .bridge_server import BridgeServer
from .live_adapter import LiveAdapter, LiveAdapterError


def _make_logger():
    logger = logging.getLogger("BubblePlug.Remote")
    if logger.handlers:
        return logger

    logger.setLevel(logging.INFO)
    log_path = os.path.join(os.path.expanduser("~/Documents"), "bubbleplug-remote.log")
    handler = logging.FileHandler(log_path, encoding="utf-8")
    handler.setFormatter(logging.Formatter("%(asctime)s %(levelname)s %(message)s"))
    logger.addHandler(handler)
    return logger


class BubblePlug(ControlSurface):
    """Logs basic Live state and safe Browser API discovery information."""

    def __init__(self, c_instance):
        self._bubbleplug_logger = _make_logger()
        self._bridge_server = None
        self._launcher = None
        self._mixer_snapshot_due = None
        self._mixer_snapshot_dirty = False
        self._snapshot_queue = queue.Queue()
        self._snapshot_worker = threading.Thread(
            target=self._write_mixer_snapshots, name="BubblePlugSnapshotWriter", daemon=True
        )
        self._snapshot_worker.start()
        super().__init__(c_instance)
        self._bubbleplug_logger.info("Remote Script initialising")
        self._log_live_state()

    def _log_live_state(self):
        try:
            # Live versions expose these as either methods or properties.
            application = self.application
            song = self.song
            self._bubbleplug_logger.info("Embedded Python=%s", sys.version.replace("\n", " "))
            self._adapter = LiveAdapter(
                application, song, self._bubbleplug_logger, self._mark_mixer_snapshot_dirty
            )
            self._dispatcher = BridgeDispatcher(self._adapter)
            self._start_bridge()
            self._start_launcher()
            self._save_mixer_snapshot()
            self._bubbleplug_logger.info("Live version=%s", self._adapter.get_live_version())
            try:
                self._bubbleplug_logger.info("Selected track=%r", self._adapter.get_selected_track())
            except LiveAdapterError as exc:
                self._bubbleplug_logger.warning("Selected track unavailable: %s", exc)

            browser = getattr(application, "browser", None)
            self._bubbleplug_logger.info("Browser object available=%s", browser is not None)
            if browser is not None:
                names = sorted(name for name in dir(browser) if not name.startswith("_"))
                self._bubbleplug_logger.info("Browser data attributes=%s", names)

                for name in (
                    "plugins", "instruments", "audio_effects", "midi_effects",
                    "sounds", "drums", "max_for_live", "user_folders", "user_library",
                ):
                    try:
                        node = getattr(browser, name)
                    except Exception as exc:
                        self._bubbleplug_logger.info("Browser candidate %s unavailable: %s", name, exc)
                        continue
                    if node is not None:
                        self._bubbleplug_logger.info(
                            "Browser candidate %s: type=%s name=%r children=%s",
                            name,
                            type(node).__name__,
                            getattr(node, "name", None),
                            self._safe_child_count(node),
                        )
                page = self._adapter.get_plugins(offset=0, limit=5)
                self._bubbleplug_logger.info(
                    "VST3 catalog page: returned=%d total=%d next_offset=%r truncated=%s",
                    len(page["items"]), page["total"], page["next_offset"], page["truncated"],
                )
                self._bubbleplug_logger.info("VST3 catalog sample=%r", page["items"])
        except LiveAdapterError as exc:
            self._bubbleplug_logger.error("Live adapter initialisation failed [%s]: %s", exc.code, exc)
        except Exception:
            self._bubbleplug_logger.error("State probe failed:\n%s", traceback.format_exc())

    def _start_bridge(self):
        server = None
        try:
            server = BridgeServer(self._bubbleplug_logger)
            server.start()
            self._bridge_server = server
            self.schedule_message(1, self._process_bridge_requests)
        except Exception:
            if server is not None:
                try:
                    server.stop()
                except Exception:
                    self._bubbleplug_logger.error("Bridge cleanup failed:\n%s", traceback.format_exc())
            self._bridge_server = None
            self._bubbleplug_logger.error("Bridge startup failed:\n%s", traceback.format_exc())

    def _start_launcher(self):
        launcher = os.path.expanduser("~/Library/Application Support/BubblePlug/launch.sh")
        if not os.path.isfile(launcher):
            self._bubbleplug_logger.warning("BubblePlug launcher missing: %s", launcher)
            return
        try:
            self._launcher = subprocess.Popen(
                ["/bin/zsh", launcher],
                stdin=subprocess.DEVNULL,
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
                close_fds=True,
            )
            self._bubbleplug_logger.info("BubblePlug launcher started pid=%s", self._launcher.pid)
        except Exception:
            self._bubbleplug_logger.error("BubblePlug launcher failed:\n%s", traceback.format_exc())

    def _process_bridge_requests(self):
        server = self._bridge_server
        if server is None or not server.running:
            return
        try:
            server.process_pending(self._dispatcher)
        except Exception:
            self._bubbleplug_logger.error("Bridge dispatch failed:\n%s", traceback.format_exc())
        self._maybe_save_mixer_snapshot()
        if self._bridge_server is server and server.running:
            self.schedule_message(1, self._process_bridge_requests)

    def _mark_mixer_snapshot_dirty(self):
        self._mixer_snapshot_dirty = True
        self._mixer_snapshot_due = time.time() + 2.0

    def _maybe_save_mixer_snapshot(self):
        if not self._mixer_snapshot_dirty or self._mixer_snapshot_due is None:
            return
        if time.time() < self._mixer_snapshot_due:
            return
        try:
            if bool(getattr(self.song, "is_playing", False)):
                # Wait for transport to stop before snapshotting animated parameters.
                self._mixer_snapshot_due = time.time() + 1.0
                return
        except Exception:
            pass
        self._save_mixer_snapshot()

    def _save_mixer_snapshot(self):
        try:
            self._adapter.refresh_mixer_listeners()
            snapshot = self._adapter.get_mixer()
            # Live API objects are read above on Live's scheduled callback.
            # Only ordinary strings, numbers, lists and dictionaries cross to
            # the worker; JSON encoding and disk sync never run on Live's loop.
            self._snapshot_queue.put(snapshot)
            self._mixer_snapshot_dirty = False
            self._mixer_snapshot_due = None
            self._bubbleplug_logger.info("Mixer recovery snapshot queued for background write")
        except Exception:
            self._bubbleplug_logger.error("Could not collect mixer recovery snapshot:\n%s", traceback.format_exc())

    def _write_mixer_snapshots(self):
        while True:
            snapshot = self._snapshot_queue.get()
            if snapshot is None:
                return
            try:
                set_path = snapshot.get("set_path") or ""
                set_name = snapshot.get("set_name") or "Unsaved-Set"
                set_id = snapshot.get("set_id") or "unsaved"
                digest = hashlib.sha256((set_path or set_id).encode("utf-8")).hexdigest()[:12]
                safe_name = re.sub(r"[^A-Za-z0-9._ -]+", "-", set_name).strip(" .-") or "Unsaved-Set"
                directory = os.path.expanduser("~/Library/Application Support/BubblePlug/MixerSnapshots")
                os.makedirs(directory, mode=0o700, exist_ok=True)
                os.chmod(directory, 0o700)
                target = os.path.join(directory, "{}-{}.json".format(safe_name, digest))
                document = {
                    "schema_version": 1,
                    "saved_at": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
                    "snapshot": snapshot,
                }
                descriptor, temporary = tempfile.mkstemp(prefix=".bubbleplug-snapshot-", dir=directory)
                try:
                    os.fchmod(descriptor, 0o600)
                    with os.fdopen(descriptor, "w", encoding="utf-8") as stream:
                        json.dump(document, stream, ensure_ascii=False, sort_keys=True, separators=(",", ":"))
                        stream.flush()
                        os.fsync(stream.fileno())
                    os.replace(temporary, target)
                finally:
                    if os.path.exists(temporary):
                        os.unlink(temporary)
                self._bubbleplug_logger.info("Mixer recovery snapshot saved: %s", target)
            except Exception:
                self._bubbleplug_logger.error("Could not write mixer recovery snapshot:\n%s", traceback.format_exc())

    @staticmethod
    def _safe_child_count(node):
        """Report whether the node exposes children without traversing the tree."""
        try:
            children = getattr(node, "children")
            return len(children)
        except Exception:
            return "unavailable"


    def disconnect(self):
        self._bubbleplug_logger.info("Remote Script disconnecting")
        self._stop_launcher()
        try:
            self._snapshot_queue.put(None)
            self._snapshot_worker.join(timeout=2.0)
        except Exception:
            self._bubbleplug_logger.error("Mixer snapshot writer shutdown failed:\n%s", traceback.format_exc())
        try:
            if getattr(self, "_adapter", None) is not None:
                self._adapter.close_mixer_listeners()
        except Exception:
            self._bubbleplug_logger.error("Mixer listener cleanup failed:\n%s", traceback.format_exc())
        try:
            if self._bridge_server is not None:
                self._bridge_server.stop()
                self._bridge_server = None
        except Exception:
            self._bubbleplug_logger.error("Bridge shutdown failed:\n%s", traceback.format_exc())
        try:
            super().disconnect()
        except Exception:
            self._bubbleplug_logger.error("Control Surface disconnect failed:\n%s", traceback.format_exc())

    def _stop_launcher(self):
        process = self._launcher
        self._launcher = None
        if process is None:
            return
        # The launcher is also the watcher that quits the UI when the bridge
        # socket is removed below. Let it observe that transition and exit.
        self._bubbleplug_logger.info("BubblePlug launcher will exit after bridge shutdown")
