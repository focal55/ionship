import Foundation
import IonshipCore
import Observation

struct PersonHealth: Identifiable, Equatable {
    let chat: Chat
    let title: String
    let metrics: RelationshipMetrics
    var id: Int64 { chat.id }
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
        let chats = picker.selectedChats
        do {
            let metrics = try await Task.detached {
                let store = try MessagesStore()
                return try chats.map { RelationshipMetrics.compute(try store.messages(chatID: $0.id, limit: .max)) }
            }.value
            people = zip(chats, metrics)
                .map { PersonHealth(chat: $0, title: picker.title(for: $0), metrics: $1) }
                .sorted { $0.metrics.messageCount > $1.metrics.messageCount }
            phase = .health
        } catch {
            phase = .failed(String(describing: error))
        }
    }
}
