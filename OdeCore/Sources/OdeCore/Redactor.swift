import Foundation

/// Swaps emails, phone numbers and street addresses for numbered placeholders before text
/// leaves the Mac, and swaps them back in what a model returns. One redactor per
/// conversation keeps the same value on the same placeholder across calls.
public struct Redactor: Sendable {
    private var placeholders: [String: String] = [:]
    private var counts: [String: Int] = [:]

    private static let email = try! NSRegularExpression(pattern: #"[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}"#, options: .caseInsensitive)

    public init() {}

    public mutating func redact(_ text: String) -> String {
        let whole = NSRange(text.startIndex..., in: text)
        var spans: [(range: NSRange, kind: String)] = Self.email.matches(in: text, range: whole).map { ($0.range, "EMAIL") }
        let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.phoneNumber.rawValue | NSTextCheckingResult.CheckingType.address.rawValue)
        for match in detector?.matches(in: text, range: whole) ?? [] where !spans.contains(where: { NSIntersectionRange($0.range, match.range).length > 0 }) {
            spans.append((match.range, match.resultType == .phoneNumber ? "PHONE" : "ADDRESS"))
        }

        var result = text
        for span in spans.sorted(by: { $0.range.location > $1.range.location }) {
            guard let range = Range(span.range, in: result) else { continue }
            let value = String(result[range])
            result.replaceSubrange(range, with: placeholder(for: value, kind: span.kind))
        }
        return result
    }

    public func restore(_ text: String) -> String {
        placeholders.reduce(text) { $0.replacingOccurrences(of: $1.value, with: $1.key) }
    }

    private mutating func placeholder(for value: String, kind: String) -> String {
        if let existing = placeholders[value] { return existing }
        counts[kind, default: 0] += 1
        let placeholder = "[\(kind) \(counts[kind]!)]"
        placeholders[value] = placeholder
        return placeholder
    }
}
