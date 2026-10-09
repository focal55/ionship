import Foundation

/// Something a person is waiting on from you, for the home list.
public struct Waiting: Sendable, Equatable, Identifiable {
    /// In priority order: the list shows asked before unanswered before promised before quiet.
    public enum Kind: Int, Sendable, Comparable {
        case asked, unanswered, promised, quiet

        public static func < (lhs: Kind, rhs: Kind) -> Bool { lhs.rawValue < rhs.rawValue }
    }

    public let conversationID: Int64
    public let kind: Kind
    public let text: String
    /// What the draft composer is asked to do when you reply from the list.
    public let steer: String
    /// When it started waiting; the list shows the oldest first within a kind.
    public let since: Date
    /// A dismissal lasts until a message newer than this arrives.
    public let newestMessageID: Int64
    public var id: Int64 { conversationID }

    public init(conversationID: Int64, kind: Kind, text: String, steer: String, since: Date, newestMessageID: Int64) {
        self.conversationID = conversationID
        self.kind = kind
        self.text = text
        self.steer = steer
        self.since = since
        self.newestMessageID = newestMessageID
    }
}

extension Waiting {
    static let minimumAge: TimeInterval = 3_600
    static let maximumAge: TimeInterval = 21 * 86_400

    /// Their messages since your last one, in a 1:1 conversation. `messages` must be in date order.
    /// Younger than an hour isn't waiting yet; older than three weeks is left to `quiet`.
    public static func unanswered(in conversation: Conversation, messages: [Message], now: Date = .now) -> Waiting? {
        guard !conversation.isGroup, let newest = messages.map(\.id).max() else { return nil }
        let isSpoken = { (message: Message) in message.kind == .text || message.kind == .attachmentOnly }
        let start = messages.lastIndex { $0.isFromMe && isSpoken($0) }.map { $0 + 1 } ?? messages.startIndex
        let after = messages[start...]
        let theirs = after.filter { !$0.isFromMe && isSpoken($0) }
        guard let latest = theirs.last, let first = theirs.first else { return nil }
        guard !after.contains(where: { $0.isFromMe && $0.kind == .reaction && $0.date >= latest.date }) else { return nil }
        let age = now.timeIntervalSince(latest.date)
        guard age >= minimumAge, age <= maximumAge else { return nil }
        guard let shown = theirs.last(where: { !isCloser($0.text) }) else { return nil }

        let asked = theirs.contains { $0.text?.contains("?") == true }
        let text = shown.text ?? (shown.kind == .attachmentOnly ? "Attachment" : "Message")
        return Waiting(conversationID: conversation.id, kind: asked ? .asked : .unanswered, text: text,
                       steer: asked ? "answer their question" : "reply to their last message",
                       since: first.date, newestMessageID: newest)
    }

    private static let closers: Set<String> = [
        "ok", "okay", "k", "kk", "thanks", "thank you", "thx", "ty", "lol", "haha", "hahaha", "lmao", "nice", "cool",
        "sounds good", "got it", "np", "no problem", "you too", "will do", "perfect", "great",
    ]
    private static let closingEmoji: Set<Character> = ["👍", "❤️"]

    /// A message that ends an exchange and doesn't need a reply.
    static func isCloser(_ text: String?) -> Bool {
        guard let text else { return false }
        let trimmed = text.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.contains("?") else { return false }
        if trimmed.allSatisfy({ closingEmoji.contains($0) || $0.isWhitespace }) { return true }
        var core = Substring(trimmed)
        while let last = core.last, last.isPunctuation || last.isWhitespace || isEmoji(last) { core = core.dropLast() }
        return closers.contains(String(core))
    }

    /// Emoji, but not the digits and symbols Unicode also flags as emoji-capable.
    private static func isEmoji(_ character: Character) -> Bool {
        character.unicodeScalars.contains { $0.properties.isEmojiPresentation || ($0.properties.isEmoji && $0.value > 0x238C) }
    }
}
