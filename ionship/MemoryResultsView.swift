import IonshipCore
import SwiftUI

struct MemoryResultsView: View {
    let query: String
    let results: [MemoryResult]
    let open: (MemoryResult) -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("“\(query)”").font(.system(size: 28, weight: .semibold)).tracking(-0.8)
                    Text(results.isEmpty ? "Nothing in memory matches yet." : "\(results.count) \(results.count == 1 ? "moment" : "moments") from your conversations")
                        .foregroundStyle(Theme.secondary)
                }
                ForEach(results) { result in
                    Button { open(result) } label: {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text(result.title).font(.system(size: 13, weight: .semibold))
                                Spacer()
                                Text(result.moment.start.formatted(date: .abbreviated, time: .omitted))
                                    .font(Theme.mono(11))
                                    .foregroundStyle(Theme.muted)
                            }
                            Text(result.moment.text)
                                .font(.system(size: 14))
                                .lineLimit(6)
                                .multilineTextAlignment(.leading)
                                .foregroundStyle(Theme.ink)
                        }
                        .padding(18)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.hairline))
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(36)
            .frame(maxWidth: 820, alignment: .leading)
        }
        .frame(maxWidth: .infinity)
        .background(Theme.surface)
    }
}

#Preview {
    MemoryResultsView(query: "big sur photos", results: [
        MemoryResult(moment: Moment(conversationID: 2, firstMessageID: 10, lastMessageID: 12, start: .now.addingTimeInterval(-9 * 86_400),
                                    end: .now, text: "Maya Chen: still waiting on those Big Sur photos\nYou: Yes yes. Tonight, promise"),
                     title: "Maya Chen"),
    ]) { _ in }
    .frame(width: 900, height: 500)
    .preferredColorScheme(.light)
}
