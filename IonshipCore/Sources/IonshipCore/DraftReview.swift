import Foundation

extension WritingStyle {
    /// How closely a draft fits your usual length, capitalization and emoji habit with this
    /// person, from 0 to 1. Length counts most because it is what reads as "not you" first.
    public func match(_ text: String) -> Double {
        let lengthScore: Double
        if typicalLength == 0 {
            lengthScore = 1
        } else if text.isEmpty {
            lengthScore = 0
        } else {
            let ratio = Double(text.count) / Double(typicalLength)
            lengthScore = min(ratio, 1 / ratio)
        }
        let startsLowercase = text.first(where: \.isLetter)?.isLowercase ?? true
        let casingScore: Double = startsLowercase == (lowercaseShare >= 0.5) ? 1 : 0
        let hasEmoji = text.unicodeScalars.contains(where: \.properties.isEmojiPresentation)
        let emojiScore: Double = hasEmoji == usesEmoji ? 1 : 0
        return 0.6 * lengthScore + 0.25 * casingScore + 0.15 * emojiScore
    }
}

/// Plain checks shown beside a draft before you send it.
public enum DraftChecks {
    public struct Check: Sendable, Equatable, Hashable {
        public let ok: Bool
        public let text: String

        public init(ok: Bool, text: String) {
            self.ok = ok
            self.text = text
        }
    }

    private static let stopwords: Set<String> = [
        "about", "after", "again", "also", "been", "could", "does", "ever", "from", "have", "just", "like", "make",
        "really", "should", "some", "still", "that", "their", "them", "then", "there", "these", "they", "this", "those",
        "want", "were", "what", "when", "where", "which", "will", "with", "would", "your",
    ]

    public static func evaluate(_ draft: String, style: WritingStyle, openLoops: [String], lastIncoming: String?) -> [Check] {
        var checks: [Check] = []
        let lowered = draft.lowercased()

        for loop in openLoops where keywords(loop).contains(where: lowered.contains) {
            checks.append(Check(ok: true, text: "Closes your open loop: \(loop)"))
        }

        if style.typicalLength > 0, !draft.isEmpty {
            let ratio = Double(draft.count) / Double(style.typicalLength)
            checks.append(ratio > 2 ? Check(ok: false, text: "Longer than you usually write to them")
                : ratio < 0.5 ? Check(ok: false, text: "Shorter than you usually write to them")
                : Check(ok: true, text: "Matches your usual length with them"))
        }

        if let question = lastIncoming?.trimmingCharacters(in: .whitespacesAndNewlines), question.hasSuffix("?") {
            checks.append(keywords(question).contains(where: lowered.contains)
                ? Check(ok: true, text: "Answers their question")
                : Check(ok: false, text: "They asked: “\(question)”"))
        }
        return checks
    }

    private static func keywords(_ text: String) -> [String] {
        text.lowercased()
            .split(whereSeparator: { !$0.isLetter })
            .map(String.init)
            .filter { $0.count >= 4 && !stopwords.contains($0) }
    }
}
