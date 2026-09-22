import Foundation
import CSQLite

public enum StoreError: LocalizedError {
    case database(String)
    public var errorDescription: String? {
        switch self { case .database(let message): return "The history database failed: \(message)" }
    }
}

public actor MemoryStore {
    private var db: OpaquePointer?
    public let directory: URL
    private let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    public init(directory: URL) throws {
        self.directory = directory
        try FileManager.default.createDirectory(at: directory.appendingPathComponent("images"), withIntermediateDirectories: true)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
        var handle: OpaquePointer?
        guard sqlite3_open(directory.appendingPathComponent("history.sqlite").path, &handle) == SQLITE_OK else {
            if let handle { sqlite3_close(handle) }
            throw StoreError.database("Cannot open the database.")
        }
        db = handle
        let schema = """
        PRAGMA journal_mode=WAL;
        PRAGMA secure_delete=ON;
        CREATE TABLE IF NOT EXISTS memories (
          id TEXT PRIMARY KEY, captured REAL NOT NULL, app TEXT NOT NULL, title TEXT NOT NULL,
          body TEXT NOT NULL, image TEXT NOT NULL, url TEXT
        );
        CREATE INDEX IF NOT EXISTS captured_idx ON memories(captured);
        CREATE VIRTUAL TABLE IF NOT EXISTS memory_search USING fts5(
          title, body, app, content='memories', content_rowid='rowid', tokenize='unicode61'
        );
        CREATE TRIGGER IF NOT EXISTS memory_insert AFTER INSERT ON memories BEGIN
          INSERT INTO memory_search(rowid,title,body,app) VALUES(new.rowid,new.title,new.body,new.app);
        END;
        CREATE TRIGGER IF NOT EXISTS memory_delete AFTER DELETE ON memories BEGIN
          INSERT INTO memory_search(memory_search,rowid,title,body,app)
            VALUES('delete',old.rowid,old.title,old.body,old.app);
        END;
        """
        guard sqlite3_exec(handle, schema, nil, nil, nil) == SQLITE_OK else {
            let message = String(cString: sqlite3_errmsg(handle))
            sqlite3_close(handle)
            db = nil
            throw StoreError.database(message)
        }
    }

    deinit { sqlite3_close(db) }

    private func statement(_ sql: String) throws -> OpaquePointer {
        var result: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &result, nil) == SQLITE_OK, let result else { throw error() }
        return result
    }

    private func error() -> StoreError { .database(String(cString: sqlite3_errmsg(db))) }
    private func bind(_ value: String?, to index: Int32, in stmt: OpaquePointer) {
        if let value { sqlite3_bind_text(stmt, index, value, -1, transient) }
        else { sqlite3_bind_null(stmt, index) }
    }
    private func string(_ stmt: OpaquePointer, _ column: Int32) -> String {
        guard let text = sqlite3_column_text(stmt, column) else { return "" }
        return String(cString: text)
    }

    public func insert(_ memory: Memory) throws {
        let stmt = try statement("INSERT INTO memories(id,captured,app,title,body,image,url) VALUES(?,?,?,?,?,?,?)")
        defer { sqlite3_finalize(stmt) }
        bind(memory.id, to: 1, in: stmt)
        sqlite3_bind_double(stmt, 2, memory.date.timeIntervalSince1970)
        for (index, value) in [memory.app, memory.title, memory.text, memory.imagePath, memory.sourceURL].enumerated() {
            bind(value, to: Int32(index + 3), in: stmt)
        }
        guard sqlite3_step(stmt) == SQLITE_DONE else { throw error() }
    }

    public func search(_ query: String = "", since: Date? = nil, app: String? = nil, limit: Int = 150) throws -> [Memory] {
        let expression = SearchQuery.expression(query)
        let sql = expression == nil ? """
          SELECT id,captured,app,title,body,image,url,substr(body,1,240) FROM memories
          WHERE captured >= ? AND (? IS NULL OR app = ?) ORDER BY captured DESC LIMIT ?
          """ : """
          SELECT m.id,m.captured,m.app,m.title,m.body,m.image,m.url,
            snippet(memory_search,1,'','',' … ',36)
          FROM memory_search JOIN memories m ON m.rowid=memory_search.rowid
          WHERE memory_search MATCH ? AND m.captured >= ? AND (? IS NULL OR m.app = ?)
          ORDER BY bm25(memory_search,2.0,1.0,0.5),m.captured DESC LIMIT ?
          """
        let stmt = try statement(sql)
        defer { sqlite3_finalize(stmt) }
        var index: Int32 = 1
        if let expression { bind(expression, to: index, in: stmt); index += 1 }
        sqlite3_bind_double(stmt, index, since?.timeIntervalSince1970 ?? 0)
        bind(app, to: index + 1, in: stmt)
        bind(app, to: index + 2, in: stmt)
        sqlite3_bind_int(stmt, index + 3, Int32(max(1, min(limit, 1000))))
        var results: [Memory] = []
        var status = sqlite3_step(stmt)
        while status == SQLITE_ROW {
            results.append(Memory(id: string(stmt, 0), date: Date(timeIntervalSince1970: sqlite3_column_double(stmt, 1)),
                app: string(stmt, 2), title: string(stmt, 3), text: string(stmt, 4), imagePath: string(stmt, 5),
                sourceURL: sqlite3_column_type(stmt, 6) == SQLITE_NULL ? nil : string(stmt, 6), snippet: string(stmt, 7)))
            status = sqlite3_step(stmt)
        }
        guard status == SQLITE_DONE else { throw error() }
        return results
    }

    public func count() throws -> Int {
        let stmt = try statement("SELECT count(*) FROM memories")
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_step(stmt) == SQLITE_ROW else { throw error() }
        return Int(sqlite3_column_int(stmt, 0))
    }

    public func applications() throws -> [String] {
        let stmt = try statement("SELECT DISTINCT app FROM memories ORDER BY app COLLATE NOCASE")
        defer { sqlite3_finalize(stmt) }
        var apps: [String] = []
        var status = sqlite3_step(stmt)
        while status == SQLITE_ROW {
            apps.append(string(stmt, 0))
            status = sqlite3_step(stmt)
        }
        guard status == SQLITE_DONE else { throw error() }
        return apps
    }

    public func delete(id: String) throws {
        let stmt = try statement("SELECT image FROM memories WHERE id=?")
        bind(id, to: 1, in: stmt)
        let path = sqlite3_step(stmt) == SQLITE_ROW ? string(stmt, 0) : nil
        sqlite3_finalize(stmt)
        let deletion = try statement("DELETE FROM memories WHERE id=?")
        defer { sqlite3_finalize(deletion) }
        bind(id, to: 1, in: deletion)
        guard sqlite3_step(deletion) == SQLITE_DONE else { throw error() }
        if let path { try removeImage(path) }
    }

    private func removeImage(_ path: String) throws {
        let url = URL(fileURLWithPath: path).standardizedFileURL
        guard url.deletingLastPathComponent() == directory.appendingPathComponent("images").standardizedFileURL else { return }
        if FileManager.default.fileExists(atPath: path) { try FileManager.default.removeItem(at: url) }
    }

    public func prune(before date: Date, maximumCount: Int = 5000) throws {
        let stmt = try statement("""
          SELECT id FROM memories WHERE captured < ? OR id IN
          (SELECT id FROM memories ORDER BY captured DESC LIMIT -1 OFFSET ?)
          """)
        sqlite3_bind_double(stmt, 1, date.timeIntervalSince1970)
        sqlite3_bind_int(stmt, 2, Int32(maximumCount))
        var ids: [String] = []
        while sqlite3_step(stmt) == SQLITE_ROW { ids.append(string(stmt, 0)) }
        sqlite3_finalize(stmt)
        for id in ids { try delete(id: id) }
        if !ids.isEmpty { try compact() }
    }

    public func deleteAll() throws {
        guard sqlite3_exec(db, "DELETE FROM memories", nil, nil, nil) == SQLITE_OK else { throw error() }
        for url in try FileManager.default.contentsOfDirectory(at: directory.appendingPathComponent("images"), includingPropertiesForKeys: nil) {
            try FileManager.default.removeItem(at: url)
        }
        try compact()
    }

    private func compact() throws {
        guard sqlite3_exec(db, "INSERT INTO memory_search(memory_search) VALUES('rebuild'); PRAGMA wal_checkpoint(TRUNCATE); VACUUM;", nil, nil, nil) == SQLITE_OK else { throw error() }
    }
}
