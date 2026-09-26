import Foundation

public struct LoadPluginResult: Codable, Sendable, Equatable {
    public let pluginID: String
    public let trackID: String
    public let trackName: String

    enum CodingKeys: String, CodingKey {
        case pluginID = "plugin_id"
        case trackID = "track_id"
        case trackName = "track_name"
    }
}

public enum AbletonLibraryError: Error, LocalizedError, Sendable {
    case bridge(code: String, message: String, retryable: Bool)
    case invalidResponse
    case liveVersionUnavailable
    case unsupportedLiveVersion(String)

    public var errorDescription: String? {
        switch self {
        case .bridge(let code, let message, _):
            switch code {
            case "live_unavailable": return "Ableton Live is open but not ready. Wait a moment and refresh the library."
            case "browser_unavailable": return "Ableton Live's plugin Browser is not ready. Refresh the library in a moment."
            case "plugin_not_found": return "This plugin is no longer available in Ableton Live. Refresh the library and select it again."
            case "track_unavailable": return "No track is selected in Ableton Live. Select a track and try again."
            case "incompatible_track": return "The selected Ableton Live track cannot load this plugin. Select a compatible audio or MIDI track."
            case "track_not_empty": return "The selected track is no longer empty. Choose another track and try again."
            case "load_failed": return "Ableton Live could not load this plugin. Check the selected track and plugin, then try again."
            case "invalid_plugin": return "Ableton Live rejected this plugin ID. Refresh the library and select the plugin again."
            case "unsupported_protocol": return "PlugSpot and the Live Remote Script use different protocol versions. Update or reinstall the Remote Script."
            default: return message.isEmpty ? "Ableton Live rejected the request (\(code))." : message
            }
        case .invalidResponse: return "Ableton Live returned an invalid response."
        case .liveVersionUnavailable:
            return "PlugSpot could not identify the Ableton Live version. Update Live and the PlugSpot Remote Script, then try again."
        case .unsupportedLiveVersion(let version):
            return "Ableton Live \(version) is not supported yet. PlugSpot has only validated Live 12.4.2 and can try later 12.4.x updates."
        }
    }
}

/// High-level, UI-independent operations for the Ableton Live bridge.
public struct AbletonLibrary: Sendable {
    private let bridge: any AbletonBridge

    public init(bridge: any AbletonBridge = UnixDomainSocketClient()) {
        self.bridge = bridge
    }

    public func hello() async throws -> BridgeHello {
        let response = try await bridge.send(BridgeRequest(method: .hello))
        return try decodeResult(response)
    }

    public func plugins() async throws -> [PluginItem] {
        var allItems: [PluginItem] = []
        var offset = 0
        var expectedTotal: Int?

        repeat {
            let response = try await bridge.send(
                BridgeRequest(
                    method: .getPlugins,
                    params: .object(["offset": .integer(Int64(offset)), "limit": .integer(250)])
                )
            )
            let page: PluginPage = try decodeResult(response)
            if let expectedTotal, expectedTotal != page.total {
                throw AbletonLibraryError.invalidResponse
            }
            if expectedTotal == nil, page.total >= 0 {
                allItems.reserveCapacity(page.total)
            }
            expectedTotal = page.total
            allItems.append(contentsOf: page.items)
            guard let nextOffset = page.nextOffset else { break }
            guard nextOffset > offset, nextOffset <= page.total else {
                throw AbletonLibraryError.invalidResponse
            }
            offset = nextOffset
        } while allItems.count < (expectedTotal ?? Int.max)

        guard allItems.count == expectedTotal else { throw AbletonLibraryError.invalidResponse }
        return allItems
    }

    public func loadPlugin(id: String) async throws -> LoadPluginResult {
        let response = try await bridge.send(
            BridgeRequest(
                method: .loadPlugin,
                params: .object(["plugin_id": .string(id)])
            )
        )
        return try decodeResult(response)
    }

    public func mixer() async throws -> MixerSnapshot {
        let response = try await bridge.send(BridgeRequest(method: .getMixer))
        return try decodeResult(response)
    }

    private func decodeResult<Value: Decodable>(_ response: BridgeResponse) throws -> Value {
        guard response.ok else {
            let failure = response.error
            throw AbletonLibraryError.bridge(
                code: failure?.code ?? "unknown_error",
                message: failure?.message ?? "Ableton Live rejected the request.",
                retryable: failure?.retryable ?? false
            )
        }
        guard let result = response.result else { throw AbletonLibraryError.invalidResponse }
        let data = try JSONEncoder().encode(result)
        return try JSONDecoder().decode(Value.self, from: data)
    }
}
