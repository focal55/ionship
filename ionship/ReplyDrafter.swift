import FoundationModels
import IonshipCore

@Generable
struct ReplyDrafts {
    @Guide(description: "A complete, direct reply that answers the latest message, for example 'Found them! Sending tonight, sorry for the wait'.")
    var direct: String

    @Guide(description: "A complete, warm reply that answers the latest message and shows interest in them.")
    var warm: String

    @Guide(description: "A complete reply with light humor that still answers the latest message.")
    var playful: String
}

enum DraftResult: Equatable {
    case drafts([(label: String, text: String)])
    case unavailable
    case blocked

    static func == (lhs: DraftResult, rhs: DraftResult) -> Bool {
        switch (lhs, rhs) {
        case (.drafts(let a), .drafts(let b)): a.map(\.text) == b.map(\.text)
        case (.unavailable, .unavailable), (.blocked, .blocked): true
        default: false
        }
    }
}

/// Drafts replies on device. Nothing is sent; the user copies or opens Messages.
enum ReplyDrafter {
    private static let instructions = """
        You draft the next text message that 'You' will send in a conversation. Write as You, in first person, replying \
        to the latest messages. Each draft must be a complete message You could send as-is, one or two sentences, \
        answering what was just said. If You promised something that is still open, address it honestly. Match You's \
        tone and capitalization; treat the usual length as a guide, not a limit. Never invent facts, plans or names that \
        are not in the conversation.
        """

    static func draft(messages: [Message], name: (String?) -> String, openLoops: [String], steer: String, isGroup: Bool) async -> DraftResult {
        guard SystemLanguageModel.default.isAvailable else { return .unavailable }
        var lines = [isGroup ? "Group conversation:" : "Conversation:"]
        lines += messages.filter { $0.kind == .text && $0.text != nil }.suffix(12).map { message in
            "\(message.isFromMe ? "You" : name(message.sender)): \(message.text!.prefix(280))"
        }
        if !openLoops.isEmpty { lines += ["", "Things You promised and hasn't done: \(openLoops.joined(separator: "; "))."] }
        if let style = WritingStyle(of: messages).summary { lines.append(style) }
        if !steer.isEmpty { lines.append("You want this reply to: \(steer)") }
        let prompt = lines.joined(separator: "\n")

        for _ in 0..<2 {
            let session = LanguageModelSession(instructions: instructions)
            if let drafts = try? await session.respond(to: prompt, generating: ReplyDrafts.self).content {
                return .drafts([("DIRECT", drafts.direct), ("WARM", drafts.warm), ("PLAYFUL", drafts.playful)])
            }
        }
        return .blocked
    }
}
