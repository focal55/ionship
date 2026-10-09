import Foundation
import SQLite3
import Testing
@testable import IonshipCore

@Suite struct MessagesStoreTests {
    let fixture: Fixture
    let store: MessagesStore

    init() throws {
        fixture = try Fixture()
        store = try MessagesStore(path: fixture.path)
    }

    @Test func chatsAreSortedByMostRecentActivity() throws {
        let chats = try store.chats()
        #expect(chats.map(\.id) == [2, 1])
    }

    @Test func oneToOneChat() throws {
        let chat = try #require(try store.chats().first { $0.id == 1 })
        #expect(chat.identifier == "+15551234567")
        #expect(chat.displayName == nil)
        #expect(!chat.isGroup)
        #expect(chat.participants == ["+15551234567"])
        #expect(chat.messageCount == 5)
        #expect(chat.lastMessageDate == Date(timeIntervalSinceReferenceDate: 5000))
    }

    @Test func groupChat() throws {
        let chat = try #require(try store.chats().first { $0.id == 2 })
        #expect(chat.displayName == "Fam")
        #expect(chat.isGroup)
        #expect(chat.participants == ["+15559876543", "alice@example.com"])
        #expect(chat.messageCount == 4)
    }

    @Test func messagesAreChronologicalWithSenders() throws {
        let messages = try store.messages(chatID: 1)
        #expect(messages.map(\.id) == [1, 2, 3, 4, 5])
        #expect(messages[0].sender == "+15551234567")
        #expect(!messages[0].isFromMe)
        #expect(messages[1].sender == nil)
        #expect(messages[1].isFromMe)
        #expect(messages.allSatisfy { $0.chatID == 1 })
    }

    @Test func textComesFromColumnOrAttributedBody() throws {
        let messages = try store.messages(chatID: 1)
        #expect(messages[0].text == "hello")
        #expect(messages[0].textSource == .column)
        #expect(messages[1].text == "short body")
        #expect(messages[1].textSource == .attributedBody(.unarchiver))
        #expect(messages[2].text == longBody)
    }

    @Test func undecodableBodyIsReportedNotThrown() throws {
        let message = try #require(try store.messages(chatID: 2).first { $0.id == 8 })
        #expect(message.text == nil)
        #expect(message.textSource == .undecodable)
    }

    @Test func kinds() throws {
        let byID = Dictionary(uniqueKeysWithValues: try (store.messages(chatID: 1) + store.messages(chatID: 2)).map { ($0.id, $0) })
        #expect(byID[1]?.kind == .text)
        #expect(byID[4]?.kind == .reaction)
        #expect(byID[5]?.kind == .attachmentOnly)
        #expect(byID[5]?.text == nil)
        #expect(byID[8]?.kind == .other)
        #expect(byID[9]?.kind == .other)
    }

    @Test func nanosecondAndSecondDatesBothConvert() throws {
        let messages = try store.messages(chatID: 1)
        #expect(messages[0].date == Date(timeIntervalSinceReferenceDate: 1000))
        #expect(messages[2].date == Date(timeIntervalSinceReferenceDate: 3000))
    }

    @Test func pagingReturnsMostRecentBeforeCursor() throws {
        #expect(try store.messages(chatID: 1, limit: 2).map(\.id) == [4, 5])
        #expect(try store.messages(chatID: 1, limit: 2, before: 4).map(\.id) == [2, 3])
    }

    @Test func newMessagesAfterRowID() throws {
        #expect(try store.newMessages(after: 7).map(\.id) == [8, 9])
        try fixture.insertMessage(rowID: 10, chatID: 1, text: "live", handleID: 1, date: ns(10_000))
        let fresh = try store.newMessages(after: 9)
        #expect(fresh.map(\.id) == [10])
        #expect(fresh.first?.text == "live")
    }

    @Test func connectionIsReadOnly() throws {
        #expect(throws: MessagesStoreError.self) {
            try store.execute("DELETE FROM message")
        }
        #expect(try store.messages(chatID: 1).count == 5)
    }

    @Test func schemaReportOnCompleteSchema() throws {
        let report = try store.schemaReport()
        #expect(report.missing.isEmpty)
        #expect(report.isUsable)
    }

    @Test func schemaReportFlagsMissingColumns() throws {
        let stripped = Fixture.schema.replacingOccurrences(of: "attributedBody BLOB, ", with: "")
        let fixture = try Fixture(schema: stripped, seed: false)
        let report = try MessagesStore(path: fixture.path).schemaReport()
        #expect(report.missing == ["message.attributedBody"])
        #expect(!report.isUsable)
    }

    @Test func missingFileIsCannotOpenNotAccessDenied() {
        #expect(throws: MessagesStoreError.cannotOpen(path: "/nonexistent/chat.db", reason: "unable to open database file")) {
            try MessagesStore(path: "/nonexistent/chat.db")
        }
    }

    @Test(arguments: [
        (SQLITE_AUTH, "not authorized"),
        (SQLITE_CANTOPEN, "authorization denied"),
        (SQLITE_PERM, "access permission denied"),
    ])
    func accessDeniedIsRecognized(code: Int32, message: String) {
        #expect(MessagesStoreError.classifyOpenFailure(path: "p", code: code, message: message) == .accessDenied(path: "p"))
    }

    @Test func latestRowIDTracksNewMessages() throws {
        #expect(try store.latestRowID() == 9)
        try fixture.insertMessage(rowID: 10, chatID: 1, text: "new", handleID: 1, date: ns(10_000))
        #expect(try store.latestRowID() == 10)
    }

    @Test func latestRowIDOfEmptyDatabaseIsZero() throws {
        let empty = try Fixture(seed: false)
        #expect(try MessagesStore(path: empty.path).latestRowID() == 0)
    }

    @Test func chatsCarryServiceAndFirstMessageDate() throws {
        let chats = try store.chats()
        let one = try #require(chats.first { $0.id == 1 })
        #expect(one.service == "iMessage")
        let group = try #require(chats.first { $0.id == 2 })
        #expect(group.service == "SMS")
        #expect(group.firstMessageDate == Date(timeIntervalSinceReferenceDate: 6000))
    }

    @Test func olderDatabasesWithoutServiceStillLoad() throws {
        let stripped = Fixture.schema.replacingOccurrences(of: ", service_name TEXT", with: "")
        let fixture = try Fixture(schema: stripped, seed: false)
        try fixture.exec("INSERT INTO chat (ROWID, guid, chat_identifier, display_name, style) VALUES (1, 'g', 'x', '', 45)")
        #expect(try MessagesStore(path: fixture.path).chats().first?.service == nil)
    }
}
