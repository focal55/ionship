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

public struct ConversationPicker: Sendable {
    public private(set) var all: [Chat]
    public private(set) var selected: Set<Int64>
    public var filter = ""

    public init(chats: [Chat], preselect: Int = 10) {
        all = chats.filter { $0.messageCount > 0 }.sorted { $0.messageCount > $1.messageCount }
        selected = Set(all.prefix(preselect).map(\.id))
    }

    public var visible: [Chat] {
        let query = filter.trimmingCharacters(in: .whitespaces).lowercased()
        guard !query.isEmpty else { return all }
        return all.filter { chat in
            ([chat.displayName ?? "", chat.identifier] + chat.participants).contains { $0.lowercased().contains(query) }
        }
    }

    public var selectedMessageCount: Int {
        all.filter { selected.contains($0.id) }.reduce(0) { $0 + $1.messageCount }
    }

    public mutating func toggle(_ id: Int64) {
        if selected.remove(id) == nil { selected.insert(id) }
    }

    public static func title(for chat: Chat) -> String {
        if let name = chat.displayName { return name }
        switch chat.participants.count {
        case 0: return chat.identifier
        case 1: return chat.participants[0]
        case 2: return chat.participants.joined(separator: ", ")
        default: return "\(chat.participants.prefix(2).joined(separator: ", ")) +\(chat.participants.count - 2)"
        }
    }
}
