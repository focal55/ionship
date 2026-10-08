import Foundation
import IonshipCore
import Observation

@MainActor @Observable
final class AppModel {
    enum Phase: Equatable {
        case checking
        case connect(MessagesAccess)
        case loading
        case choose
        case imported(conversations: Int, messages: Int)
        case failed(String)
    }

    private(set) var phase = Phase.checking
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
        phase = .imported(conversations: picker.selected.count, messages: picker.selectedMessageCount)
    }

    private func loadChats() async {
        phase = .loading
        do {
            let chats = try await Task.detached { try MessagesStore().chats() }.value
            picker = ConversationPicker(chats: chats)
            phase = .choose
        } catch {
            phase = .failed(String(describing: error))
        }
    }
}
