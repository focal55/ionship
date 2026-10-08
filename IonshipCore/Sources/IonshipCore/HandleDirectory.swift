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

    private var entryNames: [String] = []
    private var entryIndex: [String: Int] = [:]

    public init(entries: [Entry] = []) {
        for (index, entry) in entries.enumerated() {
            entryNames.append(entry.name)
            for key in entry.phones.compactMap(Self.phoneKey) + entry.emails.compactMap(Self.emailKey) where entryIndex[key] == nil {
                entryIndex[key] = index
            }
        }
    }

    public func name(for handle: String) -> String? {
        contactKey(for: handle).map { entryNames[$0] }
    }

    /// Identifies the contact card a handle belongs to, so one person's phone and email
    /// chats can be merged without conflating two contacts who share a name.
    public func contactKey(for handle: String) -> Int? {
        let key = handle.contains("@") ? Self.emailKey(handle) : Self.phoneKey(handle)
        return key.flatMap { entryIndex[$0] }
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
