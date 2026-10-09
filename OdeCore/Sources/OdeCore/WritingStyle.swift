import Foundation

/// How you write to one person, from your recent messages, so drafts can sound like you.
public struct WritingStyle: Sendable, Equatable {
    public let sampleSize: Int
    public let typicalLength: Int
    public let lowercaseShare: Double
    public let usesEmoji: Bool

    public init(of messages: [Message], recent: Int = 100) {
        let texts = messages
            .filter { $0.isFromMe && $0.kind == .text && $0.text?.isEmpty == false }
            .sorted { $0.date < $1.date }
            .suffix(recent)
            .compactMap(\.text)
        sampleSize = texts.count
        typicalLength = texts.isEmpty ? 0 : texts.map(\.count).sorted()[texts.count / 2]
        let lowercase = texts.filter { $0.first(where: \.isLetter)?.isLowercase ?? true }.count
        lowercaseShare = texts.isEmpty ? 0 : Double(lowercase) / Double(texts.count)
        let withEmoji = texts.filter { $0.unicodeScalars.contains(where: \.properties.isEmojiPresentation) }.count
        usesEmoji = !texts.isEmpty && Double(withEmoji) / Double(texts.count) >= 0.1
    }

    /// A sentence for a model prompt; nil until there are enough messages to say anything.
    public var summary: String? {
        guard sampleSize >= 5 else { return nil }
        let casing = lowercaseShare >= 0.7 ? "mostly lowercase" : lowercaseShare <= 0.3 ? "usually capitalized" : "mixed capitalization"
        return "Your messages to them are usually about \(typicalLength) characters, \(casing), \(usesEmoji ? "often with emoji" : "with no emoji")."
    }
}
