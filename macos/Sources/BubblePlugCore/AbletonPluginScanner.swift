import Foundation

public enum AbletonPluginScannerError: Error, LocalizedError, Sendable {
    case scannerUnavailable
    case pluginNotFound(String)

    public var errorDescription: String? {
        switch self {
        case .scannerUnavailable:
            return "Ableton's VST3 scan data is unavailable. BubblePlug could not resolve this plug-in's installed bundle."
        case .pluginNotFound(let name):
            return "Could not match \(name) to its installed VST3 bundle in Ableton's scan data."
        }
    }
}

/// Resolves Live Browser entries to their installed VST3 bundles using Live's own scan record.
public enum AbletonPluginScanner {
    private static let scanLock = NSLock()
    private static var cachedScan: (path: String, modified: Date?, size: Int, entries: [ScanEntry])?
    private struct ScanEntry {
        var name = ""
        var vendor = ""
        var bundlePath = ""
        var deviceClassID = ""
    }

    /// Returns Live's exact VST3 class identifier for a Browser item.
    /// Browser URIs are presentation paths (`query:Plugins#…`), not the class IDs
    /// required by Ableton rack presets, so resolve them through Live's own scan log.
    public static func deviceClassID(for pluginName: String, vendor: String, liveVersion: String) throws -> String {
        let scannerURL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Preferences/Ableton/Live \(liveVersion)", isDirectory: true)
            .appendingPathComponent("PluginScanner.txt")
        guard let scannerText = try? String(contentsOf: scannerURL, encoding: .utf8) else {
            throw AbletonPluginScannerError.scannerUnavailable
        }
        let nameKey = normalized(pluginName)
        let vendorKey = normalized(vendor)
        let matches = parseVST3Entries(scannerText).filter {
            normalized($0.name) == nameKey && normalized($0.vendor) == vendorKey && !$0.deviceClassID.isEmpty
        }
        guard let match = matches.last else { throw AbletonPluginScannerError.pluginNotFound(pluginName) }
        return match.deviceClassID
    }

    private static func normalized(_ value: String) -> String {
        value.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Resolves an installed VST3 bundle for local resource lookup without instantiating it.
    public static func resourceBundleURL(for plugin: PluginItem, liveVersion: String) throws -> URL {
        let scannerURL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Preferences/Ableton/Live \(liveVersion)", isDirectory: true)
            .appendingPathComponent("PluginScanner.txt")
        guard FileManager.default.fileExists(atPath: scannerURL.path) else {
            throw AbletonPluginScannerError.scannerUnavailable
        }
        let attributes = try? FileManager.default.attributesOfItem(atPath: scannerURL.path)
        let modified = attributes?[.modificationDate] as? Date
        let size = (attributes?[.size] as? NSNumber)?.intValue ?? 0
        scanLock.lock()
        let entries: [ScanEntry]
        if let cachedScan, cachedScan.path == scannerURL.path,
           cachedScan.modified == modified, cachedScan.size == size {
            entries = cachedScan.entries
        } else {
            guard let scannerText = try? String(contentsOf: scannerURL, encoding: .utf8) else {
                scanLock.unlock()
                throw AbletonPluginScannerError.scannerUnavailable
            }
            entries = parseVST3Entries(scannerText)
            cachedScan = (scannerURL.path, modified, size, entries)
        }
        scanLock.unlock()
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
            case "path": current?.bundlePath = value
            case "device-class-id":
                let withoutQuery = value.split(separator: "?", maxSplits: 1, omittingEmptySubsequences: false).first.map(String.init) ?? value
                if withoutQuery.range(of: #"^device:vst3:(audiofx|instr|midifx):[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}$"#, options: .regularExpression) != nil {
                    current?.deviceClassID = withoutQuery
                }
            default: break
            }
        }
        appendCurrent()
        return result
    }

}
