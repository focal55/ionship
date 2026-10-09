import IonshipCore
import SwiftUI

struct ThreadView: View {
    let model: AppModel
    let person: PersonHealth
    var focus: Int64?
    let onDraft: (String) -> Void

    @State private var window = 400
    @State private var loops: OpenLoops?
    @State private var steer = ""

    private static let dayFormat = Date.FormatStyle().weekday(.abbreviated).month(.abbreviated).day()

    private var messages: [Message] { model.threads[person.id] ?? [] }

    private var openLoops: [OpenLoop] {
        switch loops {
        case .judged(let items), .unjudged(let items): items
        case nil: []
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                thread
                    .onChange(of: person.id) { window = 400 }
                    .task(id: focus) {
                        guard let focus, let index = messages.firstIndex(where: { $0.id == focus }) else { return }
                        window = max(window, messages.count - index + 20)
                        try? await Task.sleep(for: .milliseconds(100))
                        proxy.scrollTo("msg-\(focus)", anchor: .center)
                    }
            }
            Divider().overlay(Color(red: 0.937, green: 0.937, blue: 0.925))
            composer
        }
        .background(Theme.surface)
        .task(id: person.id) {
            loops = nil
            loops = await model.openLoops(for: person)
        }
    }

    private var thread: some View {
        let shown = Array(messages.suffix(window))
        let items = ThreadTimeline.items(for: shown, isGroup: person.conversation.isGroup)
        let notes = Dictionary(openLoops.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return ScrollView {
            LazyVStack(spacing: 10) {
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
                            .padding(.top, 14)
                            .padding(.bottom, 8)
                    case .message:
                        if let message = item.message {
                            Bubble(message: message, sender: item.showsSender ? person.memberName(message.sender) : nil,
                                   note: notes[message.id], isFocused: message.id == focus)
                                .id(item.id)
                        }
                    }
                }
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 24)
        }
        .defaultScrollAnchor(.bottom)
    }

    private var composer: some View {
        VStack(alignment: .leading, spacing: 10) {
            FlowLayout(spacing: 8) {
                ForEach(Array(openLoops.filter(\.isConfirmed).prefix(2).enumerated()), id: \.element.id) { index, loop in
                    chip("Draft: \(loop.task.prefix(1).lowercased() + loop.task.dropFirst())", highlighted: index == 0) {
                        onDraft("Follow through on: \(loop.task)")
                    }
                }
                chip("Draft: reply to the latest", highlighted: !openLoops.contains(where: \.isConfirmed)) { onDraft("") }
            }
            HStack(spacing: 10) {
                TextField("Write, or describe what you want to say…", text: $steer)
                    .textFieldStyle(.plain)
                    .onSubmit(draft)
                Button("Draft", action: draft)
                    .buttonStyle(AccentButtonStyle())
            }
            .padding(.leading, 14)
            .padding(.trailing, 8)
            .frame(minHeight: 48)
            .background(Color(red: 0.984, green: 0.984, blue: 0.980), in: .rect(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.hairline))
        }
        .padding(.horizontal, 28)
        .padding(.top, 16)
        .padding(.bottom, 24)
    }

    private func draft() {
        onDraft(steer.trimmingCharacters(in: .whitespaces))
        steer = ""
    }

    private func chip(_ title: String, highlighted: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 13))
                .lineLimit(1)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .foregroundStyle(highlighted ? Theme.accent : Theme.secondary)
                .background(highlighted ? Theme.accentWash : .clear, in: .capsule)
                .overlay(Capsule().stroke(highlighted ? Theme.accentBorder : Theme.hairline))
        }
        .buttonStyle(.plain)
    }
}

private struct Bubble: View {
    let message: Message
    let sender: String?
    let note: OpenLoop?
    var isFocused = false

    var body: some View {
        VStack(alignment: message.isFromMe ? .trailing : .leading, spacing: 4) {
            if let sender {
                Text(sender).font(.system(size: 11, weight: .medium)).foregroundStyle(Theme.muted).padding(.horizontal, 4)
            }
            content
                .font(.system(size: 14))
                .padding(.horizontal, 13)
                .padding(.vertical, 9)
                .foregroundStyle(message.isFromMe ? .white : Theme.ink)
                .background(message.isFromMe ? Theme.ink : Color(red: 0.949, green: 0.949, blue: 0.937), in: shape)
                .overlay(shape.stroke(Theme.accent, lineWidth: isFocused ? 2 : 0).padding(-3))
                .textSelection(.enabled)
                .help(message.date.formatted(date: .abbreviated, time: .shortened))
            if let note {
                HStack(spacing: 6) {
                    Circle().fill(Theme.accent).frame(width: 6, height: 6)
                    Text("Open loop · promised \(note.date.formatted(.dateTime.month(.abbreviated).day()))\(note.isConfirmed ? ", still open" : ", maybe")")
                }
                .font(.system(size: 12))
                .foregroundStyle(Theme.accent)
            }
        }
        .frame(maxWidth: 560, alignment: message.isFromMe ? .trailing : .leading)
        .frame(maxWidth: .infinity, alignment: message.isFromMe ? .trailing : .leading)
    }

    /// The design's bubble: rounded on three corners, tight on the corner nearest the speaker.
    private var shape: UnevenRoundedRectangle {
        message.isFromMe
            ? UnevenRoundedRectangle(topLeadingRadius: 16, bottomLeadingRadius: 16, bottomTrailingRadius: 4, topTrailingRadius: 16)
            : UnevenRoundedRectangle(topLeadingRadius: 16, bottomLeadingRadius: 4, bottomTrailingRadius: 16, topTrailingRadius: 16)
    }

    @ViewBuilder private var content: some View {
        if let text = message.text {
            Text(text)
        } else {
            Label("Attachment", systemImage: "paperclip").italic()
        }
    }
}

struct PersonMemoryView: View {
    let model: AppModel
    let person: PersonHealth
    let open: (MemoryResult) -> Void

    @State private var query = ""
    @State private var results: [MemoryResult]?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(Theme.muted)
                TextField("Search what you’ve talked about with \(person.title)", text: $query)
                    .textFieldStyle(.plain)
                    .onSubmit { Task { results = await model.searchMemory(query, in: person) } }
            }
            .padding(.horizontal, 12)
            .frame(height: 38)
            .background(Color(red: 0.984, green: 0.984, blue: 0.980), in: .rect(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.hairline))
            .padding(28)
            if let results {
                MemoryResultsView(query: query, results: results, open: open)
            } else {
                Text(model.memoryEnabled ? "Memory finds moments by meaning, not just words." : "Memory is off. Turn it on in the sidebar to search past conversations.")
                    .foregroundStyle(Theme.secondary)
                    .padding(.horizontal, 28)
                Spacer()
            }
        }
        .onChange(of: person.id) { query = ""; results = nil }
    }
}
