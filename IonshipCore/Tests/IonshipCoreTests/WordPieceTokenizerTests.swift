import Foundation
import Testing
@testable import IonshipCore

@Suite struct WordPieceTokenizerTests {
    struct Golden: Decodable {
        let text: String
        let ids: [Int32]
    }

    static let golden: [Golden] = {
        let url = Bundle.module.url(forResource: "tokenizer-golden", withExtension: "json")!
        return try! JSONDecoder().decode([Golden].self, from: Data(contentsOf: url))
    }()

    let tokenizer = try! WordPieceTokenizer.bundled()

    @Test(arguments: golden)
    func matchesTheReferenceTokenizer(_ case: Golden) {
        #expect(tokenizer.ids(for: `case`.text, maxLength: 128) == `case`.ids)
    }

    @Test func encodingPadsToLengthWithAMask() {
        let encoded = tokenizer.encode("hi there", length: 8)
        #expect(encoded.ids.count == 8)
        #expect(encoded.mask == [1, 1, 1, 1, 0, 0, 0, 0])
        #expect(encoded.ids.suffix(4) == [0, 0, 0, 0])
    }
}

@Suite struct MemoryIndexEmbedderVersionTests {
    @Test func changingTheEmbedderClearsOldVectors() throws {
        let path = FileManager.default.temporaryDirectory.appendingPathComponent("memory-\(UUID().uuidString)/memory.sqlite").path
        let moment = Moment(conversationID: 1, firstMessageID: 1, lastMessageID: 2, start: .now, end: .now, text: "trip photos")
        try MemoryIndex(path: path, embedderID: "apple-contextual").add([moment], embedder: WordEmbedder())
        #expect(try MemoryIndex(path: path, embedderID: "apple-contextual").count() == 1)
        #expect(try MemoryIndex(path: path, embedderID: "minilm-l6-v2").count() == 0)
        #expect(try MemoryIndex(path: path, embedderID: "minilm-l6-v2").indexedThrough(conversationID: 1) == 0)
    }
}
