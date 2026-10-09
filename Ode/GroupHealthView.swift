import Charts
import OdeCore
import SwiftUI

struct GroupHealthDetail: View {
    let group: PersonHealth
    let metrics: GroupMetrics
    var loadOpenLoops: ((PersonHealth) async -> OpenLoops)?

    private static let palette: [Color] = [
        Theme.accent,
        Color(red: 0.059, green: 0.463, blue: 0.431),
        Color(red: 0.761, green: 0.255, blue: 0.047),
        Color(red: 0.486, green: 0.227, blue: 0.929),
        Color(red: 0.859, green: 0.153, blue: 0.467),
    ]
    private static let othersColor = Color(white: 0.75)

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(group.title).font(.system(size: 34, weight: .semibold)).tracking(-1)
                    Text("\(metrics.members.count) members · \(metrics.messageCount.formatted()) messages · \(metrics.conversations.formatted()) conversations")
                        .foregroundStyle(Theme.secondary)
                }

                if !metrics.observations.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(metrics.observations, id: \.self) { observation in
                            HStack(alignment: .firstTextBaseline, spacing: 10) {
                                Circle().fill(Theme.accent).frame(width: 7, height: 7)
                                Text(sentence(for: observation)).font(.system(size: 16))
                            }
                        }
                    }
                }

                HStack(alignment: .top, spacing: 20) {
                    Donut(title: "Who talks", slices: slices(\.messages))
                    Donut(title: "Who starts conversations", slices: slices(\.starts))
                }

                memberTable
                if let loadOpenLoops {
                    OpenLoopsSection(person: group, load: loadOpenLoops)
                }
                VolumeChart(weeks: metrics.weekly, others: "Everyone else")
            }
            .padding(36)
            .frame(maxWidth: 1000, alignment: .leading)
        }
        .frame(maxWidth: .infinity)
        .background(Theme.surface)
    }

    private var memberTable: some View {
        Grid(alignment: .leading, horizontalSpacing: 20, verticalSpacing: 0) {
            GridRow {
                ForEach(["Member", "Messages", "Share", "Started", "Responds in", "Last active"], id: \.self) { header in
                    Text(header).font(.system(size: 12)).foregroundStyle(Theme.muted)
                }
            }
            .padding(.bottom, 10)
            ForEach(metrics.members, id: \.handle) { member in
                Divider().overlay(Theme.hairline).gridCellUnsizedAxes(.horizontal)
                GridRow {
                    HStack(spacing: 8) {
                        Circle().fill(color(for: member.handle)).frame(width: 8, height: 8)
                        Text(group.memberName(member.handle)).font(.system(size: 14, weight: .medium)).lineLimit(1)
                    }
                    Text(member.messages.formatted()).font(Theme.mono(13))
                    ShareBar(share: member.share, color: color(for: member.handle))
                    Text(member.starts.formatted()).font(Theme.mono(13))
                    Text(Elapsed.short(member.medianResponse)).font(Theme.mono(13))
                    Text(member.lastActive.map { Elapsed.ago($0) } ?? "never").font(Theme.mono(13)).foregroundStyle(Theme.secondary)
                }
                .padding(.vertical, 10)
            }
        }
        .padding(22)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.hairline))
    }

    /// Top five members by the metric, the rest folded into Others so slices stay readable.
    private func slices(_ value: KeyPath<GroupMetrics.Member, Int>) -> [Donut.Slice] {
        let ranked = metrics.members.filter { $0[keyPath: value] > 0 }.sorted { $0[keyPath: value] > $1[keyPath: value] }
        var slices = ranked.prefix(5).map {
            Donut.Slice(label: group.memberName($0.handle), value: $0[keyPath: value], color: color(for: $0.handle))
        }
        let rest = ranked.dropFirst(5).reduce(0) { $0 + $1[keyPath: value] }
        if rest > 0 { slices.append(Donut.Slice(label: "Others", value: rest, color: Self.othersColor)) }
        return slices
    }

    private func color(for handle: String?) -> Color {
        guard let handle else { return Theme.ink }
        let others = metrics.members.compactMap(\.handle)
        guard let index = others.firstIndex(of: handle), index < Self.palette.count else { return Self.othersColor }
        return Self.palette[index]
    }

    private func sentence(for observation: GroupMetrics.Observation) -> String {
        let percent = FloatingPointFormatStyle<Double>.Percent().precision(.fractionLength(0))
        switch observation {
        case .carries(let handle, let share):
            let name = group.memberName(handle)
            return "\(name) \(handle == nil ? "send" : "sends") \(share.formatted(percent)) of the messages."
        case .drifting(let handle, let usual, let recent):
            let name = group.memberName(handle)
            return "\(name) usually \(handle == nil ? "send" : "sends") \(usual.formatted(percent)) of messages; lately it’s \(recent.formatted(percent))."
        case .goneQuiet(let handle, let days):
            return "\(group.memberName(handle)) \(handle == nil ? "haven’t" : "hasn’t") posted in \(days) days while the group kept talking."
        }
    }
}

