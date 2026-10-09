import Foundation

/// How warm a relationship feels right now, and which way it is moving: the last four weeks
/// against the twenty before them. Volume sets the level; volume, reply length and reply
/// speed set the trend.
public struct Temperature: Sendable, Equatable {
    public enum Level: String, Sendable { case warm, mild, cool, quiet }
    public enum Trend: String, Sendable { case warming, cooling, steady }

    public let level: Level
    public let trend: Trend
    public let reason: String
    /// Messages per week for the last twelve weeks, oldest first.
    public let sparkline: [Double]

    public var label: String {
        level == .quiet ? "Quiet" : "\(level.rawValue), \(trend.rawValue)".capitalizedFirst
    }

    public init(of messages: [Message], now: Date = .now) {
        let week: TimeInterval = 7 * 86_400
        let spoken = RelationshipMetrics.spokenMessages(messages)
        let recentStart = now.addingTimeInterval(-4 * week)
        let baselineStart = now.addingTimeInterval(-24 * week)
        let recent = spoken.filter { $0.date >= recentStart && $0.date <= now }
        let baseline = spoken.filter { $0.date >= baselineStart && $0.date < recentStart }

        sparkline = (0..<12).map { index in
            let start = now.addingTimeInterval(-Double(12 - index) * week)
            return Double(spoken.filter { $0.date >= start && $0.date < start.addingTimeInterval(week) }.count)
        }

        let recentPerWeek = Double(recent.count) / 4
        level = recent.isEmpty ? .quiet : recentPerWeek >= 6 ? .warm : recentPerWeek >= 2 ? .mild : .cool

        guard !baseline.isEmpty, !recent.isEmpty else {
            trend = .steady
            reason = recent.isEmpty ? "No messages in the last four weeks." : "Not enough history to compare yet."
            return
        }
        let volume = recentPerWeek / (Double(baseline.count) / 20)
        let length = Self.ratio(Self.myLengths(recent), Self.myLengths(baseline))
        let latency = Self.ratio(Self.myReplyDelays(recent), Self.myReplyDelays(baseline))
        let shorter = length.map { $0 < 0.7 } ?? false
        let slower = latency.map { $0 > 1.5 } ?? false

        if volume < 0.6 || (shorter && slower) {
            trend = .cooling
        } else if volume > 1.6 {
            trend = .warming
        } else {
            trend = .steady
        }
        reason = switch (shorter, slower) {
        case (true, true): "Your replies are shorter and slower than usual lately."
        case (false, true): "Your replies are slower than usual lately."
        case (true, false): "Your replies are shorter than usual lately."
        default:
            volume < 0.6 ? "You’re talking less than usual lately."
                : volume > 1.6 ? "You’re talking more than usual lately." : "Steady compared with the past few months."
        }
    }

    private static func myLengths(_ messages: [Message]) -> [Double] {
        messages.filter { $0.isFromMe }.compactMap { $0.text.map { Double($0.count) } }
    }

    private static func myReplyDelays(_ messages: [Message]) -> [Double] {
        zip(messages, messages.dropFirst()).compactMap { previous, current in
            !previous.isFromMe && current.isFromMe ? current.date.timeIntervalSince(previous.date) : nil
        }
    }

    private static func ratio(_ recent: [Double], _ baseline: [Double]) -> Double? {
        guard let a = RelationshipMetrics.median(recent), let b = RelationshipMetrics.median(baseline), b > 0 else { return nil }
        return a / b
    }
}

extension String {
    var capitalizedFirst: String { prefix(1).uppercased() + dropFirst() }
}
