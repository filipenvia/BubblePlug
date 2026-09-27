import Darwin
import Foundation
import SQLite3

public struct LocalPluginLabel: Codable, Sendable, Equatable, Hashable, Identifiable {
    public let pluginID: String
    public let name: String
    public let kind: String
    public let source: String
    public let colorIndex: Int?
    public let pluginName: String?
    public let vendor: String?
    public let format: String?

    public var id: String { "\(pluginID)|\(kind)|\(name)|\(source)" }

    public init(pluginID: String, name: String, kind: String = "category", source: String = "local", colorIndex: Int? = nil, pluginName: String? = nil, vendor: String? = nil, format: String? = nil) {
        self.pluginID = pluginID
        self.name = name
        self.kind = kind
        self.source = source
        self.colorIndex = colorIndex
        self.pluginName = pluginName
        self.vendor = vendor
        self.format = format
    }
}

public struct LocalCategory: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public let name: String
    /// Ableton Collection slot; slot 1 is reserved for Favorites, so user categories use 2...7.
    public let colorIndex: Int

    public init(id: String = UUID().uuidString, name: String, colorIndex: Int) {
        self.id = id
        self.name = name
        self.colorIndex = colorIndex
    }
}

public struct StoredChainPlugin: Codable, Sendable, Equatable, Identifiable {
    public let familyID: String
    public let pluginID: String
    public let name: String
    public let vendor: String
    public let format: String
    public var id: String { "\(familyID)|\(pluginID)|\(name)" }

    public init(familyID: String, pluginID: String, name: String, vendor: String, format: String) {
        self.familyID = familyID
        self.pluginID = pluginID
        self.name = name
        self.vendor = vendor
        self.format = format
    }
}

public struct StoredChainSet: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public var name: String
    public var plugins: [StoredChainPlugin]
    public let updatedAt: Date

    public init(id: String = UUID().uuidString, name: String, plugins: [StoredChainPlugin], updatedAt: Date = Date()) {
        self.id = id
        self.name = name
        self.plugins = plugins
        self.updatedAt = updatedAt
    }
}

public struct PlugSpotLibraryDocument: Codable, Sendable, Equatable {
    public let schemaVersion: Int
    public let exportedAt: Date
    public let favorites: [LocalPluginRecord]
    public let labels: [LocalPluginLabel]
    public let recentRecords: [LocalPluginRecord]
    public let categories: [LocalCategory]

    public init(schemaVersion: Int = 2, exportedAt: Date = Date(), favorites: [LocalPluginRecord], labels: [LocalPluginLabel], recentRecords: [LocalPluginRecord] = [], categories: [LocalCategory] = []) {
        self.schemaVersion = schemaVersion
        self.exportedAt = exportedAt
        self.favorites = favorites
        self.labels = labels
        self.recentRecords = recentRecords
        self.categories = categories
    }

    private enum CodingKeys: String, CodingKey { case schemaVersion, exportedAt, favorites, labels, recentRecords, categories }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try values.decode(Int.self, forKey: .schemaVersion)
        exportedAt = try values.decodeIfPresent(Date.self, forKey: .exportedAt) ?? .distantPast
        favorites = try values.decodeIfPresent([LocalPluginRecord].self, forKey: .favorites) ?? []
        labels = try values.decodeIfPresent([LocalPluginLabel].self, forKey: .labels) ?? []
        recentRecords = try values.decodeIfPresent([LocalPluginRecord].self, forKey: .recentRecords) ?? []
        categories = try values.decodeIfPresent([LocalCategory].self, forKey: .categories) ?? []
    }

    public func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(schemaVersion, forKey: .schemaVersion)
        try values.encode(exportedAt, forKey: .exportedAt)
        try values.encode(favorites, forKey: .favorites)
        try values.encode(labels, forKey: .labels)
        try values.encode(recentRecords, forKey: .recentRecords)
        try values.encode(categories, forKey: .categories)
    }
}

