import IonshipCore
import SwiftUI

struct ChooseView: View {
    @Binding var picker: ConversationPicker
    let onImport: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Choose conversations").font(.system(size: 28, weight: .semibold)).tracking(-0.8)
                Text("Your busiest threads are selected. Add or remove anyone — you can change this later.")
                    .foregroundStyle(Theme.secondary)
            }

            VStack(spacing: 0) {
                HStack(spacing: 12) {
                    TextField("Filter people and groups", text: $picker.filter)
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 320)
                    Spacer()
                    Text("\(picker.selected.count) SELECTED · \(picker.selectedMessageCount.formatted()) MESSAGES")
                        .font(Theme.mono(12))
                        .foregroundStyle(Theme.muted)
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 14)
                Divider().overlay(Theme.hairline)

                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(picker.visible) { conversation in
                            ConversationRow(conversation: conversation, title: picker.title(for: conversation),
                                            isSelected: picker.isSelected(conversation)) {
                                picker.toggle(conversation.id)
                            }
                                .padding(.horizontal, 18)
                            Divider().overlay(Theme.hairline)
                        }
                    }
                }
            }
            .background(Theme.surface, in: .rect(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.hairline))

            HStack {
                Label("Messages stay on this Mac. Nothing is sent anywhere during import.", systemImage: "lock")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.secondary)
                Spacer()
                Button("Import \(picker.selected.count) conversations", action: onImport)
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(picker.selected.isEmpty)
            }
        }
        .padding(32)
        .frame(maxWidth: 1180)
    }
}

private struct ConversationRow: View {
    let conversation: Conversation
    let title: String
    let isSelected: Bool
    let toggle: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            Toggle(title, isOn: Binding(get: { isSelected }, set: { _ in toggle() }))
                .toggleStyle(.checkbox)
                .labelsHidden()
                .tint(Theme.accent)
            Text(initials)
                .font(.system(size: 12, weight: .medium))
                .frame(width: 32, height: 32)
                .background(Color(white: 0.91), in: .circle)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.system(size: 14, weight: .medium)).lineLimit(1)
                Text(subtitle)
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.muted)
                    .lineLimit(1)
            }
            Spacer()
            Text(conversation.messageCount.formatted())
                .font(Theme.mono(12))
                .foregroundStyle(Theme.secondary)
                .frame(width: 90, alignment: .trailing)
            Text(conversation.lastMessageDate.map { $0.formatted(.dateTime.month(.abbreviated).year()) } ?? "")
                .font(Theme.mono(12))
                .foregroundStyle(Theme.muted)
                .frame(width: 90, alignment: .trailing)
        }
        .padding(.vertical, 10)
        .contentShape(.rect)
        .onTapGesture(perform: toggle)
    }

    private var subtitle: String {
        if conversation.isGroup { return "Group · \(conversation.participants.count) people" }
        let handles = conversation.participants.isEmpty ? [conversation.identifier] : conversation.participants
        if title == handles.first { return "Not in Contacts" }
        return handles.count == 1 ? handles[0] : "\(handles[0]) +\(handles.count - 1) more"
    }

    private var initials: String {
        let letters = title.split(separator: " ").prefix(2).compactMap(\.first).filter(\.isLetter)
        return letters.isEmpty ? "#" : String(letters).uppercased()
    }
}

#Preview {
    @Previewable @State var picker = samplePicker()
    ChooseView(picker: $picker) {}
        .frame(width: 1280, height: 800)
        .background(Theme.ground)
        .foregroundStyle(Theme.ink)
        .preferredColorScheme(.light)
}

private func samplePicker() -> ConversationPicker {
    var picker = ConversationPicker(chats: [
        Chat(id: 1, identifier: "+15550104471", displayName: nil, isGroup: false, participants: ["+15550104471"],
             messageCount: 11_804, lastMessageDate: .now),
        Chat(id: 2, identifier: "maya@example.com", displayName: nil, isGroup: false, participants: ["maya@example.com"],
             messageCount: 4_212, lastMessageDate: .now.addingTimeInterval(-86_400 * 3)),
        Chat(id: 3, identifier: "chat42", displayName: nil, isGroup: true,
             participants: ["+15550104471", "+15550100002", "+15550100003", "+15550100004"],
             messageCount: 3_977, lastMessageDate: .now.addingTimeInterval(-86_400 * 10)),
        Chat(id: 4, identifier: "+15550109932", displayName: nil, isGroup: false, participants: ["+15550109932"],
             messageCount: 418, lastMessageDate: .now.addingTimeInterval(-86_400 * 200)),
    ], preselect: 3)
    picker.names = HandleDirectory(entries: [
        .init(name: "Mom", phones: ["+1 (555) 010-4471"], emails: []),
        .init(name: "Maya Chen", phones: [], emails: ["maya@example.com"]),
        .init(name: "Dad", phones: ["555-010-0002"], emails: []),
    ])
    return picker
}
