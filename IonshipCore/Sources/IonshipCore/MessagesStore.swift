import Foundation
import SQLite3

/// Read-only access to a Messages `chat.db`. The schema is undocumented and owned by Apple;
/// `schemaReport()` lists which of the columns this relies on are present.
public final class MessagesStore {
    public static var defaultPath: String {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Messages/chat.db").path
    }

    static let requiredColumns: [String: [String]] = [
        "message": ["guid", "text", "attributedBody", "handle_id", "date", "is_from_me",
                    "associated_message_type", "cache_has_attachments", "item_type"],
        "handle": ["id"],
        "chat": ["chat_identifier", "display_name", "style"],
        "chat_message_join": ["chat_id", "message_id"],
        "chat_handle_join": ["chat_id", "handle_id"],
    ]

    private static let groupChatStyle: Int64 = 43

    private static let messageColumns = """
        m.ROWID, m.guid, m.text, m.attributedBody, m.is_from_me, m.date, m.associated_message_type,
        m.cache_has_attachments, m.item_type, h.id, cmj.chat_id
        FROM message m
        JOIN chat_message_join cmj ON cmj.message_id = m.ROWID
        LEFT JOIN handle h ON h.ROWID = m.handle_id
        """

    private let db: OpaquePointer

    public init(path: String = MessagesStore.defaultPath) throws {
        // mode=ro through a URI keeps the WAL readable while guaranteeing we never write.
        let uri = URL(fileURLWithPath: path).absoluteString + "?mode=ro"
        var handle: OpaquePointer?
        let code = sqlite3_open_v2(uri, &handle, SQLITE_OPEN_READONLY | SQLITE_OPEN_URI, nil)
        guard code == SQLITE_OK, let handle else {
            let message = handle.map { String(cString: sqlite3_errmsg($0)) } ?? "unable to open database file"
            sqlite3_close(handle)
            throw MessagesStoreError.classifyOpenFailure(path: path, code: code, message: message)
        }
        db = handle
        // Opening is lazy; TCC denials only surface on first read.
        do {
            try execute("SELECT 1 FROM sqlite_master LIMIT 1")
        } catch {
            let code = sqlite3_extended_errcode(handle) & 0xFF
            let message = String(cString: sqlite3_errmsg(handle))
            sqlite3_close(handle)
            throw MessagesStoreError.classifyOpenFailure(path: path, code: code, message: message)
        }
    }

    deinit {
        sqlite3_close(db)
    }

    public func chats() throws -> [Chat] {
        var participants: [Int64: [String]] = [:]
        try query("""
            SELECT chj.chat_id, h.id FROM chat_handle_join chj
            JOIN handle h ON h.ROWID = chj.handle_id ORDER BY h.id
            """) { row in
            participants[row.int(0), default: []].append(row.string(1) ?? "")
        }

        var chats: [Chat] = []
        try query("""
            SELECT c.ROWID, c.chat_identifier, c.display_name, c.style, COUNT(m.ROWID), MAX(m.date)
            FROM chat c
            LEFT JOIN chat_message_join cmj ON cmj.chat_id = c.ROWID
            LEFT JOIN message m ON m.ROWID = cmj.message_id
            GROUP BY c.ROWID
            """) { row in
            let id = row.int(0)
            let displayName = row.string(2).flatMap { $0.isEmpty ? nil : $0 }
            chats.append(Chat(
                id: id,
                identifier: row.string(1) ?? "",
                displayName: displayName,
                isGroup: row.int(3) == Self.groupChatStyle,
                participants: participants[id] ?? [],
                messageCount: Int(row.int(4)),
                lastMessageDate: row.isNull(5) ? nil : Self.date(fromMessagesTimestamp: row.int(5))
            ))
        }
        return chats.sorted { ($0.lastMessageDate ?? .distantPast) > ($1.lastMessageDate ?? .distantPast) }
    }

    /// The most recent `limit` messages with ROWID below `before`, oldest first.
    public func messages(chatID: Int64, limit: Int = 500, before: Int64? = nil) throws -> [Message] {
        var messages: [Message] = []
        try query(
            "SELECT \(Self.messageColumns) WHERE cmj.chat_id = ? AND m.ROWID < ? ORDER BY m.ROWID DESC LIMIT ?",
            bind: [chatID, before ?? .max, Int64(limit)]
        ) { messages.append(Self.message(from: $0)) }
        return messages.reversed()
    }

