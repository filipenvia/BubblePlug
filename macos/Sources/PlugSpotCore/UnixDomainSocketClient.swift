import Darwin
import Foundation

public protocol AbletonBridge: Sendable {
    func send(_ request: BridgeRequest) async throws -> BridgeResponse
}

public enum BridgeClientError: Error, Equatable, LocalizedError {
    case socketPathTooLong
    case connectionFailed(Int32)
    case writeFailed(Int32)
    case readFailed(Int32)
    case serverClosedConnection
    case frameTooLarge
    case invalidResponse

    public var errorDescription: String? {
        switch self {
        case .socketPathTooLong:
            return "PlugSpot cannot reach Ableton Live because the bridge path is too long. Reinstall the Live Remote Script in the default location."
        case .connectionFailed(let code):
            switch code {
            case ENOENT, ECONNREFUSED:
                return "Ableton Live is not connected. Open Live and make sure the PlugSpot Remote Script is enabled."
            case EACCES, EPERM:
                return "PlugSpot cannot access Ableton Live's local bridge. Check the PlugSpot Remote Script installation and macOS permissions."
            default:
                return "Could not connect to Ableton Live (system error \(code)). Try refreshing the library."
            }
        case .writeFailed, .readFailed, .serverClosedConnection:
            return "The connection to Ableton Live was interrupted. Refresh the library and try again."
        case .frameTooLarge, .invalidResponse:
            return "Ableton Live returned an unexpected bridge response. Restart Live and try again."
        }
    }
}

/// One request per local Unix socket connection. Blocking POSIX I/O runs away
/// from the main actor; the Live side serializes object-model access itself.
public final class UnixDomainSocketClient: AbletonBridge, @unchecked Sendable {
    public static let defaultSocketPath =
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/PlugSpot/bridge.sock")
            .path

    private let socketPath: String

    public init(socketPath: String = UnixDomainSocketClient.defaultSocketPath) {
        self.socketPath = socketPath
    }

    public func send(_ request: BridgeRequest) async throws -> BridgeResponse {
        let path = socketPath
        return try await Task.detached(priority: .userInitiated) {
            try Self.roundTrip(request, socketPath: path)
        }.value
    }

    private static func roundTrip(_ request: BridgeRequest, socketPath: String) throws -> BridgeResponse {
        let descriptor = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
        guard descriptor >= 0 else {
            throw BridgeClientError.connectionFailed(errno)
        }
        defer { Darwin.close(descriptor) }

        var noSignal: Int32 = 1
        _ = withUnsafePointer(to: &noSignal) {
            Darwin.setsockopt(descriptor, SOL_SOCKET, SO_NOSIGPIPE, $0, socklen_t(MemoryLayout<Int32>.size))
        }
        // Longer than the Remote Script's request deadline so its structured
        // live_timeout response can reach the UI before POSIX times out.
        var timeout = timeval(tv_sec: 10, tv_usec: 0)
        _ = withUnsafePointer(to: &timeout) {
            Darwin.setsockopt(descriptor, SOL_SOCKET, SO_RCVTIMEO, $0, socklen_t(MemoryLayout<timeval>.size))
        }
        _ = withUnsafePointer(to: &timeout) {
            Darwin.setsockopt(descriptor, SOL_SOCKET, SO_SNDTIMEO, $0, socklen_t(MemoryLayout<timeval>.size))
        }

        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        let pathBytes = Array(socketPath.utf8CString)
        let pathCapacity = MemoryLayout.size(ofValue: address.sun_path)
        guard pathBytes.count <= pathCapacity else {
            throw BridgeClientError.socketPathTooLong
        }
        pathBytes.withUnsafeBufferPointer { source in
            withUnsafeMutablePointer(to: &address.sun_path) { destination in
                destination.withMemoryRebound(to: CChar.self, capacity: pathCapacity) { bytes in
                    bytes.update(from: source.baseAddress!, count: pathBytes.count)
                }
            }
        }

        let connectResult = withUnsafePointer(to: &address) { addressPointer in
            addressPointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.connect(descriptor, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard connectResult == 0 else {
            throw BridgeClientError.connectionFailed(errno)
        }

        let requestLine = try BridgeLineCodec.encodeRequest(request)
        try writeAll(requestLine, to: descriptor)
        let responseLine = try readLine(from: descriptor)
        let response = try BridgeLineCodec.decodeResponse(from: responseLine)
        guard response.id == request.id, response.protocolVersion == request.protocolVersion else {
            throw BridgeClientError.invalidResponse
        }
        return response
    }

    private static func writeAll(_ data: Data, to descriptor: Int32) throws {
        try data.withUnsafeBytes { rawBuffer in
            guard let baseAddress = rawBuffer.baseAddress else { return }
            var offset = 0
            while offset < rawBuffer.count {
                let count = Darwin.send(
                    descriptor,
                    baseAddress.advanced(by: offset),
                    rawBuffer.count - offset,
                    0
                )
                guard count > 0 else {
                    throw BridgeClientError.writeFailed(errno)
                }
                offset += count
            }
        }
    }

    private static func readLine(from descriptor: Int32) throws -> Data {
        var response = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while response.count <= BridgeLineCodec.maximumFrameBytes {
            let count = buffer.withUnsafeMutableBytes {
                Darwin.recv(descriptor, $0.baseAddress, $0.count, 0)
            }
            guard count > 0 else {
                if count == 0 { throw BridgeClientError.serverClosedConnection }
                throw BridgeClientError.readFailed(errno)
            }
            response.append(contentsOf: buffer.prefix(count))
            if let newline = response.firstIndex(of: 0x0A) {
                return response.prefix(through: newline)
            }
        }
        throw BridgeClientError.frameTooLarge
    }
}
