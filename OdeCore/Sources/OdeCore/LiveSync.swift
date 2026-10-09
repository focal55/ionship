import Foundation

public enum LiveSync {
    /// Groups freshly arrived messages under the conversation that owns their chat; messages
    /// from conversations the user did not choose are dropped.
    public static func route(_ messages: [Message], to conversations: [Conversation]) -> [Int64: [Message]] {
        var owner: [Int64: Int64] = [:]
        for conversation in conversations {
            for chatID in conversation.chatIDs { owner[chatID] = conversation.id }
        }
        var routed: [Int64: [Message]] = [:]
        for message in messages {
            if let id = owner[message.chatID] { routed[id, default: []].append(message) }
        }
        return routed
    }
}