public struct LocalPluginRecord: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public let name: String
    public let vendor: String
    public let format: String
    public let lastUsed: Date?
    public let useCount: Int

    public init(id: String, name: String, vendor: String, format: String, lastUsed: Date?, useCount: Int) {
        self.id = id
        self.name = name
        self.vendor = vendor
        self.format = format
        self.lastUsed = lastUsed
        self.useCount = useCount
    }
}

public enum LocalLibraryStoreError: Error, LocalizedError, Sendable {
    case open(String)
    case database(String)

    public var errorDescription: String? {
        switch self {
        case .open(let message): return "Could not open the local library: \(message)"
        case .database(let message): return "Local library error: \(message)"
        }
    }
}

/// Private, offline SQLite storage for favorites and recent load requests.
public final class LocalLibraryStore: @unchecked Sendable {
    public static var defaultDatabaseURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/PlugSpot/library.sqlite3")
    }

    // Imports hold the lock across a complete SQLite transaction. Individual
    // store methods also lock, so the lock must allow same-thread re-entry.
    private let lock = NSRecursiveLock()
    private let database: OpaquePointer

    public init(databaseURL: URL = LocalLibraryStore.defaultDatabaseURL) throws {
        let directory = databaseURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        _ = chmod(directory.path, mode_t(0o700))

        var handle: OpaquePointer?
        let openResult = sqlite3_open_v2(
            databaseURL.path,
            &handle,
            SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX,
            nil
        )
        guard openResult == SQLITE_OK, let openedDatabase = handle else {
            let message = handle.map { String(cString: sqlite3_errmsg($0)) } ?? "SQLite open failed"
            if let handle { sqlite3_close(handle) }
            throw LocalLibraryStoreError.open(message)
        }
        database = openedDatabase
        _ = chmod(databaseURL.path, mode_t(0o600))

        do {
            try execute("""
                CREATE TABLE IF NOT EXISTS favorites (
                    plugin_id TEXT PRIMARY KEY NOT NULL,
                    name TEXT NOT NULL,
                    vendor TEXT NOT NULL,
                    format TEXT NOT NULL,
                    added_at REAL NOT NULL
                );
                CREATE TABLE IF NOT EXISTS usage_history (
                    plugin_id TEXT PRIMARY KEY NOT NULL,
                    name TEXT NOT NULL,
                    vendor TEXT NOT NULL,
                    format TEXT NOT NULL,
                    last_used REAL NOT NULL,
                    use_count INTEGER NOT NULL DEFAULT 0
                );
                CREATE INDEX IF NOT EXISTS usage_history_last_used
                    ON usage_history(last_used DESC);
                CREATE TABLE IF NOT EXISTS plugin_labels (
                    plugin_id TEXT NOT NULL,
                    name TEXT NOT NULL,
                    kind TEXT NOT NULL,
                    source TEXT NOT NULL,
                    color_index INTEGER,
                    plugin_name TEXT,
                    vendor TEXT,
                    format TEXT,
                    PRIMARY KEY(plugin_id, name, kind, source)
                );
                CREATE TABLE IF NOT EXISTS categories (
                    category_id TEXT PRIMARY KEY NOT NULL,
                    name TEXT NOT NULL COLLATE NOCASE UNIQUE,
                    color_index INTEGER NOT NULL UNIQUE CHECK(color_index BETWEEN 2 AND 7)
                );
                CREATE TABLE IF NOT EXISTS chain_sets (
                    chain_set_id TEXT PRIMARY KEY NOT NULL,
                    name TEXT NOT NULL COLLATE NOCASE UNIQUE,
                    updated_at REAL NOT NULL
                );
                CREATE TABLE IF NOT EXISTS chain_set_plugins (
                    chain_set_id TEXT NOT NULL REFERENCES chain_sets(chain_set_id) ON DELETE CASCADE,
                    position INTEGER NOT NULL,
                    family_id TEXT NOT NULL,
                    plugin_id TEXT NOT NULL,
                    name TEXT NOT NULL,
                    vendor TEXT NOT NULL,
                    format TEXT NOT NULL,
                    PRIMARY KEY(chain_set_id, position)
                );
                """)
            try execute("PRAGMA foreign_keys=ON")
            try ensurePluginLabelColorColumn()
        } catch {
            sqlite3_close(openedDatabase)
            throw error
        }
    }

    deinit {
        sqlite3_close(database)
    }

    public func favoriteIDs() throws -> Set<String> {
        lock.lock()
        defer { lock.unlock() }
        return Set(try readRecords("SELECT plugin_id, name, vendor, format, NULL, 0 FROM favorites").map(\.id))
    }

    public func favoriteRecords() throws -> [LocalPluginRecord] {
        lock.lock()
        defer { lock.unlock() }
        return try readRecords("SELECT plugin_id, name, vendor, format, NULL, 0 FROM favorites ORDER BY name COLLATE NOCASE")
    }

    public func recentRecords(limit: Int = 100) throws -> [LocalPluginRecord] {
        lock.lock()
        defer { lock.unlock() }
        let boundedLimit = max(1, min(limit, 500))
        return try readRecords(
            "SELECT plugin_id, name, vendor, format, last_used, use_count FROM usage_history ORDER BY last_used DESC LIMIT \(boundedLimit)"
        )
    }

    public func labels() throws -> [LocalPluginLabel] {
        lock.lock()
        defer { lock.unlock() }
        return try withStatement("SELECT plugin_id, name, kind, source, color_index, plugin_name, vendor, format FROM plugin_labels ORDER BY name COLLATE NOCASE, plugin_id") { statement in
            var values: [LocalPluginLabel] = []
            while true {
                let result = sqlite3_step(statement)
                if result == SQLITE_DONE { break }
                guard result == SQLITE_ROW else { throw LocalLibraryStoreError.database(String(cString: sqlite3_errmsg(database))) }
                let colorIndex = sqlite3_column_type(statement, 4) == SQLITE_NULL ? nil : Int(sqlite3_column_int(statement, 4))
                values.append(LocalPluginLabel(pluginID: textColumn(statement, 0), name: textColumn(statement, 1), kind: textColumn(statement, 2), source: textColumn(statement, 3), colorIndex: colorIndex, pluginName: optionalTextColumn(statement, 5), vendor: optionalTextColumn(statement, 6), format: optionalTextColumn(statement, 7)))
            }
            return values
        }
    }

    public func addLabel(_ label: LocalPluginLabel) throws {
        lock.lock()
        defer { lock.unlock() }
        try withStatement("INSERT OR IGNORE INTO plugin_labels(plugin_id, name, kind, source, color_index, plugin_name, vendor, format) VALUES(?, ?, ?, ?, ?, ?, ?, ?)") { statement in
            try bind(label.pluginID, at: 1, in: statement)
            try bind(label.name, at: 2, in: statement)
            try bind(label.kind, at: 3, in: statement)
            try bind(label.source, at: 4, in: statement)
            if let colorIndex = label.colorIndex { sqlite3_bind_int(statement, 5, Int32(colorIndex)) }
            else { sqlite3_bind_null(statement, 5) }
            try bindOptional(label.pluginName, at: 6, in: statement)
            try bindOptional(label.vendor, at: 7, in: statement)
            try bindOptional(label.format, at: 8, in: statement)
            try stepDone(statement)
        }
    }

    public func categories() throws -> [LocalCategory] {
        lock.lock()
        defer { lock.unlock() }
        return try withStatement("SELECT category_id, name, color_index FROM categories ORDER BY color_index") { statement in
            var values: [LocalCategory] = []
            while true {
                let result = sqlite3_step(statement)
                if result == SQLITE_DONE { break }
                guard result == SQLITE_ROW else { throw LocalLibraryStoreError.database(String(cString: sqlite3_errmsg(database))) }
                values.append(LocalCategory(id: textColumn(statement, 0), name: textColumn(statement, 1), colorIndex: Int(sqlite3_column_int(statement, 2))))
            }
            return values
        }
    }

    public func chainSets() throws -> [StoredChainSet] {
        lock.lock()
        defer { lock.unlock() }
        return try withStatement("SELECT chain_set_id, name, updated_at FROM chain_sets ORDER BY name COLLATE NOCASE") { statement in
            var result: [StoredChainSet] = []
            while true {
                let step = sqlite3_step(statement)
                if step == SQLITE_DONE { break }
                guard step == SQLITE_ROW else { throw LocalLibraryStoreError.database(String(cString: sqlite3_errmsg(database))) }
                let id = textColumn(statement, 0)
                result.append(StoredChainSet(id: id, name: textColumn(statement, 1), plugins: try chainPlugins(id: id), updatedAt: Date(timeIntervalSince1970: sqlite3_column_double(statement, 2))))
            }
            return result
        }
    }

    public func saveChainSet(_ chainSet: StoredChainSet) throws {
        lock.lock()
        defer { lock.unlock() }
        let name = chainSet.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, !chainSet.plugins.isEmpty else { throw LocalLibraryStoreError.database("Give the Chain Set a name and add at least one plugin.") }
        try execute("BEGIN IMMEDIATE")
        do {
            try withStatement("INSERT INTO chain_sets(chain_set_id, name, updated_at) VALUES(?, ?, ?) ON CONFLICT(chain_set_id) DO UPDATE SET name=excluded.name, updated_at=excluded.updated_at") { statement in
                try bind(chainSet.id, at: 1, in: statement); try bind(name, at: 2, in: statement)
                sqlite3_bind_double(statement, 3, chainSet.updatedAt.timeIntervalSince1970); try stepDone(statement)
            }
            try withStatement("DELETE FROM chain_set_plugins WHERE chain_set_id=?") { statement in try bind(chainSet.id, at: 1, in: statement); try stepDone(statement) }
            for (index, plugin) in chainSet.plugins.enumerated() {
                try withStatement("INSERT INTO chain_set_plugins(chain_set_id, position, family_id, plugin_id, name, vendor, format) VALUES(?, ?, ?, ?, ?, ?, ?)") { statement in
                    try bind(chainSet.id, at: 1, in: statement); sqlite3_bind_int(statement, 2, Int32(index))
                    try bind(plugin.familyID, at: 3, in: statement); try bind(plugin.pluginID, at: 4, in: statement)
                    try bind(plugin.name, at: 5, in: statement); try bind(plugin.vendor, at: 6, in: statement); try bind(plugin.format, at: 7, in: statement)
                    try stepDone(statement)
                }
            }
            try execute("COMMIT")
        } catch { try? execute("ROLLBACK"); throw error }
    }

    public func deleteChainSet(id: String) throws {
        lock.lock(); defer { lock.unlock() }
        try withStatement("DELETE FROM chain_sets WHERE chain_set_id=?") { statement in try bind(id, at: 1, in: statement); try stepDone(statement) }
        try withStatement("DELETE FROM chain_set_plugins WHERE chain_set_id=?") { statement in try bind(id, at: 1, in: statement); try stepDone(statement) }
    }

    public func renameChainSet(id: String, name: String) throws {
        lock.lock(); defer { lock.unlock() }
        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanName.isEmpty else { throw LocalLibraryStoreError.database("A Chain Set needs a name.") }
        try withStatement("UPDATE chain_sets SET name=?, updated_at=? WHERE chain_set_id=?") { statement in
            try bind(cleanName, at: 1, in: statement); sqlite3_bind_double(statement, 2, Date().timeIntervalSince1970); try bind(id, at: 3, in: statement); try stepDone(statement)
        }
    }

    private func chainPlugins(id: String) throws -> [StoredChainPlugin] {
        try withStatement("SELECT family_id, plugin_id, name, vendor, format FROM chain_set_plugins WHERE chain_set_id=? ORDER BY position") { statement in
            try bind(id, at: 1, in: statement)
            var result: [StoredChainPlugin] = []
            while true {
                let step = sqlite3_step(statement)
                if step == SQLITE_DONE { break }
                guard step == SQLITE_ROW else { throw LocalLibraryStoreError.database(String(cString: sqlite3_errmsg(database))) }
                result.append(StoredChainPlugin(familyID: textColumn(statement, 0), pluginID: textColumn(statement, 1), name: textColumn(statement, 2), vendor: textColumn(statement, 3), format: textColumn(statement, 4)))
            }
            return result
        }
    }

    public func saveCategory(_ category: LocalCategory, replacing oldName: String? = nil) throws {
        lock.lock()
        defer { lock.unlock() }
        let name = category.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, (2...7).contains(category.colorIndex) else { throw LocalLibraryStoreError.database("Choose a category name and a valid color.") }
        try withStatement("INSERT INTO categories(category_id, name, color_index) VALUES(?, ?, ?) ON CONFLICT(category_id) DO UPDATE SET name=excluded.name, color_index=excluded.color_index") { statement in
            try bind(category.id, at: 1, in: statement)
            try bind(name, at: 2, in: statement)
            sqlite3_bind_int(statement, 3, Int32(category.colorIndex))
            try stepDone(statement)
        }
        if let oldName, oldName.caseInsensitiveCompare(name) != .orderedSame {
            try withStatement("UPDATE plugin_labels SET name=?, color_index=? WHERE kind='category' AND name=? COLLATE NOCASE") { statement in
                try bind(name, at: 1, in: statement)
                sqlite3_bind_int(statement, 2, Int32(category.colorIndex))
                try bind(oldName, at: 3, in: statement)
                try stepDone(statement)
            }
        } else {
            try withStatement("UPDATE plugin_labels SET color_index=? WHERE kind='category' AND name=? COLLATE NOCASE") { statement in
                sqlite3_bind_int(statement, 1, Int32(category.colorIndex))
                try bind(name, at: 2, in: statement)
                try stepDone(statement)
            }
        }
    }

    public func deleteCategory(_ category: LocalCategory) throws {
        lock.lock()
        defer { lock.unlock() }
        try withStatement("DELETE FROM plugin_labels WHERE kind='category' AND name=? COLLATE NOCASE") { statement in
            try bind(category.name, at: 1, in: statement)
            try stepDone(statement)
        }
        try withStatement("DELETE FROM categories WHERE category_id=?") { statement in
            try bind(category.id, at: 1, in: statement)
            try stepDone(statement)
        }
    }

    public func setCategory(_ category: LocalCategory, pluginID: String, pluginName: String, vendor: String, format: String, assigned: Bool) throws {
        if assigned {
            try addLabel(LocalPluginLabel(pluginID: pluginID, name: category.name, kind: "category", source: "local", colorIndex: category.colorIndex, pluginName: pluginName, vendor: vendor, format: format))
        } else {
            lock.lock()
            defer { lock.unlock() }
            try withStatement("DELETE FROM plugin_labels WHERE plugin_id=? AND kind='category' AND name=? COLLATE NOCASE") { statement in
                try bind(pluginID, at: 1, in: statement)
                try bind(category.name, at: 2, in: statement)
                try stepDone(statement)
            }
        }
    }

    public func exportDocument() throws -> PlugSpotLibraryDocument {
        PlugSpotLibraryDocument(schemaVersion: 2, favorites: try favoriteRecords(), labels: try labels(), recentRecords: try recentRecords(limit: 500), categories: try categories())
    }

    /// Merges an exported library. Existing favorites, categories, and labels are preserved.
    public func importDocument(_ document: PlugSpotLibraryDocument) throws {
        guard (1...2).contains(document.schemaVersion) else {
            throw LocalLibraryStoreError.database("This PlugSpot library file version is not supported.")
        }
        lock.lock()
        defer { lock.unlock() }
        try execute("BEGIN IMMEDIATE")
        do {
            let existing = try categories()
            var nextColor = (2...7).filter { index in !existing.contains(where: { $0.colorIndex == index }) }
            let newCategories = document.categories.filter { category in
                !existing.contains(where: { $0.name.caseInsensitiveCompare(category.name) == .orderedSame })
            }
            guard newCategories.count <= nextColor.count else {
                throw LocalLibraryStoreError.database("There are already six categories. Delete or rename one before importing more.")
            }
            for category in newCategories {
                guard let color = nextColor.first(where: { $0 == category.colorIndex }) ?? nextColor.first else { continue }
                nextColor.removeAll { $0 == color }
                try saveCategory(LocalCategory(id: category.id, name: category.name, colorIndex: color))
            }
            var categoryColors: [String: Int] = [:]
            for category in try categories() {
                categoryColors[category.name.lowercased()] = category.colorIndex
            }
            for favorite in document.favorites {
                try setFavorite(id: favorite.id, name: favorite.name, vendor: favorite.vendor, format: favorite.format, isFavorite: true)
            }
            for record in document.recentRecords {
                guard let lastUsed = record.lastUsed else { continue }
                try mergeRecent(record, lastUsed: lastUsed)
            }
            for label in document.labels {
                let color = categoryColors[label.name.lowercased()] ?? label.colorIndex
                try addLabel(LocalPluginLabel(pluginID: label.pluginID, name: label.name, kind: label.kind, source: label.source, colorIndex: color, pluginName: label.pluginName, vendor: label.vendor, format: label.format))
            }
            try execute("COMMIT")
        } catch {
            try? execute("ROLLBACK")
            throw error
        }
    }

    public func setFavorite(id: String, name: String, vendor: String, format: String, isFavorite: Bool) throws {
        lock.lock()
        defer { lock.unlock() }
        if isFavorite {
            try withStatement("""
                INSERT INTO favorites(plugin_id, name, vendor, format, added_at)
                VALUES(?, ?, ?, ?, ?)
                ON CONFLICT(plugin_id) DO UPDATE SET
                    name=excluded.name, vendor=excluded.vendor, format=excluded.format
                """) { statement in
                try bind(id, at: 1, in: statement)
                try bind(name, at: 2, in: statement)
                try bind(vendor, at: 3, in: statement)
                try bind(format, at: 4, in: statement)
                try bind(Date().timeIntervalSince1970, at: 5, in: statement)
                try stepDone(statement)
            }
        } else {
            try withStatement("DELETE FROM favorites WHERE plugin_id = ?") { statement in
                try bind(id, at: 1, in: statement)
                try stepDone(statement)
            }
        }
    }

    public func recordLoadRequest(id: String, name: String, vendor: String, format: String) throws {
        lock.lock()
        defer { lock.unlock() }
        try withStatement("""
            INSERT INTO usage_history(plugin_id, name, vendor, format, last_used, use_count)
            VALUES(?, ?, ?, ?, ?, 1)
            ON CONFLICT(plugin_id) DO UPDATE SET
                name=excluded.name, vendor=excluded.vendor, format=excluded.format,
                last_used=excluded.last_used, use_count=usage_history.use_count + 1
            """) { statement in
            try bind(id, at: 1, in: statement)
            try bind(name, at: 2, in: statement)
            try bind(vendor, at: 3, in: statement)
            try bind(format, at: 4, in: statement)
            try bind(Date().timeIntervalSince1970, at: 5, in: statement)
            try stepDone(statement)
        }
    }

    private func mergeRecent(_ record: LocalPluginRecord, lastUsed: Date) throws {
        lock.lock()
        defer { lock.unlock() }
        try withStatement("""
            INSERT INTO usage_history(plugin_id, name, vendor, format, last_used, use_count)
            VALUES(?, ?, ?, ?, ?, ?)
            ON CONFLICT(plugin_id) DO UPDATE SET
                name=excluded.name, vendor=excluded.vendor, format=excluded.format,
                last_used=MAX(usage_history.last_used, excluded.last_used),
                use_count=MAX(usage_history.use_count, excluded.use_count)
            """) { statement in
            try bind(record.id, at: 1, in: statement)
            try bind(record.name, at: 2, in: statement)
            try bind(record.vendor, at: 3, in: statement)
            try bind(record.format, at: 4, in: statement)
            try bind(lastUsed.timeIntervalSince1970, at: 5, in: statement)
            sqlite3_bind_int64(statement, 6, sqlite3_int64(record.useCount))
            try stepDone(statement)
        }
    }

    private func ensurePluginLabelColorColumn() throws {
        for (column, type) in [("plugin_name", "TEXT"), ("vendor", "TEXT"), ("format", "TEXT"), ("color_index", "INTEGER")] {
            var exists = false
            try withStatement("PRAGMA table_info(plugin_labels)") { statement in
                while sqlite3_step(statement) == SQLITE_ROW {
                    if textColumn(statement, 1) == column { exists = true }
                }
            }
            if !exists { try execute("ALTER TABLE plugin_labels ADD COLUMN \(column) \(type)") }
        }
    }

    private func execute(_ sql: String) throws {
        var errorMessage: UnsafeMutablePointer<CChar>?
        guard sqlite3_exec(database, sql, nil, nil, &errorMessage) == SQLITE_OK else {
            let message = errorMessage.map { String(cString: $0) } ?? String(cString: sqlite3_errmsg(database))
            sqlite3_free(errorMessage)
            throw LocalLibraryStoreError.database(message)
        }
    }

    private func withStatement<T>(_ sql: String, _ body: (OpaquePointer) throws -> T) throws -> T {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK,
              let preparedStatement = statement else {
            throw LocalLibraryStoreError.database(String(cString: sqlite3_errmsg(database)))
        }
        defer { sqlite3_finalize(preparedStatement) }
        return try body(preparedStatement)
    }

    private func readRecords(_ sql: String) throws -> [LocalPluginRecord] {
        try withStatement(sql) { statement in
            var records: [LocalPluginRecord] = []
            while true {
                let result = sqlite3_step(statement)
                if result == SQLITE_DONE { break }
                guard result == SQLITE_ROW else {
                    throw LocalLibraryStoreError.database(String(cString: sqlite3_errmsg(database)))
                }
                let timestamp = sqlite3_column_type(statement, 4) == SQLITE_NULL
                    ? nil
                    : Date(timeIntervalSince1970: sqlite3_column_double(statement, 4))
                records.append(LocalPluginRecord(
                    id: textColumn(statement, 0),
                    name: textColumn(statement, 1),
                    vendor: textColumn(statement, 2),
                    format: textColumn(statement, 3),
                    lastUsed: timestamp,
                    useCount: Int(sqlite3_column_int64(statement, 5))
                ))
            }
            return records
        }
    }

    private func bind(_ value: String, at index: Int32, in statement: OpaquePointer) throws {
        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        guard sqlite3_bind_text(statement, index, value, -1, transient) == SQLITE_OK else {
            throw LocalLibraryStoreError.database(String(cString: sqlite3_errmsg(database)))
        }
    }

    private func bind(_ value: Double, at index: Int32, in statement: OpaquePointer) throws {
        guard sqlite3_bind_double(statement, index, value) == SQLITE_OK else {
            throw LocalLibraryStoreError.database(String(cString: sqlite3_errmsg(database)))
        }
    }

    private func stepDone(_ statement: OpaquePointer) throws {
        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw LocalLibraryStoreError.database(String(cString: sqlite3_errmsg(database)))
        }
    }

    private func textColumn(_ statement: OpaquePointer, _ index: Int32) -> String {
        guard let value = sqlite3_column_text(statement, index) else { return "" }
        return String(cString: value)
    }

    private func optionalTextColumn(_ statement: OpaquePointer, _ index: Int32) -> String? {
        guard sqlite3_column_type(statement, index) != SQLITE_NULL else { return nil }
        return textColumn(statement, index)
    }

    private func bindOptional(_ value: String?, at index: Int32, in statement: OpaquePointer) throws {
        if let value { try bind(value, at: index, in: statement) }
        else { sqlite3_bind_null(statement, index) }
    }
}
