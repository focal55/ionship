import IonshipCore
import SwiftUI

struct ThreadView: View {
    let person: PersonHealth
    let messages: [Message]

    @State private var window = 400

    private static let dayFormat = Date.FormatStyle().weekday(.abbreviated).month(.abbreviated).day()

    var body: some View {
        thread(messages)
            .background(Theme.surface)
            .onChange(of: person.id) { window = 400 }
    }

    private func thread(_ messages: [Message]) -> some View {
        let shown = Array(messages.suffix(window))
        let items = ThreadTimeline.items(for: shown, isGroup: person.conversation.isGroup)
        return ScrollView {
            LazyVStack(spacing: 6) {
                if shown.count < messages.count {
                    Button("Show earlier messages") { window += 400 }
                        .buttonStyle(.plain)
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.accent)
                        .padding(.vertical, 12)
                }
                ForEach(items) { item in
                    switch item.kind {
                    case .day:
                        Text(item.date.formatted(Self.dayFormat).uppercased())
                            .font(Theme.mono(11))
                            .foregroundStyle(Theme.muted)
                            .padding(.top, 18)
                            .padding(.bottom, 6)
                    case .message:
                        if let message = item.message {
                            Bubble(message: message, sender: item.showsSender ? person.memberName(message.sender) : nil)
                        }
                    }
                }
            }
            .padding(.horizontal, 36)
            .padding(.vertical, 24)
            .frame(maxWidth: 820)
            .frame(maxWidth: .infinity)
        }
        .defaultScrollAnchor(.bottom)
    }
}

private struct Bubble: View {
    let message: Message
    let sender: String?

    var body: some View {
        VStack(alignment: message.isFromMe ? .trailing : .leading, spacing: 3) {
            if let sender {
                Text(sender).font(.system(size: 11, weight: .medium)).foregroundStyle(Theme.muted).padding(.horizontal, 4)
            }
            content
                .font(.system(size: 14))
                .padding(.horizontal, 13)
                .padding(.vertical, 8)
                .foregroundStyle(message.isFromMe ? .white : Theme.ink)
                .background(message.isFromMe ? Theme.ink : Color(red: 0.949, green: 0.949, blue: 0.937),
                            in: .rect(cornerRadius: 16))
                .textSelection(.enabled)
                .help(message.date.formatted(date: .abbreviated, time: .shortened))
        }
        .frame(maxWidth: 560, alignment: message.isFromMe ? .trailing : .leading)
        .frame(maxWidth: .infinity, alignment: message.isFromMe ? .trailing : .leading)
    }

    @ViewBuilder private var content: some View {
        if let text = message.text {
            Text(text)
        } else {
            Label("Attachment", systemImage: "paperclip").italic()
        }
    }
}

#Preview {
    let person = sampleGroup()
    ThreadView(person: person, messages: {
        let senders: [String?] = ["+15550000001", "+15550000001", nil, "+15550000002", nil, "+15550000001"]
        let lines = ["Saturday at Brooklyn Boulders?", "I can drive", "In. 9am?", "9 is early lol", "Fine, 10", "10 works"]
        return zip(senders, lines).enumerated().map { index, pair in
            Message(id: Int64(index), guid: "\(index)", chatID: 50, sender: pair.0, isFromMe: pair.0 == nil,
                    date: .now.addingTimeInterval(Double(index - 6) * 900), text: pair.1, textSource: .column, kind: .text)
        }
    }())
    .frame(width: 800, height: 600)
    .preferredColorScheme(.light)
}
