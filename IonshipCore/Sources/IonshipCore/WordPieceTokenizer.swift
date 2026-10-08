import Foundation

/// BERT uncased WordPiece tokenization, matching Hugging Face's BertTokenizer so the bundled
/// sentence model sees the same token ids it was trained on. Works on Unicode scalars because
/// the reference implementation works on code points.
public struct WordPieceTokenizer: Sendable {
    private let vocabulary: [String: Int32]
    private let unknown: Int32
    private let classify: Int32
    private let separator: Int32

    public init(vocabulary lines: [String]) {
        var vocabulary: [String: Int32] = [:]
        for (index, token) in lines.enumerated() where vocabulary[token] == nil { vocabulary[token] = Int32(index) }
        self.vocabulary = vocabulary
        unknown = vocabulary["[UNK]"] ?? 100
        classify = vocabulary["[CLS]"] ?? 101
        separator = vocabulary["[SEP]"] ?? 102
    }

    public static func bundled() throws -> WordPieceTokenizer {
        let url = Bundle.module.url(forResource: "vocab", withExtension: "txt")!
        let lines = try String(contentsOf: url, encoding: .utf8).split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        return WordPieceTokenizer(vocabulary: lines)
    }

    /// [CLS] tokens [SEP], truncated to `maxLength`.
    public func ids(for text: String, maxLength: Int) -> [Int32] {
        let pieces = basicTokens(text).flatMap(wordPieces)
        return [classify] + pieces.prefix(maxLength - 2) + [separator]
    }

    public func encode(_ text: String, length: Int) -> (ids: [Int32], mask: [Int32]) {
        let ids = ids(for: text, maxLength: length)
        let padding = length - ids.count
        return (ids + Array(repeating: 0, count: padding), Array(repeating: 1, count: ids.count) + Array(repeating: 0, count: padding))
    }

    private func basicTokens(_ text: String) -> [[Unicode.Scalar]] {
        var cleaned: [Unicode.Scalar] = []
        for scalar in text.unicodeScalars {
            if scalar.value == 0 || scalar.value == 0xFFFD || Self.isControl(scalar) { continue }
            if Self.isWhitespace(scalar) {
                cleaned.append(" ")
            } else if Self.isCJK(scalar) {
                cleaned += [" ", scalar, " "]
            } else {
                cleaned.append(scalar)
            }
        }
        return cleaned.split(separator: " ").flatMap { word -> [[Unicode.Scalar]] in
            let lowered = String(String.UnicodeScalarView(word)).lowercased().decomposedStringWithCanonicalMapping
            let stripped = lowered.unicodeScalars.filter { $0.properties.generalCategory != .nonspacingMark }
            var tokens: [[Unicode.Scalar]] = []
            var current: [Unicode.Scalar] = []
            for scalar in stripped {
                if Self.isPunctuation(scalar) {
                    if !current.isEmpty { tokens.append(current); current = [] }
                    tokens.append([scalar])
                } else {
                    current.append(scalar)
                }
            }
            if !current.isEmpty { tokens.append(current) }
            return tokens
        }
    }

    private func wordPieces(_ word: [Unicode.Scalar]) -> [Int32] {
        guard word.count <= 100 else { return [unknown] }
        var pieces: [Int32] = []
        var start = 0
        while start < word.count {
            var end = word.count
            var match: Int32?
            while start < end {
                let piece = (start > 0 ? "##" : "") + String(String.UnicodeScalarView(word[start..<end]))
                if let id = vocabulary[piece] { match = id; break }
                end -= 1
            }
            guard let match else { return [unknown] }
            pieces.append(match)
            start = end
        }
        return pieces
    }

    private static func isWhitespace(_ scalar: Unicode.Scalar) -> Bool {
        scalar == " " || scalar == "\t" || scalar == "\n" || scalar == "\r" || scalar.properties.generalCategory == .spaceSeparator
    }

    private static func isControl(_ scalar: Unicode.Scalar) -> Bool {
        if scalar == "\t" || scalar == "\n" || scalar == "\r" { return false }
        let category = scalar.properties.generalCategory
        return category == .control || category == .format
    }

    private static func isPunctuation(_ scalar: Unicode.Scalar) -> Bool {
        let v = scalar.value
        if (33...47).contains(v) || (58...64).contains(v) || (91...96).contains(v) || (123...126).contains(v) { return true }
        switch scalar.properties.generalCategory {
        case .connectorPunctuation, .dashPunctuation, .openPunctuation, .closePunctuation,
             .initialPunctuation, .finalPunctuation, .otherPunctuation:
            return true
        default:
            return false
        }
    }

    private static func isCJK(_ scalar: Unicode.Scalar) -> Bool {
        let v = scalar.value
        return (0x4E00...0x9FFF).contains(v) || (0x3400...0x4DBF).contains(v) || (0x20000...0x2A6DF).contains(v)
            || (0x2A700...0x2B73F).contains(v) || (0x2B740...0x2B81F).contains(v) || (0x2B820...0x2CEAF).contains(v)
            || (0xF900...0xFAFF).contains(v) || (0x2F800...0x2FA1F).contains(v)
    }
}
