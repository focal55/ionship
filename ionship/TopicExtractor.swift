import FoundationModels
import IonshipCore

@Generable
struct ConversationTopics {
    @Guide(description: "Three to six short topics these two keep coming back to, two or three words each, lowercase, for example 'job search' or 'portland move'.", .count(3...6))
    var topics: [String]
}

/// Recurring topics from recent messages, on device. Empty when the model is unavailable or
/// declines the text.
enum TopicExtractor {
    static func topics(in messages: [Message], name: (String?) -> String) async -> [String] {
        guard SystemLanguageModel.default.isAvailable else { return [] }
        var budget = 2400
        var lines: [String] = []
        for message in messages.reversed() where message.kind == .text {
            guard let text = message.text, text.count >= 12 else { continue }
            let line = "\(message.isFromMe ? "You" : name(message.sender)): \(text.prefix(200))"
            budget -= line.count
            guard budget > 0 else { break }
            lines.append(line)
        }
        guard lines.count >= 10 else { return [] }
        let session = LanguageModelSession(instructions: "You list the subjects a conversation keeps returning to. Use only what the messages discuss.")
        let prompt = lines.reversed().joined(separator: "\n")
        return (try? await session.respond(to: prompt, generating: ConversationTopics.self).content.topics) ?? []
    }
}
