import Foundation

public enum BridgeMethod: String, Codable, Sendable {
    case hello
    case ping
    case shutdown = "shutdown"
    case getStatus = "get_status"
    case getPlugins = "get_plugins"
    case getSelectedTrack = "get_selected_track"
    case getMixer = "get_mixer"
    case loadPlugin = "load_plugin"
    case refreshLibrary = "refresh_library"
}

/// JSON value used for method-specific parameters and results.
public indirect enum JSONValue: Codable, Sendable, Equatable {
    case null
    case bool(Bool)
    case integer(Int64)
    case number(Double)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Int64.self) {
            self = .integer(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([JSONValue].self) {
            self = .array(value)
        } else if let value = try? container.decode([String: JSONValue].self) {
            self = .object(value)
        } else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Unsupported JSON value"
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .null: try container.encodeNil()
        case .bool(let value): try container.encode(value)
        case .integer(let value): try container.encode(value)
        case .number(let value): try container.encode(value)
        case .string(let value): try container.encode(value)
        case .array(let value): try container.encode(value)
        case .object(let value): try container.encode(value)
        }
    }
}

public struct BridgeRequest: Codable, Sendable, Equatable {
    public let protocolVersion: Int
    public let id: String
    public let method: BridgeMethod
    public let params: JSONValue?

    public init(
        id: String = UUID().uuidString.lowercased(),
        method: BridgeMethod,
        params: JSONValue? = nil,
        protocolVersion: Int = 1
    ) {
        self.protocolVersion = protocolVersion
        self.id = id
        self.method = method
        self.params = params
    }

    enum CodingKeys: String, CodingKey {
        case protocolVersion = "protocol_version"
        case id
        case method
        case params
    }
}

public struct BridgeFailure: Codable, Sendable, Equatable {
    public let code: String
    public let message: String
    public let retryable: Bool

    public init(code: String, message: String, retryable: Bool = false) {
        self.code = code
        self.message = message
        self.retryable = retryable
    }
}

public struct BridgeResponse: Codable, Sendable, Equatable {
    public let protocolVersion: Int
    public let id: String
    public let ok: Bool
    public let result: JSONValue?
    public let error: BridgeFailure?

    enum CodingKeys: String, CodingKey {
        case protocolVersion = "protocol_version"
        case id
        case ok
        case result
        case error
    }
}

public struct BridgeHello: Decodable, Sendable, Equatable {
    public let protocolVersion: Int
    public let liveVersion: String?
    public let pythonVersion: String?
    public let capabilities: [String: Bool]?

    enum CodingKeys: String, CodingKey {
        case protocolVersion = "protocol_version"
        case liveVersion = "live_version"
        case pythonVersion = "python_version"
        case capabilities
    }
}

public struct PluginItem: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public let name: String
    public let format: String
    public let vendor: String?

    public init(id: String, name: String, format: String, vendor: String? = nil) {
        self.id = id
        self.name = name
        self.format = format
        self.vendor = vendor
    }
}

public struct PluginPage: Codable, Sendable, Equatable {
    public let items: [PluginItem]
    public let nextOffset: Int?
    public let total: Int
    public let truncated: Bool

    public init(items: [PluginItem], nextOffset: Int?, total: Int, truncated: Bool) {
        self.items = items
        self.nextOffset = nextOffset
        self.total = total
        self.truncated = truncated
    }

    enum CodingKeys: String, CodingKey {
        case items
        case nextOffset = "next_offset"
        case total
        case truncated
    }
}

public struct SelectedTrack: Codable, Sendable, Equatable, Identifiable {
    public let id: String?
    public let name: String

    public init(id: String?, name: String) {
        self.id = id
        self.name = name
    }
}

public struct MixerSnapshot: Codable, Sendable, Equatable {
    public let setName: String
    public let setPath: String
    public let setID: String
    public let liveVersion: String?
    public let tracks: [MixerTrack]
    public let returnTracks: [MixerTrack]
    public let masterTrack: MixerTrack
    enum CodingKeys: String, CodingKey {
        case setName = "set_name"
        case setPath = "set_path"
        case setID = "set_id"
        case liveVersion = "live_version"
        case tracks
        case returnTracks = "return_tracks"
        case masterTrack = "master_track"
    }
}

public struct MixerTrack: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public let name: String
    public let kind: String
    public let color: Int?
    public let volume: Double?
    public let pan: Double?
    public let devices: [MixerDevice]
    enum CodingKeys: String, CodingKey { case id, name, kind, color, volume, pan, devices }
}

public struct MixerDevice: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public let name: String
    public let className: String
    public let chains: [MixerChain]
    public let presetName: String?
    public let presetIndex: Int?
    public let parameters: [MixerParameter]
    enum CodingKeys: String, CodingKey {
        case id, name, chains, parameters
        case className = "class_name"
        case presetName = "preset_name"
        case presetIndex = "preset_index"
    }
}

public struct MixerChain: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public let name: String
    public let devices: [MixerDevice]
}

public struct MixerParameter: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public let name: String
    public let value: Double?
    public let displayValue: Double?
    enum CodingKeys: String, CodingKey { case id, name, value; case displayValue = "display_value" }
}

public enum BridgeLineCodec {
    /// Maximum frame size guards against accidentally unbounded IPC messages.
    public static let maximumFrameBytes = 8 * 1024 * 1024

    public static func encodeRequest(_ request: BridgeRequest) throws -> Data {
        try encodeLine(request)
    }

    public static func decodeResponse(from line: Data) throws -> BridgeResponse {
        let payload = try normalized(line)
        return try JSONDecoder().decode(BridgeResponse.self, from: payload)
    }

    private static func encodeLine<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        var data = try encoder.encode(value)
        guard data.count <= maximumFrameBytes else {
            throw BridgeCodecError.frameTooLarge
        }
        data.append(0x0A)
        return data
    }

    private static func normalized(_ line: Data) throws -> Data {
        guard line.count <= maximumFrameBytes else {
            throw BridgeCodecError.frameTooLarge
        }
        var payload = line
        while payload.last == 0x0A || payload.last == 0x0D {
            payload.removeLast()
        }
        guard !payload.isEmpty else {
            throw BridgeCodecError.emptyFrame
        }
        return payload
    }
}

public enum BridgeCodecError: Error, Equatable {
    case emptyFrame
    case frameTooLarge
}
