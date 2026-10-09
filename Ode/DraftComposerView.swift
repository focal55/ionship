import AppKit
import OdeCore
import SwiftUI

/// The design's draft composer: what you're replying to and the context used, three drafts
/// with how much they sound like you, and checks before you send.
struct DraftComposerView: View {
    let model: AppModel
    let person: PersonHealth
    let close: () -> Void

    @State var steer: String
    var initialResult: DraftResult?
    @State private var length = DraftLength.balanced
    @State private var result: DraftResult?
    @State private var working = false
    @State private var chosen: String?
    @State private var edits: [String: String] = [:]
    @State private var editing: String?
    @State private var recalled: MemoryResult?
    @State private var copied = false

    private var messages: [Message] { model.threads[person.id] ?? [] }
    private var style: WritingStyle { WritingStyle(of: messages) }

    private var drafts: [Draft] {
        if case .drafts(let drafts) = result { return drafts }
        return []
    }

    private var selectedText: String? {
        guard let id = chosen ?? drafts.first?.id, let draft = drafts.first(where: { $0.id == id }) else { return nil }
        return edits[id] ?? draft.text
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().overlay(Theme.hairline)
            HStack(spacing: 0) {
                context.frame(width: 330)
                Divider().overlay(Theme.hairline)
                composer.frame(maxWidth: .infinity)
                Divider().overlay(Theme.hairline)
                sendPanel.frame(width: 300)
            }
        }
        .background(Theme.ground)
        .task {
            recalled = await model.recalled(for: person)
            if let initialResult { result = initialResult } else { generate() }
        }
    }

    private var header: some View {
        HStack(spacing: 14) {
            Button(action: close) {
                Image(systemName: "chevron.left").frame(width: 32, height: 32)
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.hairline))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Back to thread")
            VStack(alignment: .leading, spacing: 0) {
                Text("Reply to \(person.title)").font(.system(size: 14, weight: .semibold))
                Text("Ode never sends · you send from Messages").font(.system(size: 12)).foregroundStyle(Theme.muted)
            }
            Spacer()
        }
        .padding(.horizontal, 20)
        .frame(height: 56)
    }

    private var context: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                label("Replying to")
                ForEach(messages.filter { $0.kind == .text }.suffix(3)) { message in
                    Text(message.text ?? "")
                        .font(.system(size: 14))
                        .padding(.horizontal, 13).padding(.vertical, 9)
                        .foregroundStyle(message.isFromMe ? .white : Theme.ink)
                        .background(message.isFromMe ? Theme.ink : Theme.surface, in: .rect(cornerRadius: 16))
                        .overlay(RoundedRectangle(cornerRadius: 16).stroke(message.isFromMe ? .clear : Theme.hairline))
                        .frame(maxWidth: 260, alignment: message.isFromMe ? .trailing : .leading)
                        .frame(maxWidth: .infinity, alignment: message.isFromMe ? .trailing : .leading)
                }
                label("Context used").padding(.top, 18)
                ForEach(model.confirmedLoops(for: person)) { loop in
                    contextCard(loop.task, "OPEN LOOP · \(Elapsed.ago(loop.date).uppercased())")
                }
                if let recalled {
                    contextCard(recalled.moment.text, "MEMORY · \(recalled.moment.start.formatted(.dateTime.month(.abbreviated).day()).uppercased())")
                }
                if let summary = style.summary {
                    contextCard(summary, "YOUR STYLE WITH \(person.title.uppercased())")
                }
            }
            .padding(22)
        }
    }

    private var composer: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                HStack {
                    Text("Three ways to say it").font(.system(size: 22, weight: .semibold)).tracking(-0.4)
                    Spacer()
                    HStack(spacing: 0) {
                        ForEach(DraftLength.allCases, id: \.self) { option in
                            Button { length = option; generate() } label: {
                                Text(option.rawValue)
                                    .padding(.horizontal, 12).padding(.vertical, 6)
                                    .foregroundStyle(length == option ? Theme.ink : Theme.secondary)
                                    .background(length == option ? Theme.surface : .clear, in: .rect(cornerRadius: 7))
                                    .shadow(color: length == option ? .black.opacity(0.08) : .clear, radius: 1, y: 1)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(3)
                    .background(Color(red: 0.949, green: 0.949, blue: 0.937), in: .rect(cornerRadius: 9))
                }

                switch result {
                case nil:
                    HStack(spacing: 10) { ProgressView().controlSize(.small); Text("Drafting on this Mac…").foregroundStyle(Theme.secondary) }
                case .unavailable:
                    Text("Drafting needs Apple Intelligence, which is off on this Mac.").foregroundStyle(Theme.secondary)
                case .blocked:
                    Text("Apple’s on-device model declined to draft for this conversation. Try steering it differently.").foregroundStyle(Theme.secondary)
                case .drafts:
                    ForEach(drafts) { card($0) }
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Steer it").font(.system(size: 12, weight: .medium)).foregroundStyle(Theme.muted)
                    HStack(spacing: 8) {
                        TextField("e.g. apologize for the delay, mention the wedding", text: $steer)
                            .textFieldStyle(.plain)
                            .onSubmit(generate)
                        Button(working ? "Drafting…" : "Redraft", action: generate)
                            .buttonStyle(AccentButtonStyle())
                            .disabled(working)
                    }
                    .padding(.leading, 14).padding(.trailing, 8)
                    .frame(minHeight: 48)
                    .background(Color(red: 0.984, green: 0.984, blue: 0.980), in: .rect(cornerRadius: 12))
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.hairline))
                }
            }
            .padding(.horizontal, 36)
            .padding(.vertical, 28)
        }
        .background(Theme.surface)
    }

    private func card(_ draft: Draft) -> some View {
        let text = edits[draft.id] ?? draft.text
        let isChosen = (chosen ?? drafts.first?.id) == draft.id
        let percent = style.sampleSize >= 5 ? "SOUNDS LIKE YOU \(Int((style.match(text) * 100).rounded()))%" : ""
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(draft.label).font(Theme.mono(11)).tracking(0.6).foregroundStyle(Theme.muted)
                Spacer()
                Text(percent).font(Theme.mono(11)).foregroundStyle(Theme.muted)
            }
            if editing == draft.id {
                TextEditor(text: Binding(get: { edits[draft.id] ?? draft.text }, set: { edits[draft.id] = $0 }))
                    .font(.system(size: 16))
                    .frame(minHeight: 60)
                    .scrollContentBackground(.hidden)
            } else {
                Text(text).font(.system(size: 16)).textSelection(.enabled)
            }
            HStack {
                Text(draft.why).font(.system(size: 12)).foregroundStyle(Theme.accent)
                Spacer()
                Button(editing == draft.id ? "Done" : "Edit") { editing = editing == draft.id ? nil : draft.id }
                    .buttonStyle(.bordered)
                Button("Use") { chosen = draft.id }
                    .buttonStyle(CompactPrimaryButtonStyle())
            }
        }
        .padding(.horizontal, 20).padding(.vertical, 18)
        .background(isChosen ? Theme.surface : Color(red: 0.984, green: 0.984, blue: 0.980), in: .rect(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(isChosen ? Theme.accent : Theme.hairline, lineWidth: isChosen ? 1.5 : 1))
        .contentShape(.rect)
        .onTapGesture { chosen = draft.id }
    }

    private var sendPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            label("Before you send")
            if let text = selectedText {
                let lastIncoming = messages.last(where: { !$0.isFromMe && $0.kind == .text })?.text
                ForEach(DraftChecks.evaluate(text, style: style, openLoops: model.confirmedLoops(for: person).map(\.task),
                                             lastIncoming: lastIncoming), id: \.self) { check in
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: check.ok ? "checkmark" : "exclamationmark")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(check.ok ? Theme.positive : Theme.warning)
                            .frame(width: 16)
                            .padding(.top, 2)
                        Text(check.text).font(.system(size: 13))
                    }
                }
            } else {
                Text("Pick a draft to see checks.").font(.system(size: 13)).foregroundStyle(Theme.secondary)
            }
            Spacer()
            Button { sendViaMessages() } label: {
                Text(copied ? "Copied — paste in Messages" : "Send via Messages").frame(maxWidth: .infinity)
            }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(selectedText == nil)
                .help("Copies the draft and opens the conversation in Messages. You press send.")
            Button("Copy to clipboard") { if let text = selectedText { copy(text) } }
                .buttonStyle(.plain)
                .foregroundStyle(Theme.secondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .disabled(selectedText == nil)
        }
        .padding(22)
    }

    private func label(_ text: String) -> some View {
        Text(text.uppercased()).font(.system(size: 11, weight: .medium)).tracking(0.9).foregroundStyle(Theme.muted)
    }

    private func contextCard(_ text: String, _ meta: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(text).font(.system(size: 13)).lineLimit(4)
            Text(meta).font(Theme.mono(11)).foregroundStyle(Theme.muted)
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surface, in: .rect(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color(red: 0.925, green: 0.925, blue: 0.910)))
    }

    private func generate() {
        guard !working else { return }
        working = true
        edits = [:]
        editing = nil
        chosen = nil
        Task {
            result = await model.draftReply(for: person, steer: steer.trimmingCharacters(in: .whitespaces), length: length)
            working = false
        }
    }

    private func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        copied = true
    }

    private func sendViaMessages() {
        guard let text = selectedText else { return }
        copy(text)
        let participants = person.conversation.participants
        if !person.conversation.isGroup, participants.count == 1,
           let handle = participants[0].addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
           let url = URL(string: "imessage:\(handle)") {
            NSWorkspace.shared.open(url)
        } else if let messagesApp = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.MobileSMS") {
            NSWorkspace.shared.openApplication(at: messagesApp, configuration: .init())
        }
    }
}

#Preview {
    let model = AppModel.preview()
    DraftComposerView(model: model, person: model.people[0], close: {}, steer: "", initialResult: .drafts([
        Draft(label: "DIRECT", text: "found them! sending the whole album tonight, sorry it took a week", why: "Closes the photos loop"),
        Draft(label: "WARM", text: "okay I owe you. album tonight, and good luck thursday, tell me everything after", why: "Closes loop and asks about round two"),
        Draft(label: "PLAYFUL", text: "the photos were hiding from you specifically. freeing them tonight", why: "Matches her tone"),
    ]))
    .frame(width: 1160, height: 900)
    .foregroundStyle(Theme.ink)
    .preferredColorScheme(.light)
}
