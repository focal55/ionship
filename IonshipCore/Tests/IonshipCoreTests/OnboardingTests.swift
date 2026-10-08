import Foundation
import Testing
@testable import IonshipCore

@Suite struct MessagesAccessTests {
    @Test func readableDatabaseIsGranted() throws {
        let fixture = try Fixture()
        #expect(MessagesAccess.check(path: fixture.path) == .granted)
    }

    @Test func missingDatabaseIsUnavailableNotDenied() {
        #expect(MessagesAccess.check(path: "/nonexistent/chat.db") == .unavailable)
    }
}

@Suite struct ConversationPickerTests {
    func chat(_ id: Int64, _ count: Int, name: String? = nil, identifier: String = "", participants: [String] = []) -> Chat {
        Chat(id: id, identifier: identifier, displayName: name, isGroup: participants.count > 1,
             participants: participants, messageCount: count, lastMessageDate: nil)
    }

    @Test func ordersByMessageCountDescending() {
        let picker = ConversationPicker(chats: [chat(1, 10), chat(2, 300), chat(3, 40)])
        #expect(picker.visible.map(\.id) == [2, 3, 1])
    }

    @Test func emptyChatsAreHidden() {
        let picker = ConversationPicker(chats: [chat(1, 0), chat(2, 5)])
        #expect(picker.visible.map(\.id) == [2])
    }

    @Test func preselectsTheBusiestConversations() {
        let chats = (1...15).map { chat(Int64($0), $0 * 10) }
        let picker = ConversationPicker(chats: chats, preselect: 10)
        #expect(picker.selected == Set((6...15).map(Int64.init)))
    }

    @Test func filterMatchesNameIdentifierAndParticipantsCaseInsensitively() {
        var picker = ConversationPicker(chats: [
            chat(1, 5, name: "Ybarra Family", participants: ["+15550001111", "a@b.com"]),
            chat(2, 5, identifier: "maya@example.com", participants: ["maya@example.com"]),
            chat(3, 5, identifier: "+15559990000", participants: ["+15559990000"]),
        ])
        picker.filter = "family"
        #expect(picker.visible.map(\.id) == [1])
        picker.filter = "MAYA"
        #expect(picker.visible.map(\.id) == [2])
        picker.filter = "9990"
        #expect(picker.visible.map(\.id) == [3])
        picker.filter = "  "
        #expect(picker.visible.count == 3)
    }

    @Test func toggleAndTotals() {
        var picker = ConversationPicker(chats: [chat(1, 100), chat(2, 50), chat(3, 7)], preselect: 1)
        #expect(picker.selectedMessageCount == 100)
        picker.toggle(3)
        #expect(picker.selected == [1, 3])
        #expect(picker.selectedMessageCount == 107)
        picker.toggle(1)
        #expect(picker.selected == [3])
    }

    @Test func titlePrefersDisplayNameThenSingleParticipant() {
        #expect(ConversationPicker.title(for: chat(1, 1, name: "Fam", participants: ["x", "y"])) == "Fam")
        #expect(ConversationPicker.title(for: chat(2, 1, identifier: "id", participants: ["maya@example.com"])) == "maya@example.com")
        #expect(ConversationPicker.title(for: chat(3, 1, identifier: "chat9", participants: ["a", "b", "c"])) == "a, b +1")
    }
}
