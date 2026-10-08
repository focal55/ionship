import Foundation
import Testing
@testable import IonshipCore

private func w(_ id: Int64, me: Bool, _ text: String?, kind: Message.Kind = .text) -> Message {
    Message(id: id, guid: "g\(id)", chatID: 1, sender: me ? nil : "x", isFromMe: me, date: Date(timeIntervalSince1970: Double(id)),
            text: text, textSource: .column, kind: kind)
}

@Suite struct WritingStyleTests {
    @Test func describesOnlyYourOwnMessages() {
        let style = WritingStyle(of: [
            w(1, me: true, "ok cool"), w(2, me: true, "sounds good to me"), w(3, me: true, "yep"),
            w(4, me: false, "THIS IS A VERY LONG MESSAGE FROM SOMEONE ELSE 😂😂"),
        ])
        #expect(style.sampleSize == 3)
        #expect(style.typicalLength == 7)
        #expect(style.lowercaseShare == 1)
        #expect(!style.usesEmoji)
    }

    @Test func emojiAndCapitalization() {
        let style = WritingStyle(of: [
            w(1, me: true, "Haha yes 😂"), w(2, me: true, "Totally"), w(3, me: true, "omg 🙌"), w(4, me: true, "See you then"),
        ])
        #expect(style.lowercaseShare == 0.25)
        #expect(style.usesEmoji)
    }

    @Test func reactionsAndAttachmentsAreIgnored() {
        let style = WritingStyle(of: [w(1, me: true, "Loved “hi”", kind: .reaction), w(2, me: true, nil, kind: .attachmentOnly)])
        #expect(style.sampleSize == 0)
        #expect(style.summary == nil)
    }

    @Test func summaryReadsLikeAnInstruction() {
        let style = WritingStyle(of: (0..<10).map { w(Int64($0), me: true, "lol ok see u soon") })
        #expect(style.summary == "Your messages to them are usually about 17 characters, mostly lowercase, with no emoji.")
    }

    @Test func considersOnlyTheMostRecentHundred() {
        let old = (0..<200).map { w(Int64($0), me: true, "This is an older and much longer message with capitals.") }
        let recent = (200..<300).map { w(Int64($0), me: true, "k") }
        #expect(WritingStyle(of: old + recent).typicalLength == 1)
    }
}
