import Foundation
import Testing
@testable import IonshipCore

private let day: TimeInterval = 86_400
private let base = Date(timeIntervalSinceReferenceDate: 800_000_000)

private func m(_ id: Int64, me: Bool, at offset: TimeInterval, kind: Message.Kind = .text) -> Message {
    Message(id: id, guid: "g\(id)", chatID: 1, sender: me ? nil : "+15550001111", isFromMe: me,
            date: base.addingTimeInterval(offset), text: "x", textSource: .column, kind: kind)
}

@Suite struct RelationshipMetricsTests {
    let threeSessions = [
        m(1, me: false, at: 10 * 3600),
        m(2, me: true, at: 10 * 3600 + 300),
        m(3, me: false, at: 10 * 3600 + 360),
        m(4, me: true, at: day + 9 * 3600),
        m(5, me: false, at: day + 9 * 3600 + 1800),
        m(6, me: true, at: 2 * day + 12 * 3600),
    ]

    @Test func sessionsSplitOnLongGapsAndCountStarters() {
        let metrics = RelationshipMetrics.compute(threeSessions, now: base.addingTimeInterval(3 * day))
        #expect(metrics.conversations == 3)
        #expect(metrics.youStartShare == 2.0 / 3.0)
        #expect(metrics.messageCount == 6)
    }

    @Test func replyTimesAreMediansPerSide() {
        let metrics = RelationshipMetrics.compute(threeSessions, now: base.addingTimeInterval(3 * day))
        #expect(metrics.yourMedianReply == 300)
        #expect(metrics.theirMedianReply == 930)
    }

    @Test func reactionsAndSystemRowsAreIgnored() {
        let noisy = threeSessions + [
            m(7, me: true, at: 10 * 3600 + 30, kind: .reaction),
            m(8, me: false, at: 10 * 3600 + 40, kind: .other),
        ]
        let metrics = RelationshipMetrics.compute(noisy, now: base.addingTimeInterval(3 * day))
        #expect(metrics.yourMedianReply == 300)
        #expect(metrics.messageCount == 6)
    }

    @Test func inputOrderDoesNotMatter() {
        let metrics = RelationshipMetrics.compute(threeSessions.reversed(), now: base.addingTimeInterval(3 * day))
        #expect(metrics.conversations == 3)
        #expect(metrics.yourMedianReply == 300)
    }

    @Test func recentReplyMedianOnlyCountsLast90Days() {
        let messages = [
            m(1, me: false, at: 0), m(2, me: true, at: 600),
            m(3, me: false, at: 200 * day), m(4, me: true, at: 200 * day + 60),
        ]
        let metrics = RelationshipMetrics.compute(messages, now: base.addingTimeInterval(201 * day))
        #expect(metrics.yourMedianReply == 330)
        #expect(metrics.yourRecentMedianReply == 60)
    }

    @Test func longConversationsAndTheirUsualGap() {
        func burst(startID: Int64, at start: TimeInterval) -> [Message] {
            (0..<20).map { m(startID + Int64($0), me: $0.isMultiple(of: 2), at: start + Double($0) * 60) }
        }
        let messages = burst(startID: 100, at: 10 * day) + burst(startID: 200, at: 30 * day)
            + burst(startID: 300, at: 50 * day) + [m(400, me: true, at: 55 * day)]
        let metrics = RelationshipMetrics.compute(messages, now: base.addingTimeInterval(60 * day))
        #expect(metrics.lastLongConversation == base.addingTimeInterval(50 * day))
        #expect(metrics.usualGapBetweenLongConversations == 20 * day)
    }

    @Test func weeklyVolumeCoversLast52Weeks() {
        let now = base.addingTimeInterval(400 * day)
        let messages = [
            m(1, me: true, at: 400 * day - day),
            m(2, me: false, at: 400 * day - 8 * day),
            m(3, me: false, at: 400 * day - 8 * day + 60),
            m(4, me: true, at: 0),
        ]
        let weekly = RelationshipMetrics.compute(messages, now: now).weekly
        #expect(weekly.count == 52)
        #expect(weekly[51].mine == 1 && weekly[51].theirs == 0)
        #expect(weekly[50].mine == 0 && weekly[50].theirs == 2)
        #expect(weekly.reduce(0) { $0 + $1.mine + $1.theirs } == 3)
        #expect(weekly[51].start == now.addingTimeInterval(-7 * day))
    }

    @Test func emptyHistory() {
        let metrics = RelationshipMetrics.compute([], now: base)
        #expect(metrics.conversations == 0)
        #expect(metrics.youStartShare == nil)
        #expect(metrics.yourMedianReply == nil)
        #expect(metrics.lastLongConversation == nil)
        #expect(metrics.weekly.count == 52)
    }
}
