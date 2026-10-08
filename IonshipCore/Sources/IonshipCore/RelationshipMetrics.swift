import Foundation

/// Relationship health derived from timestamps alone: no message text, no model.
public struct RelationshipMetrics: Sendable, Equatable {
    public struct Week: Sendable, Equatable {
        public let start: Date
        public let mine: Int
        public let theirs: Int
    }

    public let messageCount: Int
    /// Bursts of messages separated by a quiet gap of at least `sessionGap`.
    public let conversations: Int
    public let youStartShare: Double?
    public let yourMedianReply: TimeInterval?
    public let theirMedianReply: TimeInterval?
    public let yourRecentMedianReply: TimeInterval?
    public let lastLongConversation: Date?
    public let usualGapBetweenLongConversations: TimeInterval?
    public let weekly: [Week]

    public static let recentWindow: TimeInterval = 90 * 86_400

    public enum Observation: Sendable, Hashable {
        case theyStartMost(share: Double)
        case youStartMost(share: Double)
        case repliesSlowing(recent: TimeInterval, usual: TimeInterval)
        case overdue(since: TimeInterval, usual: TimeInterval)
    }

    /// Only deviations worth a sentence; a balanced relationship yields none.
    public func observations(now: Date = .now) -> [Observation] {
        var result: [Observation] = []
        if let share = youStartShare {
            if share < 0.3 { result.append(.theyStartMost(share: 1 - share)) }
            if share > 0.7 { result.append(.youStartMost(share: share)) }
        }
        if let recent = yourRecentMedianReply, let usual = yourMedianReply, recent > usual * 1.5 {
            result.append(.repliesSlowing(recent: recent, usual: usual))
        }
        if let last = lastLongConversation, let usual = usualGapBetweenLongConversations {
            let since = now.timeIntervalSince(last)
            if since > usual * 1.5 { result.append(.overdue(since: since, usual: usual)) }
        }
        return result
    }

    public static func compute(
        _ messages: [Message], now: Date = .now,
        sessionGap: TimeInterval = 6 * 3600, longConversationLength: Int = 20
    ) -> RelationshipMetrics {
        let spoken = messages.filter { $0.kind == .text || $0.kind == .attachmentOnly }.sorted { $0.date < $1.date }

        var sessions: [[Message]] = []
        for message in spoken {
            if let last = sessions.last?.last, message.date.timeIntervalSince(last.date) < sessionGap {
                sessions[sessions.count - 1].append(message)
            } else {
                sessions.append([message])
            }
        }

        var yourReplies: [(at: Date, delay: TimeInterval)] = []
        var theirReplies: [TimeInterval] = []
        for session in sessions {
            for (previous, current) in zip(session, session.dropFirst()) where previous.isFromMe != current.isFromMe {
                let delay = current.date.timeIntervalSince(previous.date)
                if current.isFromMe { yourReplies.append((current.date, delay)) } else { theirReplies.append(delay) }
            }
        }

        let longStarts = sessions.filter { $0.count >= longConversationLength }.compactMap(\.first?.date)
        let longGaps = zip(longStarts, longStarts.dropFirst()).map { $1.timeIntervalSince($0) }
        let recentCutoff = now.addingTimeInterval(-recentWindow)

        return RelationshipMetrics(
            messageCount: spoken.count,
            conversations: sessions.count,
            youStartShare: sessions.isEmpty ? nil : Double(sessions.filter { $0.first?.isFromMe == true }.count) / Double(sessions.count),
            yourMedianReply: median(yourReplies.map(\.delay)),
            theirMedianReply: median(theirReplies),
            yourRecentMedianReply: median(yourReplies.filter { $0.at >= recentCutoff }.map(\.delay)),
            lastLongConversation: longStarts.last,
            usualGapBetweenLongConversations: median(longGaps),
            weekly: weeklyVolume(spoken, now: now)
        )
    }

    private static func weeklyVolume(_ messages: [Message], now: Date) -> [Week] {
        let week: TimeInterval = 7 * 86_400
        var mine = Array(repeating: 0, count: 52)
        var theirs = Array(repeating: 0, count: 52)
        for message in messages {
            let age = now.timeIntervalSince(message.date)
            guard age >= 0 else { continue }
            let bucket = 51 - Int(age / week)
            guard bucket >= 0 else { continue }
            if message.isFromMe { mine[bucket] += 1 } else { theirs[bucket] += 1 }
        }
        return (0..<52).map { Week(start: now.addingTimeInterval(-Double(52 - $0) * week), mine: mine[$0], theirs: theirs[$0]) }
    }

    private static func median(_ values: [TimeInterval]) -> TimeInterval? {
        guard !values.isEmpty else { return nil }
        let sorted = values.sorted()
        let mid = sorted.count / 2
        return sorted.count.isMultiple(of: 2) ? (sorted[mid - 1] + sorted[mid]) / 2 : sorted[mid]
    }
}
