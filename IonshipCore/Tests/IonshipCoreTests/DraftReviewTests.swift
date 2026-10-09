import Foundation
import Testing
@testable import IonshipCore

private func mine(_ text: String, _ id: Int64) -> Message {
    Message(id: id, guid: "\(id)", chatID: 1, sender: nil, isFromMe: true, date: Date(timeIntervalSince1970: Double(id)),
            text: text, textSource: .column, kind: .text)
}

@Suite struct StyleMatchTests {
    let style = WritingStyle(of: (0..<10).map { mine("sounds good see you then", Int64($0)) })

    @Test func aDraftLikeYourMessagesScoresHigh() {
        #expect(style.match("ok see you there tomorrow") > 0.9)
    }

    @Test func wrongCasingLengthAndEmojiScoreLow() {
        let score = style.match("Absolutely! I would be truly delighted to attend and will bring dessert for everyone 🎉🎉")
        #expect(score < 0.5)
    }

    @Test func scoreIsBetweenZeroAndOne() {
        #expect((0...1).contains(style.match("")))
        #expect((0...1).contains(style.match(String(repeating: "x", count: 5000))))
    }
}

@Suite struct DraftChecksTests {
    let style = WritingStyle(of: (0..<10).map { mine("sounds good see you then", Int64($0)) })

    @Test func closingAnOpenLoopIsCalledOut() {
        let checks = DraftChecks.evaluate("found the big sur photos, sending tonight", style: style,
                                          openLoops: ["Send the Big Sur photos"], lastIncoming: nil)
        #expect(checks.contains(.init(ok: true, text: "Closes your open loop: Send the Big Sur photos")))
    }

    @Test func lengthOutsideYourUsualRangeIsFlagged() {
        let long = String(repeating: "this is a much longer message than usual ", count: 4)
        #expect(DraftChecks.evaluate(long, style: style, openLoops: [], lastIncoming: nil)
            .contains(.init(ok: false, text: "Longer than you usually write to them")))
        #expect(DraftChecks.evaluate("sure thing, see you", style: style, openLoops: [], lastIncoming: nil)
            .contains(.init(ok: true, text: "Matches your usual length with them")))
    }

    @Test func anUnansweredQuestionIsFlagged() {
        let question = "did you ever find those photos?"
        #expect(DraftChecks.evaluate("haha love you", style: style, openLoops: [], lastIncoming: question)
            .contains(.init(ok: false, text: "They asked: “did you ever find those photos?”")))
        #expect(DraftChecks.evaluate("yes found the photos!", style: style, openLoops: [], lastIncoming: question)
            .contains(.init(ok: true, text: "Answers their question")))
    }

    @Test func statementsNeedNoAnswer() {
        let checks = DraftChecks.evaluate("haha nice", style: style, openLoops: [], lastIncoming: "that was fun")
        #expect(!checks.contains { $0.text.hasPrefix("They asked") || $0.text == "Answers their question" })
    }
}
