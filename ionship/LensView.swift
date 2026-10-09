import IonshipCore
import SwiftUI

/// The design's right-hand panel: what the last ninety days say about this relationship.
struct LensView: View {
    let model: AppModel
    let person: PersonHealth

    @State private var loops: OpenLoops?
    @State private var recalled: MemoryResult?
    @State private var topics: [String]?

    var body: some View {
        let temperature = model.temperature(for: person)
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                HStack {
                    Text("Lens").font(.system(size: 13, weight: .semibold))
                    Spacer()
                    Text("LAST 90 DAYS").font(Theme.mono(11)).foregroundStyle(Theme.muted)
                }

                section("Temperature") {
                    HStack(alignment: .bottom) {
                        Text(temperature.label).font(.system(size: 20, weight: .semibold)).tracking(-0.4)
                        Spacer()
                        Sparkline(values: temperature.sparkline).frame(width: 120, height: 36)
                    }
                    Text(temperature.reason).font(.system(size: 13)).foregroundStyle(Theme.secondary)
                }

                stats

                section("Open loops") {
                    switch loops {
                    case nil:
                        ProgressView().controlSize(.small)
                    case .judged(let items) where items.isEmpty, .unjudged(let items) where items.isEmpty:
                        Text("Nothing unfinished.").font(.system(size: 13)).foregroundStyle(Theme.secondary)
                    case .judged(let items), .unjudged(let items):
                        ForEach(items) { loop in
                            HStack(alignment: .top, spacing: 10) {
                                Circle().strokeBorder(loop.isConfirmed ? Theme.accent : Theme.muted, lineWidth: 1.5)
                                    .frame(width: 8, height: 8).padding(.top, 6)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(loop.task).lineLimit(2)
                                    Text("You promised · \(loop.date.formatted(.dateTime.month(.abbreviated).day()))\(loop.isConfirmed ? "" : " · not sure")")
                                        .font(.system(size: 12)).foregroundStyle(Theme.muted)
                                }
                            }
                        }
                    }
                }

                if let recalled {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Recalled").font(.system(size: 12, weight: .medium)).foregroundStyle(Theme.muted)
                        Text(recalled.moment.text).font(.system(size: 13)).lineLimit(5)
                        Text("FROM \(recalled.moment.start.formatted(.dateTime.month(.abbreviated).day()).uppercased()) · \(String(format: "%.2f", recalled.score)) MATCH")
                            .font(Theme.mono(11)).foregroundStyle(Theme.muted)
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(red: 0.949, green: 0.949, blue: 0.937), in: .rect(cornerRadius: 10))
                }

                if let topics, !topics.isEmpty {
                    section("Recurring topics") {
                        FlowLayout(spacing: 6) {
                            ForEach(topics, id: \.self) { topic in
                                Text(topic).font(.system(size: 12))
                                    .padding(.horizontal, 9).padding(.vertical, 4)
                                    .background(Theme.surface, in: .capsule)
                                    .overlay(Capsule().stroke(Theme.hairline))
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 22)
            .padding(.vertical, 20)
        }
        .frame(width: 340)
        .background(Theme.ground)
        .task(id: person.id) {
            loops = nil
            recalled = nil
            topics = nil
            async let loopsResult = model.openLoops(for: person)
            async let recallResult = model.recalled(for: person)
            loops = await loopsResult
            recalled = await recallResult
            topics = await model.topics(for: person)
        }
    }

    @ViewBuilder private var stats: some View {
        let metrics = model.lensMetrics(for: person)
        let percent = FloatingPointFormatStyle<Double>.Percent().precision(.fractionLength(0))
        let them = person.conversation.isGroup ? "Others" : "They"
        Grid(horizontalSpacing: 1, verticalSpacing: 1) {
            GridRow {
                stat("You start", metrics.youStartShare.map { $0.formatted(percent) } ?? "—")
                stat("\(them) start", metrics.youStartShare.map { (1 - $0).formatted(percent) } ?? "—")
            }
            GridRow {
                stat("Your reply", Elapsed.short(metrics.yourMedianReply))
                stat(person.conversation.isGroup ? "Their replies" : "Their reply", Elapsed.short(metrics.theirMedianReply))
            }
        }
        .background(Theme.hairline)
        .clipShape(.rect(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.hairline))
    }

    private func stat(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.system(size: 12)).foregroundStyle(Theme.muted)
            Text(value).font(Theme.mono(17).weight(.medium))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(Theme.surface)
    }

    private func section(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.system(size: 12, weight: .medium)).foregroundStyle(Theme.muted)
            content()
        }
    }
}

private struct Sparkline: View {
    let values: [Double]

    var body: some View {
        Canvas { context, size in
            guard values.count > 1, let top = values.max(), top > 0 else { return }
            var path = Path()
            for (index, value) in values.enumerated() {
                let point = CGPoint(x: size.width * CGFloat(index) / CGFloat(values.count - 1),
                                    y: size.height - 2 - (size.height - 4) * CGFloat(value / top))
                index == 0 ? path.move(to: point) : path.addLine(to: point)
            }
            context.stroke(path, with: .color(Theme.accent), style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
        }
        .accessibilityLabel("Messages per week over the last twelve weeks")
    }
}

/// Wraps chips onto as many lines as needed.
struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(subviews, width: proposal.width ?? .infinity)
        return CGSize(width: proposal.width ?? rows.map(\.width).max() ?? 0, height: rows.last.map { $0.y + $0.height } ?? 0)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for row in arrange(subviews, width: bounds.width) {
            var x = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: bounds.minY + row.y), proposal: .unspecified)
                x += size.width + spacing
            }
        }
    }

    private func arrange(_ subviews: Subviews, width: CGFloat) -> [(indices: [Int], y: CGFloat, width: CGFloat, height: CGFloat)] {
        var rows: [(indices: [Int], y: CGFloat, width: CGFloat, height: CGFloat)] = []
        var current: [Int] = [], x: CGFloat = 0, y: CGFloat = 0, height: CGFloat = 0
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            if x > 0, x + size.width > width {
                rows.append((current, y, x - spacing, height))
                y += height + spacing
                current = []; x = 0; height = 0
            }
            current.append(index)
            x += size.width + spacing
            height = max(height, size.height)
        }
        if !current.isEmpty { rows.append((current, y, x - spacing, height)) }
        return rows
    }
}
