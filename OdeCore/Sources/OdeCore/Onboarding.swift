import Foundation

public enum MessagesAccess: Sendable, Equatable {
    case granted
    case denied
    case unavailable

    public static func check(path: String = MessagesStore.defaultPath) -> MessagesAccess {
        do {
            _ = try MessagesStore(path: path)
            return .granted
        } catch MessagesStoreError.accessDenied {
            return .denied
        } catch {
            return .unavailable
        }
    }

    public static let settingsURL = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles")!
}

/// One row in the picker: a group chat, or every 1:1 chat with the same contact.
public struct Conversation: Sendable, Equatable, Identifiable {
    public let chats: [Chat]

    public init(chats: [Chat]) {
        self.chats = chats.sorted { $0.messageCount > $1.messageCount }
    }

    public var id: Int64 { chatIDs[0] }
    public var chatIDs: [Int64] { chats.map(\.id).sorted() }
    public var isGroup: Bool { chats[0].isGroup }
    public var displayName: String? { chats.lazy.compactMap(\.displayName).first }
    public var identifier: String { chats[0].identifier }
    public var messageCount: Int { chats.reduce(0) { $0 + $1.messageCount } }
    public var lastMessageDate: Date? { chats.compactMap(\.lastMessageDate).max() }
    public var firstMessageDate: Date? { chats.compactMap(\.firstMessageDate).min() }

    /// "iMessage", "SMS", or both when one person's chats span services.
    public var service: String? {
        let services = Array(Set(chats.compactMap(\.service))).sorted()
        return services.isEmpty ? nil : services.joined(separator: " + ")
    }

    public var participants: [String] {
        var seen = Set<String>()
        return chats.flatMap(\.participants).filter { seen.insert($0).inserted }
    }
}

public struct ConversationPicker: Sendable {
    private let chats: [Chat]
    /// Chat IDs, not conversation IDs: merging changes once contact names arrive.
    public private(set) var selected: Set<Int64>
    public var filter = ""
    public var names = HandleDirectory()

    public init(chats: [Chat], preselect: Int = 10) {
        self.chats = chats.filter { $0.messageCount > 0 }.sorted { $0.messageCount > $1.messageCount }
        selected = Set(self.chats.prefix(preselect).map(\.id))
    }

    public var all: [Conversation] {
        var order: [String] = []
        var groups: [String: [Chat]] = [:]
        for chat in chats {
            let key: String
            if !chat.isGroup, chat.participants.count == 1, let contact = names.contactKey(for: chat.participants[0]) {
                key = "contact:\(contact)"
            } else {
                key = "chat:\(chat.id)"
            }
            if groups[key] == nil { order.append(key) }
            groups[key, default: []].append(chat)
        }
        return order.map { Conversation(chats: groups[$0]!) }.sorted { $0.messageCount > $1.messageCount }
    }

    public var visible: [Conversation] {
        let query = filter.trimmingCharacters(in: .whitespaces).lowercased()
        guard !query.isEmpty else { return all }
        return all.filter { conversation in
            ([conversation.displayName ?? "", conversation.identifier, title(for: conversation)] + conversation.participants)
                .contains { $0.lowercased().contains(query) }
        }
    }

    public var selectedConversations: [Conversation] {
        all.filter(isSelected)
    }

    public var selectedMessageCount: Int {
        selectedConversations.reduce(0) { $0 + $1.messageCount }
    }

    public func isSelected(_ conversation: Conversation) -> Bool {
        !selected.isDisjoint(with: conversation.chatIDs)
    }

    public mutating func restore(selection: Set<Int64>) {
        selected = selection.intersection(chats.map(\.id))
    }

    public mutating func toggle(_ id: Int64) {
        guard let conversation = all.first(where: { $0.id == id }) else { return }
        if isSelected(conversation) {
            selected.subtract(conversation.chatIDs)
        } else {
            selected.formUnion(conversation.chatIDs)
        }
    }

    public func title(for chat: Chat) -> String {
        title(displayName: chat.displayName, participants: chat.participants, identifier: chat.identifier)
    }

    public func title(for conversation: Conversation) -> String {
        title(displayName: conversation.displayName, participants: conversation.participants, identifier: conversation.identifier)
    }

    private func title(displayName: String?, participants: [String], identifier: String) -> String {
        if let displayName { return displayName }
        var seen = Set<String>()
        let people = participants.map { names.name(for: $0) ?? $0 }.filter { seen.insert($0).inserted }
        switch people.count {
        case 0: return names.name(for: identifier) ?? identifier
        case 1, 2: return people.joined(separator: ", ")
        default: return "\(people.prefix(2).joined(separator: ", ")) +\(people.count - 2)"
        }
    }
}
