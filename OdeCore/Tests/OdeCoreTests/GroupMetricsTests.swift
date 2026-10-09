import Foundation
import Testing
@testable import OdeCore

private let base = Date(timeIntervalSinceReferenceDate: 800_000_000)
private let hour: TimeInterval = 3600
private let day: TimeInterval = 86_400

private func g(_ id: Int64, _ sender: String?, at offset: TimeInterval, kind: Message.Kind = .text) -> Message {
    Message(id: id, guid: "g\(id)", chatID: 9, sender: sender, isFromMe: sender == nil,
            date: base.addingTimeInterval(offset), text: "x", textSource: .column, kind: kind)
}

@Suite struct GroupMetricsTests {
    let messages = [
        g(1, "A", at: 0), g(2, "B", at: 60), g(3, nil, at: 120), g(4, "A", at: 180),
        g(5, nil, at: 8 * hour), g(6, "B", at: 8 * hour + 300),
        g(7, "B", at: 20 * hour),
        g(8, "A", at: 20 * hour + 10, kind: .reaction),
    ]

    var metrics: GroupMetrics {
        GroupMetrics.compute(messages, participants: ["A", "B", "C"], now: base.addingTimeInterval(day))
    }

    func member(_ handle: String?) -> GroupMetrics.Member? {
        metrics.members.first { $0.handle == handle }
    }

    @Test func totals() {
        #expect(metrics.messageCount == 7)
        #expect(metrics.conversations == 3)
        #expect(metrics.members.count == 4)
    }

    @Test func membersAreOrderedByMessagesWithSilentMembersLast() {
        #expect(metrics.members.first?.handle == "B")
        #expect(metrics.members.last?.handle == "C")
        #expect(member("C")?.messages == 0)
        #expect(member("C")?.lastActive == nil)
    }

    @Test func shareOfMessagesAndStarts() {
        #expect(member("B")?.messages == 3)
        #expect(member("B")?.share == 3.0 / 7.0)
        #expect(member("A")?.starts == 1)
        #expect(member(nil)?.starts == 1)
        #expect(member("B")?.starts == 1)
        #expect(member("A")?.startShare == 1.0 / 3.0)
    }

    @Test func responseTimeIsDelayAfterSomeoneElseSpoke() {
        #expect(member("B")?.medianResponse == 180)
        #expect(member(nil)?.medianResponse == 60)
        #expect(member("A")?.medianResponse == 60)
        #expect(member("C")?.medianResponse == nil)
    }

    @Test func lastActive() {
        #expect(member("B")?.lastActive == base.addingTimeInterval(20 * hour))
        #expect(member("A")?.lastActive == base.addingTimeInterval(180))
    }

    @Test func someoneCarryingTheGroup() {
        let senders: [String?] = Array(repeating: "A", count: 9) + ["B", nil, nil]
        let chatty = senders.enumerated().map { g(Int64($0.offset), $0.element, at: Double($0.offset) * 60) }
        let metrics = GroupMetrics.compute(chatty, participants: ["A", "B"], now: base.addingTimeInterval(day))
        let expected: [GroupMetrics.Observation] = [.carries(handle: "A", share: 0.75)]
        #expect(metrics.observations == expected)
    }

    @Test func driftingMemberLostMostOfTheirShareRecently() {
        let early = (0..<20).map { g(Int64($0), $0.isMultiple(of: 2) ? "A" : "B", at: Double($0) * 60) }
        let recent = (0..<20).map { g(Int64(100 + $0), $0.isMultiple(of: 2) ? "B" : nil, at: 300 * day + Double($0) * 60) }
        let stillAround = g(200, "A", at: 300 * day + 30 * 60)
        let metrics = GroupMetrics.compute(early + recent + [stillAround], participants: ["A", "B"], now: base.addingTimeInterval(301 * day))
        #expect(metrics.observations.contains(.drifting(handle: "A", usual: 11.0 / 41.0, recent: 1.0 / 21.0)))
        #expect(!metrics.observations.contains(.goneQuiet(handle: "A", days: 301)))
    }

    @Test func weeklyVolumeIsIncluded() {
        #expect(metrics.weekly.count == 52)
        #expect(metrics.weekly.reduce(0) { $0 + $1.mine + $1.theirs } == 7)
    }

    @Test func regularWhoWentSilentWhileTheGroupKeptTalking() {
        let rotation: [String?] = ["A", "B", nil]
        let early = (0..<30).map { g(Int64($0), rotation[$0 % 3], at: Double($0) * 60) }
        let lately = (0..<10).map { g(Int64(100 + $0), $0.isMultiple(of: 2) ? "B" : nil, at: 50 * day + Double($0) * 60) }
        let metrics = GroupMetrics.compute(early + lately, participants: ["A", "B"], now: base.addingTimeInterval(52 * day))
        #expect(metrics.observations.contains(.goneQuiet(handle: "A", days: 52)))
    }

    @Test func quietGroupsDoNotFlagQuietMembers() {
        let rotation: [String?] = ["A", "B", nil]
        let early = (0..<30).map { g(Int64($0), rotation[$0 % 3], at: Double($0) * 60) }
        let metrics = GroupMetrics.compute(early, participants: ["A", "B"], now: base.addingTimeInterval(52 * day))
        #expect(!metrics.observations.contains { if case .goneQuiet = $0 { true } else { false } })
    }
}
