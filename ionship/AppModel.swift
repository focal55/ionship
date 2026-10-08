import Foundation
import IonshipCore
import Observation

struct PersonHealth: Identifiable, Equatable {
    enum Health: Equatable {
        case person(RelationshipMetrics)
        case group(GroupMetrics)
    }

    let conversation: Conversation
    let title: String
    let health: Health
    /// Group members' handles to contact names.
    var memberNames: [String: String] = [:]
    var id: Int64 { conversation.id }

    var messageCount: Int {
        switch health {
        case .person(let metrics): metrics.messageCount
        case .group(let metrics): metrics.messageCount
        }
    }

    var needsAttention: Bool {
        switch health {
        case .person(let metrics): metrics.observations().contains(where: \.isActionable)
        case .group(let metrics):
            metrics.observations.contains {
                switch $0 {
                case .drifting, .goneQuiet: true
                case .carries: false
                }
            }
        }
    }

    func memberName(_ handle: String?) -> String {
        handle.map { memberNames[$0] ?? $0 } ?? "You"
    }
}

@MainActor @Observable
final class AppModel {
    enum Phase: Equatable {
        case checking
        case connect(MessagesAccess)
        case loading
        case choose
        case analyzing
        case health
        case failed(String)
    }

    private static let selectionKey = "selectedChatIDs"

    private(set) var phase = Phase.checking
    private(set) var people: [PersonHealth] = []
    var picker = ConversationPicker(chats: [])
    private var polling: Task<Void, Never>?

    func start() {
        guard polling == nil else { return }
        polling = Task {
            while !Task.isCancelled {
                let access = await Task.detached { MessagesAccess.check() }.value
                if access == .granted {
                    await loadChats()
                    return
                }
                phase = .connect(access)
                try? await Task.sleep(for: .seconds(2))
            }
        }
    }

    func importSelected() {
        UserDefaults.standard.set(picker.selected.map(Int.init), forKey: Self.selectionKey)
        Task { await analyze() }
    }

    func changeConversations() {
        phase = .choose
    }

    private var threads: [Int64: [Message]] = [:]

    func thread(for conversation: Conversation) async -> [Message] {
        if let cached = threads[conversation.id] { return cached }
        let chatIDs = conversation.chatIDs
        let messages = (try? await Task.detached { () throws -> [Message] in
            let store = try MessagesStore()
            return try chatIDs.flatMap { try store.messages(chatID: $0, limit: .max) }.sorted { $0.date < $1.date }
        }.value) ?? []
        threads[conversation.id] = messages
        return messages
    }

    private func loadChats() async {
        phase = .loading
        do {
            let chats = try await Task.detached { try MessagesStore().chats() }.value
            picker = ConversationPicker(chats: chats)
            picker.names = await ContactsLoader.directory()
            if let saved = UserDefaults.standard.array(forKey: Self.selectionKey) as? [Int], !saved.isEmpty {
                picker.restore(selection: Set(saved.map(Int64.init)))
                await analyze()
            } else {
                phase = .choose
            }
        } catch {
            phase = .failed(String(describing: error))
        }
    }

    private func analyze() async {
        phase = .analyzing
        let conversations = picker.selectedConversations
        do {
            let health = try await Task.detached {
                let store = try MessagesStore()
                return try conversations.map { conversation -> PersonHealth.Health in
                    let messages = try conversation.chatIDs.flatMap { try store.messages(chatID: $0, limit: .max) }
                    return conversation.isGroup
                        ? .group(GroupMetrics.compute(messages, participants: conversation.participants))
                        : .person(RelationshipMetrics.compute(messages))
                }
            }.value
            let names = picker.names
            people = zip(conversations, health)
                .map { conversation, health in
                    var person = PersonHealth(conversation: conversation, title: picker.title(for: conversation), health: health)
                    if conversation.isGroup {
                        for handle in conversation.participants { person.memberNames[handle] = names.name(for: handle) }
                    }
                    return person
                }
                .sorted { $0.messageCount > $1.messageCount }
            phase = .health
        } catch {
            phase = .failed(String(describing: error))
        }
    }
}
