import Charts
import IonshipCore
import SwiftUI

struct Tile: View {
    let label: String
    let value: String
    let detail: String
    var detailColor = Theme.secondary

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.system(size: 12)).foregroundStyle(Theme.muted)
            Text(value).font(Theme.mono(26).weight(.medium)).tracking(-0.5)
            Text(detail).font(.system(size: 12)).foregroundStyle(detailColor).lineLimit(1)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(.horizontal, 20)
        .padding(.vertical, 18)
        .background(Theme.surface)
    }
}

struct VolumeChart: View {
    let weeks: [RelationshipMetrics.Week]
    var others = "Them"

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Messages per week").font(.system(size: 15, weight: .semibold))
            Chart {
                ForEach(weeks, id: \.start) { week in
                    BarMark(x: .value("Week", week.start, unit: .weekOfYear), y: .value("Messages", week.theirs))
                        .foregroundStyle(by: .value("From", others))
                    BarMark(x: .value("Week", week.start, unit: .weekOfYear), y: .value("Messages", week.mine))
                        .foregroundStyle(by: .value("From", "You"))
                }
            }
            .chartForegroundStyleScale([others: Theme.accent, "You": Theme.ink])
            .chartXAxis { AxisMarks(values: .stride(by: .month, count: 3)) { AxisValueLabel(format: .dateTime.month(.abbreviated)) } }
            .frame(height: 200)
        }
        .padding(22)
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.hairline))
    }
}

enum Elapsed {
    static func short(_ interval: TimeInterval?) -> String {
        guard let interval else { return "—" }
        let minutes = Int(interval / 60)
        if minutes < 1 { return "<1m" }
        if minutes < 60 { return "\(minutes)m" }
        let hours = minutes / 60
        if hours < 24 { return minutes % 60 == 0 ? "\(hours)h" : "\(hours)h \(minutes % 60)m" }
        return "\(hours / 24)d"
    }

    static func ago(_ date: Date) -> String {
        let days = Int((Date.now.timeIntervalSince(date) / 86_400).rounded())
        return days == 0 ? "today" : "\(days)d ago"
    }
}

func samplePeople() -> [PersonHealth] {
    func person(_ id: Int64, _ title: String, myReply: TimeInterval, iStartEvery: Int) -> PersonHealth {
        var messages: [Message] = []
        var next: Int64 = 0
        for day in stride(from: 360, through: 3, by: -2) {
            let start = Date.now.addingTimeInterval(-Double(day) * 86_400)
            let iStart = day % iStartEvery == 0
            let burst = day % 9 == 0 ? 24 : 4
            for i in 0..<burst {
                let fromMe = (i % 2 == 0) == iStart
                let gap = fromMe ? (day < 60 ? myReply * 3 : myReply) : 240
                next += 1
                messages.append(Message(id: next, guid: "\(next)", chatID: id, sender: fromMe ? nil : "x", isFromMe: fromMe,
                                        date: start.addingTimeInterval(Double(i) * gap), text: "x", textSource: .column, kind: .text))
            }
        }
        let chat = Chat(id: id, identifier: title, displayName: title, isGroup: false, participants: [title],
                        messageCount: messages.count, lastMessageDate: messages.last?.date)
        return PersonHealth(conversation: Conversation(chats: [chat]), title: title, health: .person(RelationshipMetrics.compute(messages)))
    }
    return [person(1, "Mom", myReply: 900, iStartEvery: 5), person(2, "Maya Chen", myReply: 300, iStartEvery: 2), sampleGroup()]
}
