import Foundation

/// A conversation laid out for reading: day dividers between calendar days, and in groups a
/// sender label whenever someone else starts speaking.
public enum ThreadTimeline {
    public struct Item: Sendable, Identifiable, Equatable {
        public enum Kind: Sendable, Equatable {
            case day
            case message
        }

        public let id: String
        public let kind: Kind
        public let date: Date
        public let message: Message?
        public let showsSender: Bool
    }

    public static func items(for messages: [Message], isGroup: Bool, calendar: Calendar = .current) -> [Item] {
        var items: [Item] = []
        var currentDay: Date?
        var previousSpeaker: String??
        for message in messages.filter({ $0.kind == .text || $0.kind == .attachmentOnly }).sorted(by: { $0.date < $1.date }) {
            let day = calendar.startOfDay(for: message.date)
            if day != currentDay {
                items.append(Item(id: "day-\(day.timeIntervalSinceReferenceDate)", kind: .day, date: day, message: nil, showsSender: false))
                currentDay = day
                previousSpeaker = nil
            }
            let speaker: String? = message.isFromMe ? nil : message.sender
            let showsSender = isGroup && !message.isFromMe && previousSpeaker != .some(speaker)
            items.append(Item(id: "msg-\(message.id)", kind: .message, date: message.date, message: message, showsSender: showsSender))
            previousSpeaker = .some(speaker)
        }
        return items
    }
}
