import Foundation
import FoundationModels
import OdeCore

@Generable
struct ConversationTopics {
    @Guide(description: "Three to six short topics these two keep coming back to, two or three words each, lowercase, for example 'job search' or 'portland move'.", .count(3...6))
    var topics: [String]
}

/// Recurring topics from recent messages, on device. Empty when the model is unavailable or
/// declines the text.
enum TopicExtractor {
    private static let instructions = "You list the subjects a conversation keeps returning to. Use only what the messages discuss."

    static func topics(in messages: [Message], name: (String?) -> String, cloud: CloudRunner? = nil) async -> [String] {
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
        let prompt = lines.reversed().joined(separator: "\n")
        if let cloud, let data = await cloud(CloudRequest(system: instructions, prompt: prompt, schemaName: "topics", schema: CloudSchemas.topics)),
           let topics = try? JSONDecoder().decode(CloudSchemas.Topics.self, from: data) {
            return Array(topics.topics.prefix(6)).map { $0.lowercased() }
        }
        guard SystemLanguageModel.default.isAvailable else { return [] }
        let session = LanguageModelSession(instructions: instructions)
        return (try? await session.respond(to: prompt, generating: ConversationTopics.self).content.topics) ?? []
    }
}
