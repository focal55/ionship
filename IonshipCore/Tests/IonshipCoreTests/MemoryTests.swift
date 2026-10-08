import Foundation
import Testing
@testable import IonshipCore

private let base = Date(timeIntervalSinceReferenceDate: 800_000_000)
private let hour: TimeInterval = 3600

private func mm(_ id: Int64, me: Bool, _ text: String?, at offset: TimeInterval, chat: Int64 = 1) -> Message {
    Message(id: id, guid: "g\(id)", chatID: chat, sender: me ? nil : "+15550001111", isFromMe: me,
            date: base.addingTimeInterval(offset), text: text, textSource: .column, kind: .text)
}

/// Deterministic stand-in for a real model: one dimension per known word.
struct WordEmbedder: Embedder {
    static let vocabulary = ["photos", "pictures", "trip", "dinner", "sunday", "knee", "doctor", "climbing"]
    func vector(for text: String) -> [Float]? {
        let lowered = text.lowercased()
        let vector = Self.vocabulary.map { lowered.contains($0) ? Float(1) : 0 }
        return vector.contains(where: { $0 > 0 }) ? vector : nil
    }
}

@Suite struct MomentTests {
    let name: (String?) -> String = { $0 == nil ? "You" : "Maya" }

    @Test func sessionsBecomeMomentsWithSpeakerLines() {
        let messages = [mm(1, me: false, "hey", at: 0), mm(2, me: true, "hi!", at: 60), mm(3, me: false, "dinner?", at: 10 * hour)]
        let moments = Moment.split(messages, conversationID: 7, name: name, closedBefore: base.addingTimeInterval(100 * hour))
        #expect(moments.map(\.firstMessageID) == [1, 3])
        #expect(moments[0].text == "Maya: hey\nYou: hi!")
        #expect(moments[0].lastMessageID == 2)
        #expect(moments[0].conversationID == 7)
    }

    @Test func longSessionsAreSplitIntoWindows() {
        let messages = (0..<20).map { mm(Int64($0), me: $0.isMultiple(of: 2), "m\($0)", at: Double($0) * 60) }
        let moments = Moment.split(messages, conversationID: 1, name: name, closedBefore: base.addingTimeInterval(100 * hour), window: 8)
        #expect(moments.map(\.firstMessageID) == [0, 8, 16])
    }

    @Test func theSessionStillInProgressIsLeftForLater() {
        let messages = [mm(1, me: false, "old", at: 0), mm(2, me: true, "now", at: 20 * hour)]
        let moments = Moment.split(messages, conversationID: 1, name: name, closedBefore: base.addingTimeInterval(22 * hour))
        #expect(moments.map(\.firstMessageID) == [1])
    }

    @Test func attachmentOnlyMessagesAreSkippedAndEmptyMomentsDropped() {
        let messages = [mm(1, me: false, nil, at: 0), mm(2, me: true, "look", at: 30)]
        let moments = Moment.split(messages, conversationID: 1, name: name, closedBefore: base.addingTimeInterval(100 * hour))
        #expect(moments.first?.text == "You: look")
        #expect(Moment.split([mm(1, me: false, nil, at: 0)], conversationID: 1, name: name,
                             closedBefore: base.addingTimeInterval(100 * hour)).isEmpty)
    }
}

@Suite struct MemoryIndexTests {
    let index: MemoryIndex
    let directory: URL

    init() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("memory-\(UUID().uuidString)")
        index = try MemoryIndex(path: directory.appendingPathComponent("memory.sqlite").path)
    }

    func moment(_ id: Int64, _ text: String, conversation: Int64 = 1) -> Moment {
        Moment(conversationID: conversation, firstMessageID: id, lastMessageID: id + 1,
               start: base.addingTimeInterval(Double(id) * hour), end: base.addingTimeInterval(Double(id) * hour + 60), text: text)
    }

    @Test func meaningSearchRanksRelatedMomentsFirst() throws {
        try index.add([moment(1, "Maya: what time is dinner sunday"), moment(3, "You: I'll send the photos from the trip"),
                       moment(5, "Maya: knee is better after the doctor")], embedder: WordEmbedder())
        let hits = try index.search("those trip pictures", embedder: WordEmbedder(), limit: 2)
        #expect(hits.first?.moment.firstMessageID == 3)
    }

    @Test func literalWordsBoostOtherwiseEqualMatches() throws {
        try index.add([moment(1, "Maya: climbing saturday?"), moment(3, "Jp: climbing at brooklyn boulders")], embedder: WordEmbedder())
        let hits = try index.search("climbing brooklyn", embedder: WordEmbedder(), limit: 2)
        #expect(hits.map(\.moment.firstMessageID) == [3, 1])
    }

    @Test func momentsWithoutAVectorAreStillFoundByWords() throws {
        try index.add([moment(1, "Maya: lol ok")], embedder: WordEmbedder())
        #expect(try index.search("lol", embedder: WordEmbedder(), limit: 5).map(\.moment.firstMessageID) == [1])
    }

    @Test func tracksHowFarEachConversationIsIndexed() throws {
        #expect(try index.indexedThrough(conversationID: 1) == 0)
        try index.add([moment(1, "a photos"), moment(9, "b photos"), moment(4, "c photos", conversation: 2)], embedder: WordEmbedder())
        #expect(try index.indexedThrough(conversationID: 1) == 10)
        #expect(try index.indexedThrough(conversationID: 2) == 5)
    }

    @Test func addingTheSameMomentTwiceKeepsOneCopy() throws {
        try index.add([moment(1, "a photos")], embedder: WordEmbedder())
        try index.add([moment(1, "a photos")], embedder: WordEmbedder())
        #expect(try index.count() == 1)
    }

    @Test func persistsAcrossReopening() throws {
        try index.add([moment(1, "trip photos")], embedder: WordEmbedder())
        let reopened = try MemoryIndex(path: directory.appendingPathComponent("memory.sqlite").path)
        #expect(try reopened.search("photos", embedder: WordEmbedder(), limit: 1).count == 1)
    }

    @Test func noMatchesReturnsNothing() throws {
        try index.add([moment(1, "Maya: what time is dinner sunday")], embedder: WordEmbedder())
        #expect(try index.search("zebra", embedder: WordEmbedder(), limit: 5).isEmpty)
    }

    @Test func pruningKeepsOnlyTheChosenConversations() throws {
        try index.add([moment(1, "a photos", conversation: 1), moment(2, "b photos", conversation: 2),
                       moment(3, "c photos", conversation: 3)], embedder: WordEmbedder())
        #expect(try index.prune(keeping: [2]) == 2)
        #expect(try index.count() == 1)
        #expect(try index.search("photos", embedder: WordEmbedder(), limit: 5).map(\.moment.conversationID) == [2])
    }

    @Test func deleteAllEmptiesTheIndex() throws {
        try index.add([moment(1, "a photos"), moment(2, "b photos", conversation: 2)], embedder: WordEmbedder())
        try index.deleteAll()
        #expect(try index.count() == 0)
        #expect(try index.search("photos", embedder: WordEmbedder(), limit: 5).isEmpty)
    }

    @Test func deletedTextDoesNotLingerInTheFile() throws {
        let secret = "zebracorn-\(UUID().uuidString)" + String(repeating: " long message", count: 600)
        try index.add([moment(1, "Maya: \(secret)", conversation: 1), moment(2, "keep photos", conversation: 2)], embedder: WordEmbedder())
        try index.prune(keeping: [2])
        let bytes = try Data(contentsOf: directory.appendingPathComponent("memory.sqlite"))
        #expect(bytes.range(of: Data(secret.utf8)) == nil)
    }
}
