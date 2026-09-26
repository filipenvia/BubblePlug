import CryptoKit
import Darwin
import Foundation

public struct VST3PluginValidationTarget: Sendable, Equatable {
    public let pluginID: String
    public let name: String
    public let vendor: String
    public let bundleURL: URL
    public let version: String
    public let architecture: String
    public let fingerprint: String
    public let cacheKey: String

    public init(pluginID: String, name: String, vendor: String, bundleURL: URL, version: String, architecture: String, fingerprint: String, cacheKey: String) {
        self.pluginID = pluginID
        self.name = name
        self.vendor = vendor
        self.bundleURL = bundleURL
        self.version = version
        self.architecture = architecture
        self.fingerprint = fingerprint
        self.cacheKey = cacheKey
    }
}

public enum AbletonPluginScannerError: Error, LocalizedError, Sendable {
    case scannerUnavailable
    case pluginNotFound(String)
    case invalidBundle(String)

    public var errorDescription: String? {
        switch self {
        case .scannerUnavailable:
            return "Ableton's VST3 scan data is unavailable. PlugSpot could not resolve this plug-in's installed bundle."
        case .pluginNotFound(let name):
            return "Could not match \(name) to its installed VST3 bundle in Ableton's scan data."
        case .invalidBundle(let message):
            return "Could not read the installed VST3 bundle: \(message)"
        }
    }
}

/// Resolves Live Browser entries to their installed VST3 bundles using Live's own scan record.
public enum AbletonPluginScanner {
    private struct ScanEntry {
        var name = ""
        var vendor = ""
        var version = ""
        var bundlePath = ""
        var fingerprint = ""
        var classID = ""
    }

    /// Resolves an installed VST3 bundle for local resource lookup without instantiating it.
    public static func resourceBundleURL(for plugin: PluginItem, liveVersion: String) throws -> URL {
        let scannerURL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Preferences/Ableton/Live \(liveVersion)", isDirectory: true)
            .appendingPathComponent("PluginScanner.txt")
        guard FileManager.default.fileExists(atPath: scannerURL.path),
              let scannerText = try? String(contentsOf: scannerURL, encoding: .utf8) else {
            throw AbletonPluginScannerError.scannerUnavailable
        }

        let entries = parseVST3Entries(scannerText)
        let vendor = (plugin.vendor ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard let entry = entries.last(where: {
            $0.name.compare(plugin.name, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame &&
            (vendor.isEmpty || $0.vendor.compare(vendor, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame) &&
            !$0.bundlePath.isEmpty && FileManager.default.fileExists(atPath: $0.bundlePath)
        }) else {
            throw AbletonPluginScannerError.pluginNotFound(plugin.name)
        }
        return URL(fileURLWithPath: entry.bundlePath).resolvingSymlinksInPath().standardizedFileURL
    }

    public static func validationTarget(for plugin: PluginItem, liveVersion: String) throws -> VST3PluginValidationTarget {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let scannerURL = home
            .appendingPathComponent("Library/Preferences/Ableton/Live \(liveVersion)", isDirectory: true)
            .appendingPathComponent("PluginScanner.txt")
        guard FileManager.default.fileExists(atPath: scannerURL.path),
              let scannerText = try? String(contentsOf: scannerURL, encoding: .utf8) else {
            throw AbletonPluginScannerError.scannerUnavailable
        }

        let entries = parseVST3Entries(scannerText)
        let vendor = (plugin.vendor ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard let entry = entries.last(where: {
            $0.name.compare(plugin.name, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame &&
            (vendor.isEmpty || $0.vendor.compare(vendor, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame) &&
            !$0.bundlePath.isEmpty && FileManager.default.fileExists(atPath: $0.bundlePath)
        }) else {
            throw AbletonPluginScannerError.pluginNotFound(plugin.name)
        }

        let bundleURL = URL(fileURLWithPath: entry.bundlePath).resolvingSymlinksInPath().standardizedFileURL
        let infoURL = bundleURL.appendingPathComponent("Contents/Info.plist")
        guard let infoData = try? Data(contentsOf: infoURL),
              let info = try? PropertyListSerialization.propertyList(from: infoData, format: nil) as? [String: Any],
              let executableName = info["CFBundleExecutable"] as? String else {
            throw AbletonPluginScannerError.invalidBundle(bundleURL.path)
        }

        let executableURL = bundleURL.appendingPathComponent("Contents/MacOS").appendingPathComponent(executableName)
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: executableURL.path),
              let fileSize = attributes[.size] as? NSNumber,
              let modifiedAt = attributes[.modificationDate] as? Date else {
            throw AbletonPluginScannerError.invalidBundle("main executable not found at \(executableURL.path)")
        }
        let version = (info["CFBundleVersion"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? entry.version
        let architecture = currentArchitecture()
        let fingerprint = [
            entry.fingerprint,
            String(fileSize.uint64Value),
            String(format: "%.6f", modifiedAt.timeIntervalSince1970),
        ].joined(separator: ":")
        let keyMaterial = ["VST3", entry.classID, bundleURL.path, version, architecture, fingerprint].joined(separator: "|")
        let key = SHA256.hash(data: Data(keyMaterial.utf8)).map { String(format: "%02x", $0) }.joined()

        return VST3PluginValidationTarget(
            pluginID: plugin.id,
            name: plugin.name,
            vendor: entry.vendor,
            bundleURL: bundleURL,
            version: version,
            architecture: architecture,
            fingerprint: fingerprint,
            cacheKey: key
        )
    }

    private static func parseVST3Entries(_ text: String) -> [ScanEntry] {
        var result: [ScanEntry] = []
        var current: ScanEntry?

        func appendCurrent() {
            if let current, !current.name.isEmpty { result.append(current) }
        }

        for rawLine in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = String(rawLine).trimmingCharacters(in: .whitespacesAndNewlines)
            if line.range(of: #"^\d{4}-\d{2}-\d{2}T"#, options: .regularExpression) != nil {
                appendCurrent()
                current = nil
                if let marker = line.range(of: "info: VST3: found: ") {
                    current = ScanEntry(name: String(line[marker.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines))
                }
                continue
            }
            guard current != nil, let separator = line.firstIndex(of: ":") else { continue }
            let key = String(line[..<separator]).trimmingCharacters(in: .whitespacesAndNewlines)
            var value = String(line[line.index(after: separator)...]).trimmingCharacters(in: .whitespacesAndNewlines)
            if value.hasPrefix("\""), value.hasSuffix("\""), value.count >= 2 {
                value.removeFirst()
                value.removeLast()
            }
            if key == "path" {
                // Live escapes ampersands as "&&" in PluginScanner.txt even
                // though the installed bundle has a single literal ampersand.
                value = value.replacingOccurrences(of: "&&", with: "&")
            }
            switch key {
            case "vendor": current?.vendor = value
            case "version": current?.version = value
            case "path": current?.bundlePath = value
            case "fp": current?.fingerprint = value
            case "device-class-id": current?.classID = value
            default: break
            }
        }
        appendCurrent()
        return result
    }

    private static func currentArchitecture() -> String {
        var size = 0
        sysctlbyname("hw.machine", nil, &size, nil, 0)
        guard size > 1 else { return "unknown" }
        var value = [CChar](repeating: 0, count: size)
        guard sysctlbyname("hw.machine", &value, &size, nil, 0) == 0 else { return "unknown" }
        return String(cString: value)
    }
}
