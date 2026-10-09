import Foundation
import Testing
@testable import OdeCore

@Suite struct AttributedBodyDecoderTests {
    @Test func unarchiverDecodesShortTypedstream() {
        #expect(AttributedBodyDecoder.decodeWithUnarchiver(archived("short body")) == "short body")
        #expect(AttributedBodyDecoder.decodeDetailed(archived("short body"))?.strategy == .unarchiver)
    }

    @Test func unarchiverDecodesMultiByteLengthTypedstream() {
        #expect(longBody.utf8.count > 255)
        #expect(AttributedBodyDecoder.decodeWithUnarchiver(archived(longBody)) == longBody)
    }

    @Test(arguments: ["short body", "hi \u{1F600} é", longBody, String(repeating: "x", count: 70_000)])
    func fallbackDecodesRealTypedstream(_ text: String) {
        #expect(AttributedBodyDecoder.decodeWithFallback(archived(text)) == text)
    }

    @Test func fallbackDecodesHandCraftedSingleByteLength() {
        let blob = Data("streamtyped junk NSString".utf8) + Data([0x01, 0x94, 0x84, 0x01, 0x2B, 0x05])
            + Data("hello".utf8) + Data([0x86, 0x84])
        #expect(AttributedBodyDecoder.decodeWithFallback(blob) == "hello")
        #expect(AttributedBodyDecoder.decodeWithUnarchiver(blob) == nil)
        #expect(AttributedBodyDecoder.decodeDetailed(blob)?.strategy == .fallback)
        #expect(AttributedBodyDecoder.decode(blob) == "hello")
    }

    @Test func fallbackDecodesHandCrafted0x81Length() {
        let text = String(repeating: "ab", count: 200)
        let blob = Data("NSString".utf8) + Data([0x01, 0x94, 0x84, 0x01, 0x2B, 0x81, 0x90, 0x01])
            + Data(text.utf8) + Data([0x86])
        #expect(AttributedBodyDecoder.decodeWithFallback(blob) == text)
    }

    @Test func fallbackRejectsLengthPastEndOfData() {
        let blob = Data("NSString".utf8) + Data([0x01, 0x94, 0x84, 0x01, 0x2B, 0x40]) + Data("short".utf8)
        #expect(AttributedBodyDecoder.decodeWithFallback(blob) == nil)
    }

    @Test func garbageDecodesToNilWithoutCrashing() {
        #expect(AttributedBodyDecoder.decode(garbageBody) == nil)
        #expect(AttributedBodyDecoder.decode(archived("truncated body").prefix(40)) == nil)
        #expect(AttributedBodyDecoder.decode(Data()) == nil)
    }

    @Test func objectReplacementCharacterIsStripped() {
        #expect(AttributedBodyDecoder.decode(archived("see \u{FFFC}this")) == "see this")
        #expect(AttributedBodyDecoder.decode(archived("\u{FFFC}")) == "")
        #expect(AttributedBodyDecoder.decodeWithFallback(archived("\u{FFFC}a")) == "a")
    }
}