    public func newMessages(after rowID: Int64, limit: Int = .max) throws -> [Message] {
        var messages: [Message] = []
        try query("SELECT \(Self.messageColumns) WHERE m.ROWID > ? ORDER BY m.ROWID LIMIT ?", bind: [rowID, Int64(limit)]) {
            messages.append(Self.message(from: $0))
        }
        return messages
    }

    public func schemaReport() throws -> SchemaReport {
        var present: [String] = []
        var missing: [String] = []
        for table in Self.requiredColumns.keys.sorted() {
            var columns = Set<String>()
            try query("SELECT name FROM pragma_table_info(?)", bind: [table]) { columns.insert($0.string(0) ?? "") }
            for column in Self.requiredColumns[table]! {
                let name = "\(table).\(column)"
                if columns.contains(column) { present.append(name) } else { missing.append(name) }
            }
        }
        return SchemaReport(present: present, missing: missing)
    }

    func execute(_ sql: String) throws {
        var error: UnsafeMutablePointer<CChar>?
        guard sqlite3_exec(db, sql, nil, nil, &error) == SQLITE_OK else {
            let message = error.map { String(cString: $0) } ?? String(cString: sqlite3_errmsg(db))
            sqlite3_free(error)
            throw MessagesStoreError.query(message: message)
        }
    }

    // Messages switched from seconds to nanoseconds since 2001 in High Sierra; real values in
    // the two units differ by about nine orders of magnitude.
    static func date(fromMessagesTimestamp value: Int64) -> Date {
        let seconds = value > 100_000_000_000 ? Double(value) / 1_000_000_000 : Double(value)
        return Date(timeIntervalSinceReferenceDate: seconds)
    }

    private static func message(from row: Row) -> Message {
        let isFromMe = row.int(4) != 0
        let (text, source) = resolveText(column: row.string(2), body: row.data(3))
        let kind: Message.Kind =
            if row.int(6) != 0 { .reaction }
            else if row.int(8) != 0 { .other }
            else if text != nil { .text }
            else if row.int(7) != 0 { .attachmentOnly }
            else { .other }
        return Message(
            id: row.int(0),
            guid: row.string(1) ?? "",
            chatID: row.int(10),
            sender: isFromMe ? nil : row.string(9),
            isFromMe: isFromMe,
            date: date(fromMessagesTimestamp: row.int(5)),
            text: text,
            textSource: source,
            kind: kind
        )
    }

    private static func resolveText(column: String?, body: Data?) -> (String?, Message.TextSource) {
        if let column, !column.isEmpty { return (column, .column) }
        guard let body else { return (nil, .none) }
        guard let decoded = AttributedBodyDecoder.decodeDetailed(body) else { return (nil, .undecodable) }
        return (decoded.text.isEmpty ? nil : decoded.text, .attributedBody(decoded.strategy))
    }

    private func query(_ sql: String, bind values: [any Bindable] = [], row handler: (Row) throws -> Void) throws {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            throw MessagesStoreError.query(message: String(cString: sqlite3_errmsg(db)))
        }
        defer { sqlite3_finalize(statement) }
        for (index, value) in values.enumerated() { value.bind(to: statement, at: Int32(index + 1)) }

        while true {
            switch sqlite3_step(statement) {
            case SQLITE_ROW: try handler(Row(statement: statement))
            case SQLITE_DONE: return
            default: throw MessagesStoreError.query(message: String(cString: sqlite3_errmsg(db)))
            }
        }
    }
}

private struct Row {
    let statement: OpaquePointer

    func isNull(_ index: Int32) -> Bool { sqlite3_column_type(statement, index) == SQLITE_NULL }
    func int(_ index: Int32) -> Int64 { sqlite3_column_int64(statement, index) }

    func string(_ index: Int32) -> String? {
        sqlite3_column_text(statement, index).map { String(cString: $0) }
    }

    func data(_ index: Int32) -> Data? {
        guard let bytes = sqlite3_column_blob(statement, index) else { return nil }
        return Data(bytes: bytes, count: Int(sqlite3_column_bytes(statement, index)))
    }
}

private protocol Bindable { func bind(to statement: OpaquePointer, at index: Int32) }

extension Int64: Bindable {
    fileprivate func bind(to statement: OpaquePointer, at index: Int32) { sqlite3_bind_int64(statement, index, self) }
}

extension String: Bindable {
    fileprivate func bind(to statement: OpaquePointer, at index: Int32) {
        sqlite3_bind_text(statement, index, self, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
    }
}
