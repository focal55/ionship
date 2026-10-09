import FoundationModels
import IonshipCore

@Generable
struct DraftOption {
    @Guide(description: "The complete message You could send as-is.")
    var text: String

    @Guide(description: "Under eight words on why this works, for example 'Closes the photos loop' or 'Matches her tone'.")
    var why: String
}

@Generable
struct ReplyDrafts {
    @Guide(description: "A direct reply that answers the latest message.")
    var direct: DraftOption

    @Guide(description: "A warm reply that answers the latest message and shows interest in them.")
    var warm: DraftOption

    @Guide(description: "A reply with light humor that still answers the latest message.")
    var playful: DraftOption
}

struct Draft: Identifiable, Equatable {
    let label: String
    let text: String
    let why: String
    var id: String { label }
}

enum DraftLength: String, CaseIterable {
    case brief = "Brief"
    case balanced = "Balanced"
    case expansive = "Expansive"

    var instruction: String {
        switch self {
        case .brief: "Keep each draft under twelve words."
        case .balanced: "Keep each draft to one or two sentences."
        case .expansive: "Each draft can run two to four sentences."
        }
    }
}

enum DraftResult: Equatable {
    case drafts([Draft])
    case unavailable
    case blocked
}

/// Drafts replies on device. Nothing is sent; the user copies or opens Messages.
enum ReplyDrafter {
    private static let instructions = """
        You draft the next text message that 'You' will send in a conversation. Write as You, in first person, replying \
        to the latest messages. Each draft must be a complete message You could send as-is, answering what was just \
        said. If You promised something that is still open, address it honestly. Match You's tone and capitalization; \
        treat the usual length as a guide, not a limit. Never invent facts, plans or names that are not in the conversation.
        """

    static func draft(messages: [Message], name: (String?) -> String, openLoops: [String], steer: String,
                      length: DraftLength, isGroup: Bool) async -> DraftResult {
        guard SystemLanguageModel.default.isAvailable else { return .unavailable }
        var lines = [isGroup ? "Group conversation:" : "Conversation:"]
        lines += messages.filter { $0.kind == .text && $0.text != nil }.suffix(12).map { message in
            "\(message.isFromMe ? "You" : name(message.sender)): \(message.text!.prefix(280))"
        }
        if !openLoops.isEmpty { lines += ["", "Things You promised and hasn't done: \(openLoops.joined(separator: "; "))."] }
        if let style = WritingStyle(of: messages).summary { lines.append(style) }
        lines.append(length.instruction)
        if !steer.isEmpty { lines.append("You want this reply to: \(steer)") }
        let prompt = lines.joined(separator: "\n")

        for _ in 0..<2 {
            let session = LanguageModelSession(instructions: instructions)
            if let drafts = try? await session.respond(to: prompt, generating: ReplyDrafts.self).content {
                return .drafts([
                    Draft(label: "DIRECT", text: drafts.direct.text, why: drafts.direct.why),
                    Draft(label: "WARM", text: drafts.warm.text, why: drafts.warm.why),
                    Draft(label: "PLAYFUL", text: drafts.playful.text, why: drafts.playful.why),
                ])
            }
        }
        return .blocked
    }
}
