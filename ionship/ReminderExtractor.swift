import Foundation
import FoundationModels
import IonshipCore

@Generable
struct Reminder {
    @Guide(description: "When it happens, as written in the messages, for example 'Nov 8' or 'next Thursday'.")
    var when: String

    @Guide(description: "What to remember, in under twelve words, for example 'Her sister’s wedding in Portland'.")
    var text: String
}

@Generable
struct Reminders {
    @Guide(description: "Upcoming events, dates or plans the messages state explicitly. Empty when there are none.", .maximumCount(5))
    var items: [Reminder]
}

/// Dated things worth remembering from the last two months, on device. Only explicit
/// mentions; empty when the model is unavailable or declines.
enum ReminderExtractor {
    static func reminders(in messages: [Message], name: (String?) -> String, now: Date = .now) async -> [Reminder] {
        guard SystemLanguageModel.default.isAvailable else { return [] }
        let cutoff = now.addingTimeInterval(-60 * 86_400)
        var budget = 2600
        var lines: [String] = []
        for message in messages.reversed() where message.kind == .text && message.date >= cutoff {
            guard let text = message.text, text.count >= 10 else { continue }
            let line = "[\(message.date.formatted(.dateTime.month(.abbreviated).day()))] \(message.isFromMe ? "You" : name(message.sender)): \(text.prefix(200))"
            budget -= line.count
            guard budget > 0 else { break }
            lines.append(line)
        }
        guard !lines.isEmpty else { return [] }
        let session = LanguageModelSession(instructions: """
            You read dated text messages and list upcoming events, dates and plans they state explicitly, such as \
            birthdays, appointments, trips or invitations. Never guess. If nothing is stated, return no items.
            """)
        return (try? await session.respond(to: lines.reversed().joined(separator: "\n"), generating: Reminders.self).content.items) ?? []
    }
}
