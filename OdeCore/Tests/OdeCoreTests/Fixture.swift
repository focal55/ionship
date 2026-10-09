import Foundation
import SQLite3

private protocol Archiving { func archive(_ string: String) -> Data }

private struct LegacyArchiver: Archiving {
    @available(macOS, deprecated: 10.13)
    func archive(_ string: String) -> Data {
        NSArchiver.archivedData(withRootObject: NSAttributedString(string: string))
    }
}

/// Real typedstream, the format Messages writes to `attributedBody`. Called through a
/// protocol so the deliberate use of deprecated NSArchiver does not warn.
func archived(_ string: String) -> Data {
    (LegacyArchiver() as any Archiving).archive(string)
}

func ns(_ seconds: Double) -> Int64 { Int64(seconds * 1_000_000_000) }

let longBody = String(repeating: "Long body é ", count: 30)
let garbageBody = Data([0x04, 0x0B, 0x73, 0x74, 0x72, 0x65, 0x61, 0x6D, 0xFF, 0x00, 0x13])

/// A chat.db look-alike built from the real schema subset. The writer connection stays
/// open in WAL mode with autocheckpoint disabled so readers must honour the WAL.
final class Fixture {
    let dir: URL
    let path: String
    private var db: OpaquePointer?

    init(schema: String = Fixture.schema, seed: Bool = true) throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("ode-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        path = dir.appendingPathComponent("chat.db").path
        guard sqlite3_open(path, &db) == SQLITE_OK else { throw FixtureError(message: "open") }
        try exec("PRAGMA journal_mode=WAL; PRAGMA wal_autocheckpoint=0;")
        try exec(schema)
        if seed { try seedData() }
    }

    deinit {
        sqlite3_close(db)
        try? FileManager.default.removeItem(at: dir)
    }

    func exec(_ sql: String) throws {
        var err: UnsafeMutablePointer<CChar>?
        if sqlite3_exec(db, sql, nil, nil, &err) != SQLITE_OK {
            let message = err.map { String(cString: $0) } ?? "unknown"
            sqlite3_free(err)
            throw FixtureError(message: message)
        }
    }

    func insertMessage(
        rowID: Int64, chatID: Int64, text: String?, body: Data? = nil, handleID: Int64 = 0,
        date: Int64, isFromMe: Bool = false, associatedType: Int = 0, hasAttachments: Bool = false,
        itemType: Int = 0
    ) throws {
        let sql = """
            INSERT INTO message (ROWID, guid, text, attributedBody, handle_id, date, is_from_me,
                associated_message_type, cache_has_attachments, item_type)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { throw FixtureError(message: "prepare") }
        defer { sqlite3_finalize(stmt) }
        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        sqlite3_bind_int64(stmt, 1, rowID)
        sqlite3_bind_text(stmt, 2, "guid-\(rowID)", -1, transient)
        if let text { sqlite3_bind_text(stmt, 3, text, -1, transient) } else { sqlite3_bind_null(stmt, 3) }
        if let body {
            _ = body.withUnsafeBytes { sqlite3_bind_blob(stmt, 4, $0.baseAddress, Int32(body.count), transient) }
        } else {
            sqlite3_bind_null(stmt, 4)
        }
        sqlite3_bind_int64(stmt, 5, handleID)
        sqlite3_bind_int64(stmt, 6, date)
        sqlite3_bind_int(stmt, 7, isFromMe ? 1 : 0)
        sqlite3_bind_int(stmt, 8, Int32(associatedType))
        sqlite3_bind_int(stmt, 9, hasAttachments ? 1 : 0)
        sqlite3_bind_int(stmt, 10, Int32(itemType))
        guard sqlite3_step(stmt) == SQLITE_DONE else { throw FixtureError(message: "insert") }
        try exec("INSERT INTO chat_message_join (chat_id, message_id) VALUES (\(chatID), \(rowID))")
    }

    private func seedData() throws {
        try exec("""
            INSERT INTO handle (ROWID, id, service) VALUES
                (1, '+15551234567', 'iMessage'), (2, 'alice@example.com', 'iMessage'), (3, '+15559876543', 'SMS');
            INSERT INTO chat (ROWID, guid, chat_identifier, display_name, style, service_name) VALUES
                (1, 'iMessage;-;+15551234567', '+15551234567', '', 45, 'iMessage'),
                (2, 'iMessage;+;chat123', 'chat123', 'Fam', 43, 'SMS');
            INSERT INTO chat_handle_join (chat_id, handle_id) VALUES (1, 1), (2, 3), (2, 2);
            """)
        try insertMessage(rowID: 1, chatID: 1, text: "hello", handleID: 1, date: ns(1000))
        try insertMessage(rowID: 2, chatID: 1, text: nil, body: archived("short body"), date: ns(2000), isFromMe: true)
        try insertMessage(rowID: 3, chatID: 1, text: "", body: archived(longBody), handleID: 1, date: 3000)
        try insertMessage(rowID: 4, chatID: 1, text: "Loved “hello”", handleID: 1, date: ns(4000), associatedType: 2000)
        try insertMessage(rowID: 5, chatID: 1, text: nil, body: archived("\u{FFFC}"), date: ns(5000), isFromMe: true,
                          hasAttachments: true)
        try insertMessage(rowID: 6, chatID: 2, text: "group hi", handleID: 2, date: ns(6000))
        try insertMessage(rowID: 7, chatID: 2, text: "from me in group", date: ns(7000), isFromMe: true)
        try insertMessage(rowID: 8, chatID: 2, text: nil, body: garbageBody, handleID: 3, date: ns(8000))
        try insertMessage(rowID: 9, chatID: 2, text: nil, handleID: 2, date: ns(9000), itemType: 1)
    }

    static let schema = """
        CREATE TABLE message (ROWID INTEGER PRIMARY KEY AUTOINCREMENT, guid TEXT UNIQUE NOT NULL, text TEXT,
            attributedBody BLOB, handle_id INTEGER DEFAULT 0, date INTEGER, is_from_me INTEGER DEFAULT 0,
            associated_message_type INTEGER DEFAULT 0, cache_has_attachments INTEGER DEFAULT 0,
            item_type INTEGER DEFAULT 0);
        CREATE TABLE handle (ROWID INTEGER PRIMARY KEY AUTOINCREMENT UNIQUE, id TEXT NOT NULL, service TEXT NOT NULL);
        CREATE TABLE chat (ROWID INTEGER PRIMARY KEY AUTOINCREMENT, guid TEXT UNIQUE NOT NULL, chat_identifier TEXT,
            display_name TEXT, style INTEGER, service_name TEXT);
        CREATE TABLE chat_message_join (chat_id INTEGER REFERENCES chat (ROWID) ON DELETE CASCADE,
            message_id INTEGER REFERENCES message (ROWID) ON DELETE CASCADE, PRIMARY KEY (chat_id, message_id));
        CREATE TABLE chat_handle_join (chat_id INTEGER REFERENCES chat (ROWID) ON DELETE CASCADE,
            handle_id INTEGER REFERENCES handle (ROWID) ON DELETE CASCADE, UNIQUE(chat_id, handle_id));
        """
}

struct FixtureError: Error { let message: String }
