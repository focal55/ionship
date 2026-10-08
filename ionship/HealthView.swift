import Charts
import IonshipCore
import SwiftUI

struct HealthView: View {
    let people: [PersonHealth]
    let onChangeConversations: () -> Void
    @State private var selection: Int64?

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Divider().overlay(Theme.hairline)
            if let person = people.first(where: { $0.id == selection }) ?? people.first {
                PersonHealthDetail(person: person)
            }
        }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("RELATIONSHIPS")
                .font(.system(size: 11, weight: .medium))
                .tracking(0.9)
                .foregroundStyle(Theme.muted)
                .padding(.horizontal, 20)
                .padding(.top, 20)
                .padding(.bottom, 8)
            ScrollView {
                VStack(spacing: 2) {
                    ForEach(people) { person in
                        sidebarRow(person, isSelected: person.id == (selection ?? people.first?.id))
                    }
                }
                .padding(.horizontal, 10)
            }
            Divider().overlay(Theme.hairline)
            Button("Change conversations", action: onChangeConversations)
                .buttonStyle(.plain)
                .font(.system(size: 13))
                .foregroundStyle(Theme.secondary)
                .padding(16)
        }
        .frame(width: 280)
    }

    private func sidebarRow(_ person: PersonHealth, isSelected: Bool) -> some View {
        Button { selection = person.id } label: {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(person.title).font(.system(size: 14, weight: .medium)).lineLimit(1)
                    Text("\(person.metrics.messageCount.formatted()) messages")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.muted)
                }
                Spacer()
                if person.metrics.observations().contains(where: \.isActionable) {
                    Circle().fill(Theme.accent).frame(width: 7, height: 7)
                        .accessibilityLabel("Something changed")
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(isSelected ? Theme.surface : .clear, in: .rect(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(isSelected ? Theme.hairline : .clear))
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }
}

private struct PersonHealthDetail: View {
    let person: PersonHealth
    private var metrics: RelationshipMetrics { person.metrics }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(person.title).font(.system(size: 34, weight: .semibold)).tracking(-1)
                    Text("\(metrics.messageCount.formatted()) messages · \(metrics.conversations.formatted()) conversations")
                        .foregroundStyle(Theme.secondary)
                }

                let observations = metrics.observations()
                if !observations.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(observations, id: \.self) { observation in
                            HStack(alignment: .firstTextBaseline, spacing: 10) {
                                Circle().fill(Theme.accent).frame(width: 7, height: 7)
                                Text(sentence(for: observation)).font(.system(size: 16))
                            }
                        }
                    }
                }

                tiles
                VolumeChart(weeks: metrics.weekly)
            }
            .padding(36)
            .frame(maxWidth: 1000, alignment: .leading)
        }
        .frame(maxWidth: .infinity)
        .background(Theme.surface)
    }

    private var tiles: some View {
        Grid(horizontalSpacing: 1, verticalSpacing: 1) {
            GridRow {
                Tile(label: "You start", value: metrics.youStartShare.map { $0.formatted(.percent.precision(.fractionLength(0))) } ?? "—",
                     detail: "of \(metrics.conversations.formatted()) talks")
                Tile(label: "Your reply", value: Elapsed.short(metrics.yourMedianReply),
                     detail: metrics.yourRecentMedianReply.map { "\(Elapsed.short($0)) lately" } ?? "none lately")
                Tile(label: "Their reply", value: Elapsed.short(metrics.theirMedianReply), detail: "typical")
                Tile(label: "Long talk", value: metrics.lastLongConversation.map { Elapsed.ago($0) } ?? "—",
                     detail: metrics.usualGapBetweenLongConversations.map { "usually every \(Elapsed.short($0))" } ?? "none yet")
            }
        }
        .background(Theme.hairline)
        .clipShape(.rect(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.hairline))
    }

    private func sentence(for observation: RelationshipMetrics.Observation) -> String {
        switch observation {
        case .theyStartMost(let share):
            "They start \(share.formatted(.percent.precision(.fractionLength(0)))) of your conversations."
        case .youStartMost(let share):
            "You start \(share.formatted(.percent.precision(.fractionLength(0)))) of your conversations."
        case .repliesSlowing(let recent, let usual):
            "Your replies have slowed: \(Elapsed.short(recent)) lately, \(Elapsed.short(usual)) usually."
        case .overdue(let since, let usual):
            "It’s been \(Elapsed.short(since)) since a long conversation. Usually it’s every \(Elapsed.short(usual))."
        }
    }
}

private struct Tile: View {
    let label: String
    let value: String
    let detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.system(size: 12)).foregroundStyle(Theme.muted)
            Text(value).font(Theme.mono(26).weight(.medium)).tracking(-0.5)
            Text(detail).font(.system(size: 12)).foregroundStyle(Theme.secondary).lineLimit(1)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(.horizontal, 20)
        .padding(.vertical, 18)
        .background(Theme.surface)
    }
}

private struct VolumeChart: View {
    let weeks: [RelationshipMetrics.Week]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Messages per week").font(.system(size: 15, weight: .semibold))
            Chart {
                ForEach(weeks, id: \.start) { week in
                    BarMark(x: .value("Week", week.start, unit: .weekOfYear), y: .value("Messages", week.theirs))
                        .foregroundStyle(by: .value("From", "Them"))
                    BarMark(x: .value("Week", week.start, unit: .weekOfYear), y: .value("Messages", week.mine))
                        .foregroundStyle(by: .value("From", "You"))
                }
            }
            .chartForegroundStyleScale(["Them": Theme.accent, "You": Theme.ink])
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
        let days = Int(Date.now.timeIntervalSince(date) / 86_400)
        return days == 0 ? "today" : "\(days)d ago"
    }
}

#Preview {
    HealthView(people: samplePeople()) {}
        .frame(width: 960, height: 760)
        .background(Theme.ground)
        .foregroundStyle(Theme.ink)
        .preferredColorScheme(.light)
}

private func samplePeople() -> [PersonHealth] {
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
        return PersonHealth(conversation: Conversation(chats: [chat]), title: title, metrics: RelationshipMetrics.compute(messages))
    }
    return [person(1, "Mom", myReply: 900, iStartEvery: 5), person(2, "Maya Chen", myReply: 300, iStartEvery: 2)]
}
