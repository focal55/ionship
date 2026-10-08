import Foundation
import NaturalLanguage
import SQLite3

public protocol Embedder {
    /// A vector for the text, or nil when the model has nothing to say about it.
    func vector(for text: String) -> [Float]?
}

/// A short run of messages, the unit the memory index stores and returns.
public struct Moment: Sendable, Equatable, Identifiable {
    public let conversationID: Int64
    public let firstMessageID: Int64
    public let lastMessageID: Int64
    public let start: Date
    public let end: Date
    public let text: String
    public var id: String { "\(conversationID)-\(firstMessageID)" }

    /// Only sessions that have been quiet for `gap` before `closedBefore` are split, so a
    /// moment never changes after it is indexed.
    public static func split(
        _ messages: [Message], conversationID: Int64, name: (String?) -> String,
        closedBefore: Date = .now, gap: TimeInterval = 6 * 3600, window: Int = 8
    ) -> [Moment] {
        let sessions = RelationshipMetrics.sessions(of: RelationshipMetrics.spokenMessages(messages), gap: gap)
        return sessions
            .filter { ($0.last?.date.addingTimeInterval(gap) ?? .distantFuture) <= closedBefore }
            .flatMap { session -> [Moment] in
                let worded = session.filter { $0.text?.isEmpty == false }
                return stride(from: 0, to: worded.count, by: window).map { offset in
                    let slice = worded[offset..<min(offset + window, worded.count)]
                    let text = slice.map { "\(name($0.isFromMe ? nil : $0.sender)): \($0.text!)" }.joined(separator: "\n")
                    return Moment(conversationID: conversationID, firstMessageID: slice.first!.id, lastMessageID: slice.last!.id,
                                  start: slice.first!.date, end: slice.last!.date, text: String(text.prefix(1200)))
                }
            }
    }
}

/// Apple's on-device transformer embedding, mean-pooled over tokens.
public struct ContextualEmbedder: Embedder {
    private let model: NLContextualEmbedding

    public init?() {
        guard let model = NLContextualEmbedding(language: .english), model.hasAvailableAssets, (try? model.load()) != nil else {
            return nil
        }
        self.model = model
    }

    public func vector(for text: String) -> [Float]? {
        guard let result = try? model.embeddingResult(for: text, language: .english) else { return nil }
        var sum = [Double](repeating: 0, count: model.dimension)
        var count = 0.0
        result.enumerateTokenVectors(in: text.startIndex..<text.endIndex) { vector, _ in
            for i in vector.indices { sum[i] += vector[i] }
            count += 1
            return true
        }
        return count == 0 ? nil : sum.map { Float($0 / count) }
    }
}

/// A local, persistent index of moments with hybrid search: meaning similarity from the
/// embedder plus a boost for the query's literal words, which embeddings handle poorly
/// (names, places, specifics).
public final class MemoryIndex {
    public struct Hit: Sendable, Equatable {
        public let moment: Moment
        public let score: Float
    }

    private static let literalWeight: Float = 0.15

    private let db: OpaquePointer
    private var cache: [(moment: Moment, vector: [Float]?, lowered: String)]?

