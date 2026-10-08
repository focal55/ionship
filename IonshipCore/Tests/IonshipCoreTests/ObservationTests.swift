import Foundation
import Testing
@testable import IonshipCore

@Suite struct ObservationTests {
    let now = Date(timeIntervalSinceReferenceDate: 800_000_000)

    func metrics(
        start: Double? = 0.5, reply: TimeInterval? = 600, recent: TimeInterval? = 600,
        lastLong: TimeInterval? = nil, usualGap: TimeInterval? = nil
    ) -> RelationshipMetrics {
        RelationshipMetrics(
            messageCount: 100, conversations: 10, youStartShare: start, yourMedianReply: reply, theirMedianReply: 60,
            yourRecentMedianReply: recent, lastLongConversation: lastLong.map { now.addingTimeInterval(-$0) },
            usualGapBetweenLongConversations: usualGap, weekly: [])
    }

    @Test func balancedRelationshipHasNothingToSay() {
        #expect(metrics().observations(now: now).isEmpty)
    }

    @Test(arguments: [(0.25, RelationshipMetrics.Observation.theyStartMost(share: 0.75)),
                      (0.85, RelationshipMetrics.Observation.youStartMost(share: 0.85))])
    func lopsidedInitiation(share: Double, expected: RelationshipMetrics.Observation) {
        #expect(metrics(start: share).observations(now: now) == [expected])
    }

    @Test func slowerReplies() {
        #expect(metrics(reply: 600, recent: 1800).observations(now: now) == [.repliesSlowing(recent: 1800, usual: 600)])
        #expect(metrics(reply: 600, recent: 800).observations(now: now).isEmpty)
    }

    @Test func overdueLongConversation() {
        let day: TimeInterval = 86_400
        #expect(metrics(lastLong: 20 * day, usualGap: 8 * day).observations(now: now) == [.overdue(since: 20 * day, usual: 8 * day)])
        #expect(metrics(lastLong: 9 * day, usualGap: 8 * day).observations(now: now).isEmpty)
    }
}
