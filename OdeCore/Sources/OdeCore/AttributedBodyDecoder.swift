import Foundation
import ObjCExceptionCatcher

/// Decodes the `attributedBody` column, where Messages has stored most message text since
/// Ventura. The blob is an NSArchiver typedstream of an NSAttributedString.
public enum AttributedBodyDecoder {
    public enum Strategy: Sendable, Equatable {
        case unarchiver
        case fallback
    }

    public struct Decoded: Sendable, Equatable {
        public let text: String
        public let strategy: Strategy
    }

    public static func decode(_ data: Data) -> String? {
        decodeDetailed(data)?.text
    }

    public static func decodeDetailed(_ data: Data) -> Decoded? {
        if let text = decodeWithUnarchiver(data) { return Decoded(text: text, strategy: .unarchiver) }
        if let text = decodeWithFallback(data) { return Decoded(text: text, strategy: .fallback) }
        return nil
    }

    static func decodeWithUnarchiver(_ data: Data) -> String? {
        guard !data.isEmpty else { return nil }
        var result: String?
        // NSUnarchiver raises NSException on malformed input; Swift cannot catch that natively.
        let ok = IONTryObjC {
            result = ((LegacyUnarchiver() as any Unarchiving).unarchive(data) as? NSAttributedString)?.string
        }
        return ok ? result.map(stripObjectReplacement) : nil
    }

    /// Reads the first NSString payload directly, in case NSUnarchiver is removed or rejects
    /// a blob. Typedstream integers: a byte below 0x80 is the value; 0x81 prefixes an Int16,
    /// 0x82 an Int32, both little-endian.
    static func decodeWithFallback(_ data: Data) -> String? {
        let bytes = [UInt8](data)
        guard let marker = firstRange(of: Array("NSString".utf8), in: bytes) ?? firstRange(of: Array("NSMutableString".utf8), in: bytes),
              let plus = bytes[marker.upperBound...].firstIndex(of: 0x2B) else { return nil }

        var cursor = plus + 1
        guard cursor < bytes.count else { return nil }
        let length: Int
        switch bytes[cursor] {
        case 0x81:
            guard cursor + 2 < bytes.count else { return nil }
            length = Int(bytes[cursor + 1]) | Int(bytes[cursor + 2]) << 8
            cursor += 3
        case 0x82:
            guard cursor + 4 < bytes.count else { return nil }
            length = (0..<4).reduce(0) { $0 | Int(bytes[cursor + 1 + $1]) << (8 * $1) }
            cursor += 5
        case let byte where byte < 0x80:
            length = Int(byte)
            cursor += 1
        default:
            return nil
        }

        guard length >= 0, cursor + length <= bytes.count,
              let text = String(bytes: bytes[cursor..<(cursor + length)], encoding: .utf8) else { return nil }
        return stripObjectReplacement(text)
    }

    private static func stripObjectReplacement(_ text: String) -> String {
        text.replacingOccurrences(of: "\u{FFFC}", with: "")
    }

    private static func firstRange(of needle: [UInt8], in haystack: [UInt8]) -> Range<Int>? {
        guard needle.count <= haystack.count else { return nil }
        for start in 0...(haystack.count - needle.count) where haystack[start..<(start + needle.count)].elementsEqual(needle) {
            return start..<(start + needle.count)
        }
        return nil
    }
}

private protocol Unarchiving { func unarchive(_ data: Data) -> Any? }

/// Called through a protocol so the deliberate use of deprecated NSUnarchiver does not warn.
private struct LegacyUnarchiver: Unarchiving {
    @available(macOS, deprecated: 10.13)
    func unarchive(_ data: Data) -> Any? {
        NSUnarchiver.unarchiveObject(with: data)
    }
}
