import Foundation

/// Maps Messages handles (phone numbers, emails) to contact names.
public struct HandleDirectory: Sendable {
    public struct Entry: Sendable {
        public let name: String
        public let phones: [String]
        public let emails: [String]

        public init(name: String, phones: [String], emails: [String]) {
            self.name = name
            self.phones = phones
            self.emails = emails
        }
    }

    private var names: [String: String] = [:]

    public init(entries: [Entry] = []) {
        for entry in entries {
            for key in entry.phones.compactMap(Self.phoneKey) + entry.emails.compactMap(Self.emailKey) where names[key] == nil {
                names[key] = entry.name
            }
        }
    }

    public func name(for handle: String) -> String? {
        let key = handle.contains("@") ? Self.emailKey(handle) : Self.phoneKey(handle)
        return key.flatMap { names[$0] }
    }

    // Contacts store numbers in whatever format the user typed; Messages uses E.164. Comparing
    // the last ten digits absorbs country codes and punctuation; shorter numbers are short
    // codes and must match exactly.
    static func phoneKey(_ phone: String) -> String? {
        let digits = phone.filter(\.isASCIIDigit)
        guard !digits.isEmpty else { return nil }
        return "tel:" + (digits.count > 10 ? String(digits.suffix(10)) : digits)
    }

    static func emailKey(_ email: String) -> String? {
        let trimmed = email.trimmingCharacters(in: .whitespaces).lowercased()
        return trimmed.isEmpty ? nil : "mail:" + trimmed
    }
}

private extension Character {
    var isASCIIDigit: Bool { isASCII && isNumber }
}