private struct Donut: View {
    struct Slice: Identifiable {
        let label: String
        let value: Int
        let color: Color
        var id: String { label }
    }

    let title: String
    let slices: [Slice]

    private var total: Int { slices.reduce(0) { $0 + $1.value } }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(title).font(.system(size: 15, weight: .semibold))
            HStack(spacing: 24) {
                Chart(slices) { slice in
                    SectorMark(angle: .value("Share", slice.value), innerRadius: .ratio(0.62), angularInset: 1.5)
                        .foregroundStyle(slice.color)
                        .cornerRadius(3)
                }
                .frame(width: 140, height: 140)
                .accessibilityLabel(title)

                VStack(alignment: .leading, spacing: 8) {
                    ForEach(slices) { slice in
                        HStack(spacing: 8) {
                            Circle().fill(slice.color).frame(width: 8, height: 8)
                            Text(slice.label).font(.system(size: 13)).lineLimit(1)
                            Spacer(minLength: 8)
                            Text((Double(slice.value) / Double(max(total, 1))).formatted(.percent.precision(.fractionLength(0))))
                                .font(Theme.mono(12))
                                .foregroundStyle(Theme.secondary)
                        }
                    }
                }
            }
        }
        .padding(22)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.hairline))
    }
}

private struct ShareBar: View {
    let share: Double
    let color: Color

    var body: some View {
        HStack(spacing: 8) {
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(Theme.hairline)
                    Capsule().fill(color).frame(width: proxy.size.width * share)
                }
            }
            .frame(width: 80, height: 6)
            Text(share.formatted(.percent.precision(.fractionLength(0)))).font(Theme.mono(12)).foregroundStyle(Theme.secondary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(share.formatted(.percent.precision(.fractionLength(0)))) of messages")
    }
}

func sampleGroup() -> PersonHealth {
    let (jp, carlos, dane, bill) = ("+15550000001", "+15550000002", "+15550000003", "+15550000004")
    let turns: [String?] = [jp, jp, carlos, nil, jp, dane, jp, carlos, jp, nil, jp, carlos]
    var messages: [Message] = []
    for day in stride(from: 300, through: 2, by: -3) {
        let start = Date.now.addingTimeInterval(-Double(day) * 86_400)
        let rotated = Array(turns.dropFirst(day % 5) + turns.prefix(day % 5))
        for (i, sender) in rotated.enumerated() where !(day < 60 && sender == carlos) {
            let id = Int64(messages.count + 1)
            messages.append(Message(id: id, guid: "\(id)", chatID: 50, sender: sender, isFromMe: sender == nil,
                                    date: start.addingTimeInterval(Double(i) * 180), text: "x", textSource: .column, kind: .text))
        }
    }
    let participants = [jp, carlos, dane, bill]
    let chat = Chat(id: 50, identifier: "chat50", displayName: "Climbing crew", isGroup: true, participants: participants,
                    messageCount: messages.count, lastMessageDate: messages.last?.date)
    var group = PersonHealth(conversation: Conversation(chats: [chat]), title: "Climbing crew",
                             health: .group(GroupMetrics.compute(messages, participants: participants)))
    group.memberNames = [jp: "Jp Arde", carlos: "Carlos Azucena", dane: "Dane Phoenix", bill: "Bill Milliken"]
    return group
}

#Preview {
    let group = sampleGroup()
    if case .group(let metrics) = group.health {
        GroupHealthDetail(group: group, metrics: metrics)
            .frame(width: 1000, height: 1100)
            .foregroundStyle(Theme.ink)
            .preferredColorScheme(.light)
    }
}
