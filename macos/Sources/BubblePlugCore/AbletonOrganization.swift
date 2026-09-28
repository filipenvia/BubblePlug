import Foundation
import SQLite3

public struct AbletonCollectionLabel: Sendable, Equatable, Hashable {
    public let colorIndex: Int
    public let name: String
}

public struct AbletonPluginOrganization: Sendable, Equatable {
    public let name: String
    public let vendor: String
    public let collections: [AbletonCollectionLabel]
}

public struct AbletonOrganizationSnapshot: Sendable {
    public let labels: [AbletonCollectionLabel]
    public let plugins: [AbletonPluginOrganization]
}

public enum AbletonOrganizationError: Error, LocalizedError, Sendable {
    case unavailable(String)
    case database(String)

    public var errorDescription: String? {
        switch self {
        case .unavailable(let message): return message
        case .database(let message): return "Could not read Ableton organization: \(message)"
        }
    }
}

/// Reads the current Live Browser index and Library.cfg without changing Ableton files.
public enum AbletonOrganizationImporter {
    public static func read() throws -> AbletonOrganizationSnapshot {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let preferences = home.appendingPathComponent("Library/Preferences/Ableton", isDirectory: true)
        let libraryConfig = try newestLibraryConfig(in: preferences)
        let collections = try AbletonLabelParser.parse(url: libraryConfig)
        let databaseDirectory = home.appendingPathComponent("Library/Application Support/Ableton/Live Database", isDirectory: true)
        let fileDatabase = try newestDatabase(prefix: "Live-files-", in: databaseDirectory)
        let pluginDatabase = databaseDirectory.appendingPathComponent("Live-plugins-1.db")
        let vendors = try readVendors(from: pluginDatabase)
        let plugins = try readColoredPlugins(from: fileDatabase, vendors: vendors, collections: collections)
        let labels = collections.map { AbletonCollectionLabel(colorIndex: $0.key, name: $0.value) }.sorted { $0.colorIndex < $1.colorIndex }
        return AbletonOrganizationSnapshot(labels: labels, plugins: plugins)
    }

    private static func newestLibraryConfig(in directory: URL) throws -> URL {
        let folders = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        guard let selected = folders
            .filter({ $0.lastPathComponent.hasPrefix("Live ") })
            .map({ $0.appendingPathComponent("Library.cfg") })
            .filter({ FileManager.default.fileExists(atPath: $0.path) })
            .max(by: { modificationDate($0) < modificationDate($1) }) else {
            throw AbletonOrganizationError.unavailable("Could not find Ableton Live's Library.cfg.")
        }
        return selected
    }

    private static func newestDatabase(prefix: String, in directory: URL) throws -> URL {
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
        guard let selected = files
            .filter({ $0.lastPathComponent.hasPrefix(prefix) && $0.pathExtension == "db" })
            .max(by: { modificationDate($0) < modificationDate($1) }) else {
            throw AbletonOrganizationError.unavailable("Could not find Ableton Live's indexed plugin database.")
        }
        return selected
    }

    private static func modificationDate(_ url: URL) -> Date {
        (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
    }

    private static func readVendors(from url: URL) throws -> [String: String] {
        guard FileManager.default.fileExists(atPath: url.path) else { return [:] }
        let db = try openReadOnly(url)
        defer { sqlite3_close(db) }
        let statement = try prepare("SELECT dev_identifier, vendor FROM plugins WHERE dev_identifier IS NOT NULL", database: db)
        defer { sqlite3_finalize(statement) }
        var result: [String: String] = [:]
        while sqlite3_step(statement) == SQLITE_ROW {
            let identifier = columnText(statement, 0)
            let vendor = columnText(statement, 1)
            if !identifier.isEmpty, !vendor.isEmpty { result[identifier] = vendor }
        }
        return result
    }

    private static func readColoredPlugins(from url: URL, vendors: [String: String], collections: [Int: String]) throws -> [AbletonPluginOrganization] {
        let db = try openReadOnly(url)
        defer { sqlite3_close(db) }
        let statement = try prepare("""
            SELECT name, device_id, colors
            FROM files
            WHERE device_id LIKE 'device:vst3:%' AND device_type IN (1, 2) AND colors != 1
            """, database: db)
        defer { sqlite3_finalize(statement) }

        var plugins: [String: (name: String, vendor: String, collections: Set<AbletonCollectionLabel>)] = [:]
        while sqlite3_step(statement) == SQLITE_ROW {
            let name = columnText(statement, 0)
            let identifier = columnText(statement, 1)
            let colorBits = Int(sqlite3_column_int64(statement, 2))
            guard !name.isEmpty, !identifier.isEmpty else { continue }
            let assigned = collections.compactMap { index, label -> AbletonCollectionLabel? in
                colorBits & (1 << index) == 0 ? nil : AbletonCollectionLabel(colorIndex: index, name: label)
            }
            guard !assigned.isEmpty else { continue }
            var item = plugins[identifier] ?? (name, vendors[identifier] ?? "", [])
            item.collections.formUnion(assigned)
            plugins[identifier] = item
        }
        var result: [AbletonPluginOrganization] = []
        for plugin in plugins.values {
            let orderedLabels = plugin.collections.sorted { left, right in left.colorIndex < right.colorIndex }
            result.append(AbletonPluginOrganization(name: plugin.name, vendor: plugin.vendor, collections: orderedLabels))
        }
        return result.sorted { left, right in left.name.localizedStandardCompare(right.name) == .orderedAscending }
    }

    private static func openReadOnly(_ url: URL) throws -> OpaquePointer {
        var handle: OpaquePointer?
        let result = sqlite3_open_v2(url.path, &handle, SQLITE_OPEN_READONLY | SQLITE_OPEN_FULLMUTEX, nil)
        guard result == SQLITE_OK, let database = handle else {
            let message = handle.map { String(cString: sqlite3_errmsg($0)) } ?? "SQLite open failed"
            if let handle { sqlite3_close(handle) }
            throw AbletonOrganizationError.database(message)
        }
        return database
    }

    private static func prepare(_ sql: String, database: OpaquePointer) throws -> OpaquePointer {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            throw AbletonOrganizationError.database(String(cString: sqlite3_errmsg(database)))
        }
        return statement
    }

    private static func columnText(_ statement: OpaquePointer, _ index: Int32) -> String {
        guard let value = sqlite3_column_text(statement, index) else { return "" }
        return String(cString: value)
    }
}

private final class AbletonLabelParser: NSObject, XMLParserDelegate {
    private var labels: [Int: String] = [:]

    static func parse(url: URL) throws -> [Int: String] {
        let parser = XMLParser(contentsOf: url)
        guard let parser else { throw AbletonOrganizationError.unavailable("Could not open Ableton Live's Library.cfg.") }
        let delegate = AbletonLabelParser()
        parser.delegate = delegate
        guard parser.parse() else {
            throw AbletonOrganizationError.database(parser.parserError?.localizedDescription ?? "Invalid XML")
        }
        return delegate.labels
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String: String]) {
        guard elementName == "LabelInfo",
              let uri = attributeDict["Uri"],
              uri.hasPrefix("color:colors="),
              let index = Int(uri.dropFirst("color:colors=".count)), (1...7).contains(index),
              let name = attributeDict["DisplayName"], !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        labels[index] = name
    }
}
