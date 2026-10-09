import AppKit
import IonshipCore
import SwiftUI

struct DraftPanel: View {
    let person: PersonHealth
    let draft: (PersonHealth, String) async -> DraftResult
    var initialSteer = ""

    @State private var steer = ""
    @State var result: DraftResult?
    @State private var working = false
    @State private var copied: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let result {
                switch result {
                case .drafts(let drafts):
                    ForEach(drafts, id: \.text) { card(label: $0.label, text: $0.text) }
                case .unavailable:
                    note("Drafting needs Apple Intelligence, which is off on this Mac.")
                case .blocked:
                    note("Apple’s on-device model declined to draft for this conversation. Try steering it differently.")
                }
            }
            HStack(spacing: 8) {
                TextField("Steer it, for example: apologize for the delay", text: $steer)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(generate)
                Button(action: generate) {
                    if working { ProgressView().controlSize(.small) } else { Text(result == nil ? "Draft a reply" : "Redraft") }
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(working)
            }
            Text("Drafted on this Mac. ionship never sends messages for you.")
                .font(.system(size: 11))
                .foregroundStyle(Theme.muted)
        }
        .padding(.horizontal, 36)
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity)
        .background(Theme.ground)
        .onChange(of: person.id) { result = nil; steer = "" }
        .onAppear {
            guard result == nil else { return }
            steer = initialSteer
            generate()
        }
    }

    private func generate() {
        guard !working else { return }
        working = true
        Task {
            result = await draft(person, steer.trimmingCharacters(in: .whitespaces))
            working = false
        }
    }

    private func card(label: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(label).font(Theme.mono(10)).tracking(0.6).foregroundStyle(Theme.muted)
                Text(text).font(.system(size: 14)).textSelection(.enabled)
            }
            Spacer()
            Button(copied == text ? "Copied" : "Copy") { copy(text) }
            Button("Open in Messages") {
                copy(text)
                openMessages()
            }
            .help("Copies the draft and opens Messages so you can paste and send it yourself")
        }
        .padding(14)
        .background(Theme.surface, in: .rect(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.hairline))
    }

    private func note(_ text: String) -> some View {
        Text(text).font(.system(size: 13)).foregroundStyle(Theme.secondary)
    }

    private func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        copied = text
    }

    private func openMessages() {
        let participants = person.conversation.participants
        if !person.conversation.isGroup, participants.count == 1,
           let handle = participants[0].addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
           let url = URL(string: "imessage:\(handle)") {
            NSWorkspace.shared.open(url)
        } else if let messages = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.MobileSMS") {
            NSWorkspace.shared.openApplication(at: messages, configuration: .init())
        }
    }
}

#Preview {
    DraftPanel(person: sampleGroup(), draft: { _, _ in .unavailable }, result: .drafts([
        ("DIRECT", "tonight, sorry for the wait"),
        ("WARM", "found them! sending tonight, and good luck thursday"),
        ("PLAYFUL", "the photos were hiding from you specifically. freeing them tonight"),
    ]))
    .frame(width: 900)
    .preferredColorScheme(.light)
}
