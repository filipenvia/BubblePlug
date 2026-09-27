"""Ableton Live adapter for PlugSpot."""

from urllib.parse import unquote
import uuid


class LiveAdapterError(Exception):
    def __init__(self, code, message, retryable=False):
        super().__init__(message)
        self.code = code
        self.retryable = retryable


class LiveAdapter:
    DEFAULT_PAGE_SIZE = 100
    MAX_PAGE_SIZE = 250
    MAX_BROWSER_ITEMS = 10000
    VST3_URI_PREFIX = "query:Plugins#VST3:"

    def __init__(self, application, song, logger=None, on_mixer_change=None):
        self._application = application
        self._song = song
        self._logger = logger
        self._plugin_catalog = None
        self._browser_items = {}
        self._on_mixer_change = on_mixer_change
        self._mixer_listener = self._notify_mixer_change
        self._mixer_listeners = []
        self._mixer_listeners_stale = False
        self._unsaved_set_id = str(uuid.uuid4())
        self._bind_mixer_listeners()

    def get_live_version(self):
        version = []
        for method_name in ("get_major_version", "get_minor_version", "get_bugfix_version"):
            method = getattr(self._application, method_name, None)
            if not callable(method):
                return None
            version.append(str(method()))
        return ".".join(version)

    @staticmethod
    def get_python_version():
        import sys
        return "%d.%d.%d" % sys.version_info[:3]

    def get_selected_track(self):
        try:
            track = self._song.view.selected_track
        except Exception as exc:
            raise LiveAdapterError("track_unavailable", "Could not read selected track", True) from exc
        if track is None:
            raise LiveAdapterError("track_unavailable", "There is no selected track", True)

        raw_id = getattr(track, "id", None)
        return {
            "id": str(raw_id) if isinstance(raw_id, (int, str)) else None,
            "name": str(getattr(track, "name", "")),
        }

    def get_mixer(self):
        """Return a read-only snapshot of Live tracks and their device chains."""
        try:
            return {
                "set_name": str(getattr(self._song, "name", "")),
                "set_path": str(getattr(self._song, "file_path", "")),
                "set_id": self._unsaved_set_id,
                "live_version": self.get_live_version(),
                "tracks": [self._mixer_track(track, "track", "track:%s" % index) for index, track in enumerate(self._song.tracks)],
                "return_tracks": [self._mixer_track(track, "return", "return:%s" % index) for index, track in enumerate(self._song.return_tracks)],
                "master_track": self._mixer_track(self._song.master_track, "master", "master"),
            }
        except Exception as exc:
            raise LiveAdapterError("mixer_unavailable", "Could not read Live mixer", True) from exc

    @classmethod
    def _mixer_track(cls, track, fallback_kind, identity):
        try:
            if fallback_kind in ("master", "return"):
                kind = fallback_kind
            elif bool(getattr(track, "is_foldable", False)):
                kind = "group"
            elif bool(getattr(track, "has_midi_input", False)):
                kind = "midi"
            else:
                kind = "audio"
            return {
                "id": identity,
                "name": str(getattr(track, "name", "")),
                "kind": kind,
                "color": getattr(track, "color", None),
                "volume": cls._mixer_parameter(track, "volume"),
                "pan": cls._mixer_parameter(track, "panning"),
                "devices": [cls._mixer_device(device, "%s/device:%s" % (identity, index)) for index, device in enumerate(getattr(track, "devices", []))
                            if getattr(device, "class_name", "") != "MixerDevice"],
            }
        except Exception:
            return {"id": identity, "name": str(getattr(track, "name", "")),
                    "kind": fallback_kind, "color": None, "volume": None, "pan": None, "devices": []}

    @staticmethod
    def _mixer_parameter(track, name):
        try:
            return float(getattr(track.mixer_device, name).value)
        except Exception:
            return None

    @classmethod
    def _mixer_device(cls, device, identity):
        chains = []
        if bool(getattr(device, "can_have_chains", False)):
            for chain_index, chain in enumerate(getattr(device, "chains", [])):
                chains.append({
                    "id": "%s/chain:%s" % (identity, chain_index),
                    "name": str(getattr(chain, "name", "")),
                    "devices": [cls._mixer_device(nested, "%s/chain:%s/device:%s" % (identity, chain_index, index)) for index, nested in enumerate(getattr(chain, "devices", []))
                                if getattr(nested, "class_name", "") != "MixerDevice"],
                })
        preset_name, preset_index = cls._mixer_preset(device)
        parameters = []
        try:
            for index, parameter in enumerate(getattr(device, "parameters", [])):
                parameters.append({
                    "id": str(index),
                    "name": str(getattr(parameter, "name", "")),
                    "value": cls._safe_float(getattr(parameter, "value", None)),
                    "display_value": cls._safe_float(getattr(parameter, "display_value", None)),
                })
        except Exception:
            pass
        return {"id": identity, "name": str(getattr(device, "name", "")),
                "class_name": str(getattr(device, "class_name", "")), "chains": chains,
                "preset_name": preset_name, "preset_index": preset_index, "parameters": parameters}

    @classmethod
    def _mixer_preset(cls, device):
        if getattr(device, "class_name", "") != "PluginDevice":
            return None, None
        try:
            index = int(device.selected_preset_index)
            presets = list(device.presets)
            if 0 <= index < len(presets):
                return str(presets[index]), index
            return None, index
        except Exception:
            return None, None

    @staticmethod
    def _safe_float(value):
        try:
            return float(value)
        except (TypeError, ValueError, OverflowError):
            return None

    def _notify_mixer_change(self, *args):
        self._mixer_listeners_stale = True
        if self._on_mixer_change is not None:
            try:
                self._on_mixer_change()
            except Exception as exc:
                self._log("Could not schedule mixer snapshot save: %s", exc)

    def _bind_mixer_listeners(self):
        self._remove_mixer_listeners()
        for property_name in ("tracks", "return_tracks", "is_playing"):
            self._add_mixer_listener(self._song, property_name)
        try:
            tracks = list(self._song.tracks) + list(self._song.return_tracks) + [self._song.master_track]
        except Exception:
            tracks = []
        seen = set()
        for track in tracks:
            if track is None or id(track) in seen:
                continue
            seen.add(id(track))
            for name in ("name", "color", "devices"):
                self._add_mixer_listener(track, name)
            try:
                mixer = track.mixer_device
            except Exception:
                mixer = None
            for name in ("volume", "panning"):
                try:
                    parameter = getattr(mixer, name) if mixer is not None else None
                except Exception:
                    parameter = None
                if parameter is not None:
                    self._add_mixer_listener(parameter, "value")
            for device in getattr(track, "devices", []):
                self._bind_device_tree(device, seen)
        self._mixer_listeners_stale = False

    def _bind_device_tree(self, device, seen):
        if device is None or id(device) in seen:
            return
        seen.add(id(device))
        for name in ("name", "is_active", "parameters", "chains", "presets", "selected_preset_index"):
            self._add_mixer_listener(device, name)
        for parameter in getattr(device, "parameters", []):
            self._add_mixer_listener(parameter, "value")
        for chain_index, chain in enumerate(getattr(device, "chains", [])):
            for name in ("name", "devices", "mute", "solo"):
                self._add_mixer_listener(chain, name)
            for nested in getattr(chain, "devices", []):
                self._bind_device_tree(nested, seen)

    def _add_mixer_listener(self, obj, property_name):
        add_name = "add_{}_listener".format(property_name)
        add_listener = getattr(obj, add_name, None)
        if not callable(add_listener):
            return
        try:
            add_listener(self._mixer_listener)
            self._mixer_listeners.append((obj, property_name, self._mixer_listener))
        except Exception:
            pass

    def refresh_mixer_listeners(self):
        if self._mixer_listeners_stale:
            self._bind_mixer_listeners()

    def close_mixer_listeners(self):
        self._remove_mixer_listeners()

    def _remove_mixer_listeners(self):
        for obj, property_name, callback in self._mixer_listeners:
            remove_listener = getattr(obj, "remove_{}_listener".format(property_name), None)
            if callable(remove_listener):
                try:
                    remove_listener(callback)
                except Exception:
                    pass
        self._mixer_listeners = []

    def get_plugins(self, offset=0, limit=DEFAULT_PAGE_SIZE):
        offset = self._validate_integer("offset", offset, minimum=0)
        limit = self._validate_integer("limit", limit, minimum=1)
        if limit > self.MAX_PAGE_SIZE:
            raise LiveAdapterError(
                "invalid_params",
                "limit must be at most %d" % self.MAX_PAGE_SIZE,
            )

        catalog = self._get_plugin_catalog()
        end = min(offset + limit, len(catalog["items"]))
        items = catalog["items"][offset:end]
        return {
            "items": items,
            "next_offset": end if end < len(catalog["items"]) else None,
            "total": len(catalog["items"]),
            "truncated": catalog["truncated"],
        }

    def refresh_library(self):
        """Discard PlugSpot's snapshot and read the current Live Browser again."""
        self._plugin_catalog = None
        self._browser_items = {}
        catalog = self._get_plugin_catalog()
        return {"refreshed": True, "total": len(catalog["items"]), "truncated": catalog["truncated"]}

    def load_plugin(self, plugin_id):
        """Load an exact catalogued VST3 onto a compatible selected track."""
        if not isinstance(plugin_id, str) or not plugin_id.startswith(self.VST3_URI_PREFIX):
            raise LiveAdapterError("invalid_plugin", "Only catalogued VST3 plug-ins can be loaded")
        self._get_plugin_catalog()
        item = self._browser_items.get(plugin_id)
        if item is None:
            raise LiveAdapterError("plugin_not_found", "Plug-in is not in the current VST3 catalog")

        track = self._selected_track_object()
        try:
            has_midi_input = bool(track.has_midi_input)
        except Exception:
            has_midi_input = False
        try:
            has_audio_input = bool(track.has_audio_input)
        except Exception:
            has_audio_input = False
        if not has_midi_input and not has_audio_input:
            raise LiveAdapterError("incompatible_track", "Select a MIDI or audio track")

        # Permit repeated loads on a track so PlugSpot can build chains. Live's
        # Browser decides whether the requested device is compatible with the
        # selected track and reports load failures through its API.
        try:
            self._application.browser.load_item(item)
        except Exception as exc:
            raise LiveAdapterError("load_failed", "Live could not load the selected VST3 plug-in", True) from exc
        self._log("Requested VST3 load: name=%r uri=%r track=%r", item.name, plugin_id, track.name)
        return {"plugin_id": plugin_id, "track_id": str(getattr(track, "id", "")), "track_name": str(track.name)}

    def _selected_track_object(self):
        try:
            track = self._song.view.selected_track
        except Exception as exc:
            raise LiveAdapterError("track_unavailable", "Could not read selected track", True) from exc
        if track is None:
            raise LiveAdapterError("track_unavailable", "There is no selected track", True)
        return track

    def _get_plugin_catalog(self):
        if self._plugin_catalog is not None:
            return self._plugin_catalog

        browser = getattr(self._application, "browser", None)
        if browser is None:
            raise LiveAdapterError("browser_unavailable", "Live Browser is unavailable", True)
        root = getattr(browser, "plugins", None)
        if root is None:
            raise LiveAdapterError("browser_unavailable", "Live Plug-Ins Browser is unavailable", True)

        stack = [root]
        visited = 0
        truncated = False
        by_uri = {}
        browser_items = {}
        while stack:
            if visited >= self.MAX_BROWSER_ITEMS:
                truncated = True
                break
            node = stack.pop()
            visited += 1

            name = self._read(node, "name")
            uri = self._read(node, "uri")
            is_loadable = self._read(node, "is_loadable")
            if (
                isinstance(name, str)
                and isinstance(uri, str)
                and uri.startswith(self.VST3_URI_PREFIX)
                and is_loadable is True
                and not name.lower().endswith(".vstpreset")
            ):
                vendor = self._vendor_from_uri(uri)
                by_uri[uri] = {
                    "id": uri,
                    "name": name,
                    "format": "VST3",
                    "vendor": vendor,
                }
                browser_items[uri] = node

            children = self._read(node, "children")
            if children is not None:
                try:
                    stack.extend(reversed(list(children)))
                except Exception as exc:
                    self._log("Skipping unreadable Browser children: %s", exc)

        items = sorted(by_uri.values(), key=lambda item: (item["name"].casefold(), item["id"]))
        self._browser_items = browser_items
        self._plugin_catalog = {"items": items, "truncated": truncated, "visited": visited}
        self._log(
            "VST3 catalog built: items=%d visited=%d truncated=%s",
            len(items), visited, truncated,
        )
        return self._plugin_catalog

    @staticmethod
    def _read(obj, attribute):
        try:
            return getattr(obj, attribute)
        except Exception:
            return None

    @staticmethod
    def _validate_integer(name, value, minimum):
        if isinstance(value, bool) or not isinstance(value, int) or value < minimum:
            raise LiveAdapterError("invalid_params", "%s must be an integer >= %d" % (name, minimum))
        return value

    @staticmethod
    def _vendor_from_uri(uri):
        tail = uri.split(LiveAdapter.VST3_URI_PREFIX, 1)[1]
        vendor = tail.split(":", 1)[0]
        return unquote(vendor) if vendor else None

    def _log(self, message, *args):
        if self._logger is not None:
            self._logger.info(message, *args)
