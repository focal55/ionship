import Foundation

/// Group health: each member's part in the conversation, from timestamps alone.
public struct GroupMetrics: Sendable, Equatable {
    public struct Member: Sendable, Equatable {
        /// nil is the user.
        public let handle: String?
        public let messages: Int
        public let share: Double
        public let starts: Int
        public let startShare: Double
        public let medianResponse: TimeInterval?
        public let recentShare: Double?
        public let lastActive: Date?
    }

    public enum Observation: Sendable, Hashable {
        case carries(handle: String?, share: Double)
        case drifting(handle: String?, usual: Double, recent: Double)
    }

    public let messageCount: Int
    public let conversations: Int
    public let members: [Member]
    public let observations: [Observation]
    public let weekly: [RelationshipMetrics.Week]

    public static func compute(
        _ messages: [Message], participants: [String], now: Date = .now, sessionGap: TimeInterval = 6 * 3600
    ) -> GroupMetrics {
        let spoken = RelationshipMetrics.spokenMessages(messages)
        let sessions = RelationshipMetrics.sessions(of: spoken, gap: sessionGap)
        let speaker: (Message) -> String? = { $0.isFromMe ? nil : ($0.sender ?? "") }

        var counts: [String?: Int] = [:]
        var starts: [String?: Int] = [:]
        var responses: [String?: [TimeInterval]] = [:]
        var lastActive: [String?: Date] = [:]
        var recentCounts: [String?: Int] = [:]
        let recentCutoff = now.addingTimeInterval(-RelationshipMetrics.recentWindow)

        for session in sessions {
            if let first = session.first { starts[speaker(first), default: 0] += 1 }
            for (previous, current) in zip(session, session.dropFirst()) where speaker(previous) != speaker(current) {
                responses[speaker(current), default: []].append(current.date.timeIntervalSince(previous.date))
            }
        }
        for message in spoken {
            counts[speaker(message), default: 0] += 1
            lastActive[speaker(message)] = message.date
            if message.date >= recentCutoff { recentCounts[speaker(message), default: 0] += 1 }
        }

        var handles: [String?] = [nil] + participants.map(Optional.some)
        for handle in counts.keys where !handles.contains(handle) { handles.append(handle) }
        let recentTotal = recentCounts.values.reduce(0, +)

        let members = handles.map { handle in
            Member(
                handle: handle,
                messages: counts[handle] ?? 0,
                share: spoken.isEmpty ? 0 : Double(counts[handle] ?? 0) / Double(spoken.count),
                starts: starts[handle] ?? 0,
                startShare: sessions.isEmpty ? 0 : Double(starts[handle] ?? 0) / Double(sessions.count),
                medianResponse: RelationshipMetrics.median(responses[handle] ?? []),
                recentShare: recentTotal == 0 ? nil : Double(recentCounts[handle] ?? 0) / Double(recentTotal),
                lastActive: lastActive[handle]
            )
        }
        .enumerated()
        .sorted { $0.element.messages != $1.element.messages ? $0.element.messages > $1.element.messages : $0.offset < $1.offset }
        .map(\.element)

        return GroupMetrics(
            messageCount: spoken.count,
            conversations: sessions.count,
            members: members,
            observations: observations(members, recentTotal: recentTotal),
            weekly: RelationshipMetrics.weeklyVolume(spoken, now: now)
        )
    }

    // Thresholds keep small or quiet groups from producing noise: a carrier needs at least
    // two others to carry, and drift needs enough recent traffic to be more than chance.
    private static func observations(_ members: [Member], recentTotal: Int) -> [Observation] {
        var result: [Observation] = []
        if members.count >= 3, let top = members.first, top.share > 0.5 {
            result.append(.carries(handle: top.handle, share: top.share))
        }
        if recentTotal >= 10 {
            for member in members where member.share >= 0.15 {
                if let recent = member.recentShare, recent < member.share / 2 {
                    result.append(.drifting(handle: member.handle, usual: member.share, recent: recent))
                }
            }
        }
        return result
    }
}