    public init(path: String) throws {
        try FileManager.default.createDirectory(atPath: (path as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
        var handle: OpaquePointer?
        guard sqlite3_open_v2(path, &handle, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE, nil) == SQLITE_OK, let handle else {
            sqlite3_close(handle)
            throw MessagesStoreError.cannotOpen(path: path, reason: "could not open memory index")
        }
        db = handle
        try execute("""
            CREATE TABLE IF NOT EXISTS moment (
                conversation_id INTEGER NOT NULL, first_message_id INTEGER NOT NULL, last_message_id INTEGER NOT NULL,
                start REAL NOT NULL, end REAL NOT NULL, text TEXT NOT NULL, vector BLOB,
                PRIMARY KEY (conversation_id, first_message_id))
            """)
    }

    deinit {
        sqlite3_close(db)
    }

    public func add(_ moments: [Moment], embedder: any Embedder) throws {
        try execute("BEGIN")
        do {
            for moment in moments {
                try insert(moment, vector: embedder.vector(for: moment.text).map(Self.normalized))
            }
            try execute("COMMIT")
        } catch {
            try? execute("ROLLBACK")
            throw error
        }
        cache = nil
    }

    public func indexedThrough(conversationID: Int64) throws -> Int64 {
        var result: Int64 = 0
        try query("SELECT COALESCE(MAX(last_message_id), 0) FROM moment WHERE conversation_id = ?", bind: [.int(conversationID)]) {
            result = sqlite3_column_int64($0, 0)
        }
        return result
    }

    public func count() throws -> Int {
        var result = 0
        try query("SELECT COUNT(*) FROM moment") { result = Int(sqlite3_column_int64($0, 0)) }
        return result
    }

    public func search(_ text: String, embedder: any Embedder, limit: Int = 20) throws -> [Hit] {
        let rows = try loadCache()
        let queryVector = embedder.vector(for: text).map(Self.normalized)
        let words = text.lowercased().split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init).filter { $0.count >= 2 }

        return rows.compactMap { row -> Hit? in
            var score: Float = 0
            if let queryVector, let vector = row.vector, vector.count == queryVector.count {
                score += zip(queryVector, vector).reduce(0) { $0 + $1.0 * $1.1 }
            }
            if !words.isEmpty {
                let matched = words.filter { row.lowered.contains($0) }.count
                score += Self.literalWeight * Float(matched) / Float(words.count)
            }
            return score > 0 ? Hit(moment: row.moment, score: score) : nil
        }
        .sorted { $0.score > $1.score }
        .prefix(limit)
        .map { $0 }
    }

    private func loadCache() throws -> [(moment: Moment, vector: [Float]?, lowered: String)] {
        if let cache { return cache }
        var rows: [(moment: Moment, vector: [Float]?, lowered: String)] = []
        try query("SELECT conversation_id, first_message_id, last_message_id, start, end, text, vector FROM moment") { statement in
            let text = String(cString: sqlite3_column_text(statement, 5))
            let moment = Moment(
                conversationID: sqlite3_column_int64(statement, 0), firstMessageID: sqlite3_column_int64(statement, 1),
                lastMessageID: sqlite3_column_int64(statement, 2),
                start: Date(timeIntervalSinceReferenceDate: sqlite3_column_double(statement, 3)),
                end: Date(timeIntervalSinceReferenceDate: sqlite3_column_double(statement, 4)), text: text)
            var vector: [Float]?
            if let bytes = sqlite3_column_blob(statement, 6) {
                let count = Int(sqlite3_column_bytes(statement, 6)) / MemoryLayout<Float>.size
                vector = Array(UnsafeBufferPointer(start: bytes.assumingMemoryBound(to: Float.self), count: count))
            }
            rows.append((moment, vector, text.lowercased()))
        }
        cache = rows
        return rows
    }

    private func insert(_ moment: Moment, vector: [Float]?) throws {
        var bindings: [Binding] = [
            .int(moment.conversationID), .int(moment.firstMessageID), .int(moment.lastMessageID),
            .double(moment.start.timeIntervalSinceReferenceDate), .double(moment.end.timeIntervalSinceReferenceDate), .text(moment.text),
        ]
        bindings.append(vector.map { vector in .blob(vector.withUnsafeBufferPointer { Data(buffer: $0) }) } ?? .null)
        try query("INSERT OR REPLACE INTO moment VALUES (?, ?, ?, ?, ?, ?, ?)", bind: bindings) { _ in }
    }

    private static func normalized(_ vector: [Float]) -> [Float] {
        let length = vector.reduce(0) { $0 + $1 * $1 }.squareRoot()
        return length > 0 ? vector.map { $0 / length } : vector
    }

    private enum Binding {
        case int(Int64), double(Double), text(String), blob(Data), null
    }

    private func execute(_ sql: String) throws {
        guard sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK else {
            throw MessagesStoreError.query(message: String(cString: sqlite3_errmsg(db)))
        }
    }

    private func query(_ sql: String, bind values: [Binding] = [], row: (OpaquePointer) -> Void) throws {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            throw MessagesStoreError.query(message: String(cString: sqlite3_errmsg(db)))
        }
        defer { sqlite3_finalize(statement) }
        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        for (offset, value) in values.enumerated() {
            let index = Int32(offset + 1)
            switch value {
            case .int(let int): sqlite3_bind_int64(statement, index, int)
            case .double(let double): sqlite3_bind_double(statement, index, double)
            case .text(let text): sqlite3_bind_text(statement, index, text, -1, transient)
            case .blob(let data): _ = data.withUnsafeBytes { sqlite3_bind_blob(statement, index, $0.baseAddress, Int32(data.count), transient) }
            case .null: sqlite3_bind_null(statement, index)
            }
        }
        while true {
            switch sqlite3_step(statement) {
            case SQLITE_ROW: row(statement)
            case SQLITE_DONE: return
            default: throw MessagesStoreError.query(message: String(cString: sqlite3_errmsg(db)))
            }
        }
    }
}
