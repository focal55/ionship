import Foundation
import Testing
@testable import OdeCore

private let now = Date(timeIntervalSinceReferenceDate: 800_000_000)
private let hour: TimeInterval = 3_600
private let day: TimeInterval = 86_400

private func w(_ id: Int64, me: Bool, _ text: String?, hoursAgo: Double, kind: Message.Kind = .text) -> Message {
    Message(id: id, guid: "g\(id)", chatID: 7, sender: me ? nil : "+15550001111", isFromMe: me,
            date: now.addingTimeInterval(-hoursAgo * hour), text: text, textSource: .column, kind: kind)
}

private func conversation(group: Bool = false) -> Conversation {
    Conversation(chats: [Chat(id: 7, identifier: "x", displayName: nil, isGroup: group,
                              participants: group ? ["+15550001111", "+15550002222"] : ["+15550001111"],
                              messageCount: 0, lastMessageDate: nil)])
}

@Suite struct UnansweredTests {
    func find(_ messages: [Message], group: Bool = false) -> Waiting? {
        Waiting.unanswered(in: conversation(group: group), messages: messages, now: now)
    }

    @Test func theirMessageAfterYoursIsWaiting() {
        let item = find([w(1, me: true, "how was the trip", hoursAgo: 30), w(2, me: false, "amazing, sending pics soon", hoursAgo: 5)])
        #expect(item?.kind == .unanswered)
        #expect(item?.text == "amazing, sending pics soon")
        #expect(item?.steer == "reply to their last message")
        #expect(item?.since == now.addingTimeInterval(-5 * hour))
        #expect(item?.newestMessageID == 2)
        #expect(item?.conversationID == 7)
    }

    @Test func aQuestionIsAsked() {
        let item = find([w(1, me: true, "hey", hoursAgo: 30), w(2, me: false, "are you free Saturday?", hoursAgo: 4)])
        #expect(item?.kind == .asked)
        #expect(item?.steer == "answer their question")
    }

    @Test func yourReplyClearsIt() {
        #expect(find([w(1, me: false, "are you free Saturday?", hoursAgo: 6), w(2, me: true, "yes!", hoursAgo: 5)]) == nil)
    }

    @Test func yourReactionClearsIt() {
        #expect(find([w(1, me: false, "landed safe", hoursAgo: 6),
                      w(2, me: true, "Loved “landed safe”", hoursAgo: 5, kind: .reaction)]) == nil)
    }

    @Test func theirReactionIsNotAMessage() {
        #expect(find([w(1, me: true, "see you then", hoursAgo: 6),
                      w(2, me: false, "Liked “see you then”", hoursAgo: 5, kind: .reaction)]) == nil)
    }

    @Test func tooRecentIsNotWaitingYet() {
        #expect(find([w(1, me: false, "are you free Saturday?", hoursAgo: 0.5)]) == nil)
    }

    @Test func olderThanThreeWeeksIsLeftToGoneQuiet() {
        #expect(find([w(1, me: false, "are you free Saturday?", hoursAgo: 22 * 24)]) == nil)
    }

    @Test func windowEdgesAreIncluded() {
        #expect(find([w(1, me: false, "call me", hoursAgo: 1)]) != nil)
        #expect(find([w(1, me: false, "call me", hoursAgo: 21 * 24)]) != nil)
    }

    @Test func windowUsesTheirLatestMessage() {
        #expect(find([w(1, me: false, "dinner friday?", hoursAgo: 30), w(2, me: false, "also call me", hoursAgo: 0.2)]) == nil)
    }

    @Test(arguments: ["ok", "Okay.", "thanks!!", "Thank you 🙏", "lol 😂", "sounds good", "Got it", "👍", "❤️", "kk", "you too!"])
    func closersAreNotWaiting(_ text: String) {
        #expect(find([w(1, me: true, "see you at 7", hoursAgo: 6), w(2, me: false, text, hoursAgo: 5)]) == nil)
    }

    @Test(arguments: ["ok?", "ok but when", "thanks for the help, how much do I owe you", "lol what"])
    func nearClosersStillCount(_ text: String) {
        #expect(find([w(1, me: true, "see you at 7", hoursAgo: 6), w(2, me: false, text, hoursAgo: 5)]) != nil)
    }

    @Test func aLaterCloserDoesNotHideAnEarlierQuestion() {
        let item = find([w(1, me: true, "hey", hoursAgo: 30), w(2, me: false, "can you send the address?", hoursAgo: 8),
                         w(3, me: false, "lol", hoursAgo: 7)])
        #expect(item?.kind == .asked)
        #expect(item?.text == "can you send the address?")
        #expect(item?.since == now.addingTimeInterval(-8 * hour))
        #expect(item?.newestMessageID == 3)
    }

    @Test func onlyClosersMeansNothingIsWaiting() {
        #expect(find([w(1, me: true, "done", hoursAgo: 9), w(2, me: false, "thanks", hoursAgo: 8),
                      w(3, me: false, "👍", hoursAgo: 7)]) == nil)
    }

    @Test func neverRepliedStillCounts() {
        #expect(find([w(1, me: false, "hi it's Sam from the climbing gym", hoursAgo: 3)])?.kind == .unanswered)
    }

    @Test func attachmentsAndUndecodedTextGetALabel() {
        #expect(find([w(1, me: false, nil, hoursAgo: 3, kind: .attachmentOnly)])?.text == "Attachment")
        #expect(find([w(1, me: false, nil, hoursAgo: 3)])?.text == "Message")
    }

    @Test func groupsAreLeftOut() {
        #expect(find([w(1, me: false, "anyone free Saturday?", hoursAgo: 3)], group: true) == nil)
    }

    @Test func emptyThreadIsNothing() {
        #expect(find([]) == nil)
    }
}
