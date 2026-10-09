import Foundation
import Testing
@testable import OdeCore

@Suite struct LiveSyncTests {
    func message(_ id: Int64, chat: Int64) -> Message {
        Message(id: id, guid: "g\(id)", chatID: chat, sender: nil, isFromMe: true, date: .now,
                text: "x", textSource: .column, kind: .text)
    }

    func conversation(_ chatIDs: [Int64]) -> Conversation {
        Conversation(chats: chatIDs.map {
            Chat(id: $0, identifier: "c\($0)", displayName: nil, isGroup: false, participants: ["h"], messageCount: 1, lastMessageDate: nil)
        })
    }

    @Test func newMessagesAreGroupedByTheConversationTheyBelongTo() {
        let mom = conversation([1, 2])
        let maya = conversation([5])
        let routed = LiveSync.route([message(10, chat: 2), message(11, chat: 5), message(12, chat: 1), message(13, chat: 99)],
                                    to: [mom, maya])
        #expect(routed[mom.id]?.map(\.id) == [10, 12])
        #expect(routed[maya.id]?.map(\.id) == [11])
        #expect(routed.count == 2)
    }

    @Test func nothingToRoute() {
        #expect(LiveSync.route([], to: [conversation([1])]).isEmpty)
    }
}
