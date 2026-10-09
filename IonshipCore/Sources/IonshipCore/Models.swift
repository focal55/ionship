import Foundation

public struct Chat: Sendable, Equatable, Identifiable {
    public let id: Int64
    public let identifier: String
    public let displayName: String?
    public let isGroup: Bool
    public let participants: [String]
    public let messageCount: Int
    public let lastMessageDate: Date?
    public let firstMessageDate: Date?
    /// "iMessage", "SMS" or "RCS"; nil on databases that do not record it.
    public let service: String?

    public init(id: Int64, identifier: String, displayName: String?, isGroup: Bool, participants: [String],
                messageCount: Int, lastMessageDate: Date?, firstMessageDate: Date? = nil, service: String? = nil) {
        self.id = id
        self.identifier = identifier
        self.displayName = displayName
        self.isGroup = isGroup
        self.participants = participants
        self.messageCount = messageCount
        self.lastMessageDate = lastMessageDate
        self.firstMessageDate = firstMessageDate
        self.service = service
    }
}

public struct Message: Sendable, Equatable, Identifiable {
    public enum Kind: Sendable, Equatable {
        case text
        case reaction
        case attachmentOnly
        case other
    }

    public enum TextSource: Sendable, Equatable {
        case column
        case attributedBody(AttributedBodyDecoder.Strategy)
        case undecodable
        case none
    }

    public let id: Int64
    public let guid: String
    public let chatID: Int64
    /// The other party's handle (phone or email); nil when the user sent it.
    public let sender: String?
    public let isFromMe: Bool
    public let date: Date
    public let text: String?
    public let textSource: TextSource
    public let kind: Kind

    public init(id: Int64, guid: String, chatID: Int64, sender: String?, isFromMe: Bool, date: Date,
                text: String?, textSource: TextSource, kind: Kind) {
        self.id = id
        self.guid = guid
        self.chatID = chatID
        self.sender = sender
        self.isFromMe = isFromMe
        self.date = date
        self.text = text
        self.textSource = textSource
        self.kind = kind
    }
}

public struct SchemaReport: Sendable, Equatable {
    public let present: [String]
    public let missing: [String]
    public var isUsable: Bool { missing.isEmpty }
}

public enum MessagesStoreError: Error, Equatable {
    case accessDenied(path: String)
    case cannotOpen(path: String, reason: String)
    case query(message: String)

    static func classifyOpenFailure(path: String, code: Int32, message: String) -> MessagesStoreError {
        let lowered = message.lowercased()
        let denied = code == 23 /* SQLITE_AUTH */ || code == 3 /* SQLITE_PERM */
            || ["authorization denied", "not authorized", "permission denied"].contains { lowered.contains($0) }
        return denied ? .accessDenied(path: path) : .cannotOpen(path: path, reason: message)
    }
}
