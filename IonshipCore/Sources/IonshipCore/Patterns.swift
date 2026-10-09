import Foundation

/// Facts about a relationship computed from timestamps, phrased for people. Each pattern
/// needs enough history to be more than coincidence, so a sparse thread yields none.
public enum Patterns {
    public struct Pattern: Sendable, Equatable, Identifiable {
        public enum Kind: Sendable { case longTalkDay, replySpeed, initiationShift, timeOfDay }
        public let kind: Kind
        public let title: String
        public let detail: String
        /// First message of each conversation that shows the pattern, oldest first.
        public let momentIDs: [Int64]
        public var id: String { title }
    }

    public static func find(in messages: [Message], calendar: Calendar = .current, now: Date = .now) -> [Pattern] {
        let sessions = RelationshipMetrics.sessions(of: RelationshipMetrics.spokenMessages(messages), gap: 6 * 3600)
        return [longTalkDay(sessions, calendar), replySpeed(sessions), initiationShift(sessions, now), timeOfDay(sessions, calendar)]
            .compactMap { $0 }
    }

    private static func longTalkDay(_ sessions: [[Message]], _ calendar: Calendar) -> Pattern? {
        let long = sessions.filter { $0.count >= 20 }
        guard long.count >= 5 else { return nil }
        let byDay = Dictionary(grouping: long) { calendar.component(.weekday, from: $0[0].date) }
        guard let (weekday, matching) = byDay.max(by: { $0.value.count < $1.value.count }) else { return nil }
        let share = Double(matching.count) / Double(long.count)
        guard share >= 0.4 else { return nil }
        let name = weekdayName(weekday)
        return Pattern(kind: .longTalkDay, title: "\(name) is when real conversations happen",
                       detail: "\(percent(share)) of your conversations longer than 20 messages start on a \(name).",
                       momentIDs: matching.map { $0[0].id })
    }

    private static func replySpeed(_ sessions: [[Message]]) -> Pattern? {
        var quick: [[Message]] = [], slow: [[Message]] = []
        for session in sessions {
            let delays = zip(session, session.dropFirst()).compactMap { previous, current in
                !previous.isFromMe && current.isFromMe ? current.date.timeIntervalSince(previous.date) : nil
            }
            guard let median = RelationshipMetrics.median(delays) else { continue }
            if median < 3600 { quick.append(session) } else { slow.append(session) }
        }
        guard quick.count >= 3, slow.count >= 3 else { return nil }
        let ratio = average(quick.map(\.count)) / average(slow.map(\.count))
        guard ratio >= 1.5 else { return nil }
        return Pattern(kind: .replySpeed, title: "Quick replies keep you talking",
                       detail: "When you reply within an hour, conversations run \(Int(ratio.rounded()))× longer.",
                       momentIDs: quick.map { $0[0].id })
    }

    private static func initiationShift(_ sessions: [[Message]], _ now: Date) -> Pattern? {
        let yearAgo = now.addingTimeInterval(-365 * 86_400)
        let recent = sessions.filter { $0[0].date >= yearAgo }
        let earlier = sessions.filter { $0[0].date < yearAgo }
        guard recent.count >= 10, earlier.count >= 10 else { return nil }
        let theyRecent = Double(recent.filter { !$0[0].isFromMe }.count) / Double(recent.count)
        let theyEarlier = Double(earlier.filter { !$0[0].isFromMe }.count) / Double(earlier.count)
        let shift = theyRecent - theyEarlier
        guard abs(shift) >= 0.15 else { return nil }
        return shift > 0
            ? Pattern(kind: .initiationShift, title: "They start more than they used to",
                      detail: "They started \(percent(theyRecent)) of conversations this past year, up from \(percent(theyEarlier)).",
                      momentIDs: recent.filter { !$0[0].isFromMe }.map { $0[0].id })
            : Pattern(kind: .initiationShift, title: "You start more than you used to",
                      detail: "You started \(percent(1 - theyRecent)) of conversations this past year, up from \(percent(1 - theyEarlier)).",
                      momentIDs: recent.filter { $0[0].isFromMe }.map { $0[0].id })
    }

    private static func timeOfDay(_ sessions: [[Message]], _ calendar: Calendar) -> Pattern? {
        let messages = sessions.flatMap { $0 }
        guard messages.count >= 30 else { return nil }
        func bucket(_ date: Date) -> String {
            switch calendar.component(.hour, from: date) {
            case 5..<12: "morning"
            case 12..<17: "afternoon"
            case 17..<22: "evening"
            default: "late-night"
            }
        }
        let counts = Dictionary(grouping: messages, by: { bucket($0.date) })
        guard let (name, matching) = counts.max(by: { $0.value.count < $1.value.count }) else { return nil }
        let share = Double(matching.count) / Double(messages.count)
        guard share >= 0.5 else { return nil }
        let starts = sessions.filter { bucket($0[0].date) == name }.map { $0[0].id }
        return Pattern(kind: .timeOfDay, title: "Mostly \(name) conversations",
                       detail: "\(percent(share)) of your messages with them are sent in the \(name == "late-night" ? "late night" : name).",
                       momentIDs: starts)
    }

    private static func weekdayName(_ weekday: Int) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "en_US")
        return calendar.weekdaySymbols[weekday - 1]
    }

    private static func percent(_ value: Double) -> String { "\(Int((value * 100).rounded()))%" }

    private static func average(_ values: [Int]) -> Double { Double(values.reduce(0, +)) / Double(max(values.count, 1)) }
}
