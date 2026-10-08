import Foundation

/// A message where you may have promised something, with what was said afterwards. Phrase
/// matching only finds candidates; deciding whether a promise was kept needs a model.
public struct OpenLoopCandidate: Sendable, Equatable, Identifiable {
    public let message: Message
    public let following: [Message]
    public var id: Int64 { message.id }

    private static let commitments = [
        "i'll ", "i will ", "i'm going to ", "im going to ", "i'm gonna ", "im gonna ",
        "let me ", "i owe you", "i promise",
    ]
    /// Phrases that contain a commitment word without being one: arrival updates and requests.
    private static let notCommitments = ["i'll be there", "i'll be right", "be there in", "on my way", "omw", "let me know"]

    public static func find(in messages: [Message], within window: TimeInterval = 60 * 86_400,
                            now: Date = .now, followingWindow: TimeInterval = 7 * 86_400,
                            followingLimit: Int = 12) -> [OpenLoopCandidate] {
        let spoken = messages.filter { $0.kind == .text || $0.kind == .attachmentOnly }
            .sorted { ($0.date, $0.id) < ($1.date, $1.id) }
        let cutoff = now.addingTimeInterval(-window)

        return spoken.enumerated().compactMap { index, message in
            guard message.isFromMe, message.date >= cutoff, let text = message.text, isCommitment(text) else { return nil }
            let deadline = message.date.addingTimeInterval(followingWindow)
            let following = spoken[(index + 1)...].prefix { $0.date <= deadline }.prefix(followingLimit)
            return OpenLoopCandidate(message: message, following: Array(following))
        }
        .reversed()
    }

    static func isCommitment(_ text: String) -> Bool {
        let normalized = text.lowercased().replacingOccurrences(of: "\u{2019}", with: "'")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard normalized.count >= 12, !normalized.hasSuffix("?") else { return false }
        let padded = normalized + " "
        return commitments.contains { padded.contains($0) } && !notCommitments.contains { padded.contains($0) }
    }
}
