import SwiftUI

struct OpenLoopsSection: View {
    let person: PersonHealth
    let load: (PersonHealth) async -> OpenLoops

    @State private var loops: OpenLoops?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text("Open loops").font(.system(size: 15, weight: .semibold))
                Spacer()
                Text("LAST 60 DAYS · ON THIS MAC").font(Theme.mono(11)).foregroundStyle(Theme.muted)
            }
            switch loops {
            case nil:
                HStack(spacing: 10) {
                    ProgressView().controlSize(.small)
                    Text("Reading your recent promises…").foregroundStyle(Theme.secondary)
                }
            case .judged(let items) where items.isEmpty:
                Text("Nothing you promised looks unfinished.").foregroundStyle(Theme.secondary)
            case .judged(let items):
                ForEach(items) { row($0) }
            case .unjudged(let items):
                Text("Apple Intelligence is off, so these are possible promises that haven’t been checked.")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.secondary)
                ForEach(items) { row($0) }
            }
        }
        .padding(22)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.hairline))
        .task(id: person.id) {
            loops = nil
            loops = await load(person)
        }
    }

    private func row(_ loop: OpenLoop) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Circle()
                .strokeBorder(loop.isConfirmed ? Theme.accent : Theme.muted, lineWidth: 1.5)
                .frame(width: 10, height: 10)
                .padding(.top, 5)
            VStack(alignment: .leading, spacing: 2) {
                Text(loop.task).font(.system(size: 15)).lineLimit(2)
                Text("You said this \(Elapsed.ago(loop.date))\(loop.isConfirmed ? "" : " · not sure")")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.muted)
            }
        }
    }
}
