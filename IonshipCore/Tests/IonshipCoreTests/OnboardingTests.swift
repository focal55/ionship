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

    @Test func restoringASavedSelectionDropsChatsThatNoLongerExist() {
        var picker = ConversationPicker(chats: [chat(1, 100), chat(2, 50), chat(3, 0)])
        picker.restore(selection: [2, 3, 99])
        #expect(picker.selected == [2])
    }

    @Test func titlePrefersDisplayNameThenSingleParticipant() {
        let picker = ConversationPicker(chats: [])
        #expect(picker.title(for: chat(1, 1, name: "Fam", participants: ["x", "y"])) == "Fam")
        #expect(picker.title(for: chat(2, 1, identifier: "id", participants: ["maya@example.com"])) == "maya@example.com")
        #expect(picker.title(for: chat(3, 1, identifier: "chat9", participants: ["a", "b", "c"])) == "a, b +1")
    }

    @Test func titlesUseContactNames() {
        var picker = ConversationPicker(chats: [])
        picker.names = HandleDirectory(entries: [
            .init(name: "Mom", phones: ["5550104471"], emails: []),
            .init(name: "Dad", phones: ["5550100002"], emails: []),
        ])
        #expect(picker.title(for: chat(1, 1, identifier: "+15550104471", participants: ["+15550104471"])) == "Mom")
        #expect(picker.title(for: chat(2, 1, participants: ["+15550104471", "+15550100002", "+15559990000"])) == "Mom, Dad +1")
        #expect(picker.title(for: chat(3, 1, name: "Fam", participants: ["+15550104471", "+15550100002"])) == "Fam")
    }

    @Test func filterMatchesContactNames() {
        var picker = ConversationPicker(chats: [
            chat(1, 5, identifier: "+15550104471", participants: ["+15550104471"]),
            chat(2, 5, identifier: "+15550100002", participants: ["+15550100002"]),
        ])
        picker.names = HandleDirectory(entries: [.init(name: "Mom", phones: ["5550104471"], emails: [])])
        picker.filter = "mom"
        #expect(picker.visible.map(\.id) == [1])
    }

    @Test func mergesOneToOneChatsForTheSameContact() {
        var picker = ConversationPicker(chats: [
            chat(1, 100, identifier: "+15550104471", participants: ["+15550104471"]),
            chat(2, 50, identifier: "mom@example.com", participants: ["mom@example.com"]),
            chat(3, 30, identifier: "+15550100002", participants: ["+15550100002"]),
            chat(4, 20, identifier: "chat9", participants: ["+15550104471", "+15550100002"]),
        ], preselect: 1)
        picker.names = HandleDirectory(entries: [
            .init(name: "Mom", phones: ["5550104471"], emails: ["mom@example.com"]),
        ])
        #expect(picker.visible.map(\.id) == [1, 3, 4])
        let mom = picker.visible[0]
        #expect(mom.chatIDs == [1, 2])
        #expect(mom.messageCount == 150)
        #expect(picker.title(for: mom) == "Mom")
        #expect(picker.isSelected(mom))
        #expect(picker.selectedMessageCount == 150)
    }

    @Test func togglingAMergedConversationCoversAllItsChats() {
        var picker = ConversationPicker(chats: [
            chat(1, 100, identifier: "+15550104471", participants: ["+15550104471"]),
            chat(2, 50, identifier: "mom@example.com", participants: ["mom@example.com"]),
        ], preselect: 0)
        picker.names = HandleDirectory(entries: [.init(name: "Mom", phones: ["5550104471"], emails: ["mom@example.com"])])
        picker.toggle(1)
        #expect(picker.selected == [1, 2])
        #expect(picker.selectedConversations.map(\.chatIDs) == [[1, 2]])
        picker.toggle(1)
        #expect(picker.selected.isEmpty)
    }

    @Test func differentContactsWithTheSameNameStaySeparate() {
        var picker = ConversationPicker(chats: [
            chat(1, 10, identifier: "+15550000001", participants: ["+15550000001"]),
            chat(2, 5, identifier: "+15550000002", participants: ["+15550000002"]),
            chat(3, 3, identifier: "+15559999999", participants: ["+15559999999"]),
            chat(4, 2, identifier: "+15558888888", participants: ["+15558888888"]),
        ])
        picker.names = HandleDirectory(entries: [
            .init(name: "Sam", phones: ["5550000001"], emails: []),
            .init(name: "Sam", phones: ["5550000002"], emails: []),
        ])
        #expect(picker.visible.map(\.id) == [1, 2, 3, 4])
    }
}
