import Foundation
import Testing
@testable import OdeCore

private let now = Date(timeIntervalSinceReferenceDate: 800_000_000)
private let day: TimeInterval = 86_400

private func o(_ id: Int64, me: Bool, _ text: String?, daysAgo: Double, kind: Message.Kind = .text) -> Message {
    Message(id: id, guid: "g\(id)", chatID: 1, sender: me ? nil : "+15550001111", isFromMe: me,
            date: now.addingTimeInterval(-daysAgo * day), text: text, textSource: .column, kind: kind)
}

@Suite struct OpenLoopCandidateTests {
    func find(_ messages: [Message], within days: Double = 60) -> [OpenLoopCandidate] {
        OpenLoopCandidate.find(in: messages, within: days * day, now: now)
    }

    @Test(arguments: [
        "I'll send you the photos tonight",
        "I’ll call you after work",
        "ok I will look into it this weekend",
        "Let me check with Sarah and get back to you",
        "I'm going to book the flights tomorrow",
        "I owe you a proper dinner",
        "I promise I'll bring it Saturday",
    ])
    func commitmentsAreCandidates(_ text: String) {
        #expect(find([o(1, me: true, text, daysAgo: 3)]).map(\.message.id) == [1])
    }

    @Test(arguments: [
        "Will you send me the photos?",
        "ok",
        "I'll be there in 5",
        "Let me know if you need anything",
        "Ill",
        "That was so fun, thanks again",
    ])
    func nonCommitmentsAreNot(_ text: String) {
        #expect(find([o(1, me: true, text, daysAgo: 3)]).isEmpty)
    }

    @Test func onlyYourOwnRecentMessagesCount() {
        let messages = [
            o(1, me: false, "I'll send you the photos tonight", daysAgo: 3),
            o(2, me: true, "I'll send you the photos tonight", daysAgo: 90),
            o(3, me: true, "I'll send you the photos tonight", daysAgo: 1, kind: .reaction),
        ]
        #expect(find(messages).isEmpty)
    }

    @Test func contextIsWhatFollowedWithinAWeekCappedAtTwelve() {
        let promise = o(1, me: true, "I'll send you the photos tonight", daysAgo: 20)
        let soon = (0..<15).map { o(Int64(10 + $0), me: $0.isMultiple(of: 2), "msg \($0)", daysAgo: 19) }
        let later = o(99, me: true, "here they are", daysAgo: 5)
        let candidate = find([promise] + soon + [later]).first
        #expect(candidate?.following.count == 12)
        #expect(candidate?.following.contains { $0.id == 99 } == false)
        #expect(candidate?.following.first?.id == 10)
    }

    @Test func newestFirst() {
        let messages = [
            o(1, me: true, "I'll send you the photos tonight", daysAgo: 10),
            o(2, me: true, "Let me check my calendar and get back to you", daysAgo: 2),
        ]
        #expect(find(messages).map(\.message.id) == [2, 1])
    }
}
