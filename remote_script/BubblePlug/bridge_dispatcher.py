"""JSON Lines request validation and dispatch for the local BubblePlug bridge."""

import json

from .live_adapter import LiveAdapterError


class BridgeDispatcher:
    PROTOCOL_VERSION = 1
    MAX_FRAME_BYTES = 8 * 1024 * 1024
    MAX_REQUEST_ID_LENGTH = 128

    def __init__(self, live_adapter):
        self._live = live_adapter

    def handle_line(self, line):
        """Return one UTF-8 JSON response line for one request line."""
        request_id = ""
        try:
            if isinstance(line, bytes):
                if len(line) > self.MAX_FRAME_BYTES:
                    raise _ProtocolError("frame_too_large", "Request frame exceeds the size limit")
                line = line.decode("utf-8")
            elif not isinstance(line, str):
                raise _ProtocolError("invalid_request", "Request must be UTF-8 JSON")
            if len(line.encode("utf-8")) > self.MAX_FRAME_BYTES:
                raise _ProtocolError("frame_too_large", "Request frame exceeds the size limit")

            request = json.loads(line.strip())
            if not isinstance(request, dict):
                raise _ProtocolError("invalid_request", "Request must be a JSON object")
            candidate_id = request.get("id", "")
            if not isinstance(candidate_id, str) or not candidate_id or len(candidate_id) > self.MAX_REQUEST_ID_LENGTH:
                raise _ProtocolError("invalid_request", "id must be a non-empty string of at most 128 characters")
            request_id = candidate_id

            response = self._dispatch(request, request_id)
        except _ProtocolError as exc:
            response = self._failure(request_id, exc.code, str(exc), exc.retryable)
        except (UnicodeDecodeError, json.JSONDecodeError) as exc:
            response = self._failure(request_id, "invalid_request", "Request is not valid UTF-8 JSON")
        except Exception:
            response = self._failure(request_id, "internal_error", "Bridge request failed")

        try:
            encoded = json.dumps(response, ensure_ascii=False, separators=(",", ":")).encode("utf-8")
            if len(encoded) + 1 > self.MAX_FRAME_BYTES:
                response = self._failure(request_id, "frame_too_large", "Response frame exceeds the size limit")
                encoded = json.dumps(response, separators=(",", ":")).encode("utf-8")
            return encoded + b"\n"
        except Exception:
            return b'{"protocol_version":1,"id":"","ok":false,"error":{"code":"internal_error","message":"Could not encode response","retryable":false}}\n'

    def _dispatch(self, request, request_id):
        protocol_version = request.get("protocol_version")
        if isinstance(protocol_version, bool) or protocol_version != self.PROTOCOL_VERSION:
            return self._failure(request_id, "unsupported_protocol", "Unsupported protocol version")

        method = request.get("method")
        if not isinstance(method, str):
            return self._failure(request_id, "invalid_request", "method must be a string")
        params = request.get("params", {})
        if params is None:
            params = {}
        if not isinstance(params, dict):
            return self._failure(request_id, "invalid_params", "params must be an object")

        try:
            if method == "hello":
                result = {
                    "protocol_version": self.PROTOCOL_VERSION,
                    "live_version": self._live.get_live_version(),
                    "python_version": self._live.get_python_version(),
                    "capabilities": {
                        "get_plugins": True,
                        "get_selected_track": True,
                        "get_mixer": True,
                        "load_plugin": True,
                        "refresh_library": True,
                    },
                }
            elif method == "ping":
                result = {"pong": True}
            elif method == "shutdown":
                result = {"stopped": True}
            elif method == "get_status":
                result = {
                    "connected": True,
                    "live_version": self._live.get_live_version(),
                    "selected_track": self._live.get_selected_track(),
                }
            elif method == "get_plugins":
                result = self._live.get_plugins(
                    offset=params.get("offset", 0),
                    limit=params.get("limit", self._live.DEFAULT_PAGE_SIZE),
                )
            elif method == "get_selected_track":
                result = self._live.get_selected_track()
            elif method == "get_mixer":
                result = self._live.get_mixer()
            elif method == "refresh_library":
                result = self._live.refresh_library()
            elif method == "load_plugin":
                plugin_id = params.get("plugin_id")
                if not isinstance(plugin_id, str) or not plugin_id:
                    return self._failure(request_id, "invalid_params", "plugin_id must be a non-empty string")
                result = self._live.load_plugin(plugin_id)
            else:
                return self._failure(request_id, "unknown_method", "Unknown bridge method")
            return {
                "protocol_version": self.PROTOCOL_VERSION,
                "id": request_id,
                "ok": True,
                "result": result,
            }
        except LiveAdapterError as exc:
            return self._failure(request_id, exc.code, str(exc), exc.retryable)

    @classmethod
    def _failure(cls, request_id, code, message, retryable=False):
        return {
            "protocol_version": cls.PROTOCOL_VERSION,
            "id": request_id,
            "ok": False,
            "error": {"code": code, "message": message, "retryable": retryable},
        }


class _ProtocolError(Exception):
    def __init__(self, code, message, retryable=False):
        super().__init__(message)
        self.code = code
        self.retryable = retryable
