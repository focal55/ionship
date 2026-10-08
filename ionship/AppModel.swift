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
    var health: Health
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

    nonisolated static func health(for conversation: Conversation, messages: [Message]) -> Health {
        conversation.isGroup
            ? .group(GroupMetrics.compute(messages, participants: conversation.participants))
            : .person(RelationshipMetrics.compute(messages))
    }

    func memberName(_ handle: String?) -> String {
        handle.map { memberNames[$0] ?? $0 } ?? "You"
    }
}

struct MemoryResult: Identifiable, Equatable {
    let moment: Moment
    let title: String
    var id: String { moment.id }
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
        syncing?.cancel()
        indexing?.cancel()
        phase = .choose
    }

    /// Every message of every chosen conversation, oldest first, kept current by live sync.
    private(set) var threads: [Int64: [Message]] = [:]
    private var loops: [Int64: OpenLoops] = [:]
    private var cursor: Int64 = 0
    private var syncing: Task<Void, Never>?
    /// Fraction of chosen conversations indexed into memory; nil when idle.
    private(set) var indexingProgress: Double?
    private var indexing: Task<Void, Never>?

    nonisolated private static var memoryPath: String {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return support.appendingPathComponent("Ionship/memory.sqlite").path
    }

    func searchMemory(_ text: String) async -> [MemoryResult] {
        let titles = Dictionary(uniqueKeysWithValues: people.map { ($0.id, $0.title) })
        let hits = await Task.detached { () -> [MemoryIndex.Hit] in
            guard let embedder = ContextualEmbedder(), let index = try? MemoryIndex(path: Self.memoryPath) else { return [] }
            return (try? index.search(text, embedder: embedder, limit: 30)) ?? []
        }.value
        return hits.compactMap { hit in
            titles[hit.moment.conversationID].map { MemoryResult(moment: hit.moment, title: $0) }
        }
    }

    /// Adds closed sessions not yet in memory. Safe to call repeatedly: each conversation
    /// resumes after the last message already indexed.
    private func updateMemory(for targets: [PersonHealth]) {
        let previous = indexing
        let jobs = targets.map { person in
            (person.id, threads[person.id] ?? [], person.title, person.memberNames)
        }
        indexing = Task {
            await previous?.value
            for (offset, job) in jobs.enumerated() {
                guard !Task.isCancelled else { return }
                if jobs.count > 1 { indexingProgress = Double(offset) / Double(jobs.count) }
                let (id, messages, title, memberNames) = job
                await Task.detached(priority: .utility) {
                    guard let embedder = ContextualEmbedder(), let index = try? MemoryIndex(path: Self.memoryPath),
                          let through = try? index.indexedThrough(conversationID: id) else { return }
                    let pending = messages.filter { $0.id > through }
                    let moments = Moment.split(pending, conversationID: id) { handle in
                        handle.map { memberNames[$0] ?? title } ?? "You"
                    }
                    for batch in stride(from: 0, to: moments.count, by: 200) {
                        try? index.add(Array(moments[batch..<min(batch + 200, moments.count)]), embedder: embedder)
                    }
                }.value
            }
            indexingProgress = nil
        }
    }

    func openLoops(for person: PersonHealth) async -> OpenLoops {
        if let cached = loops[person.id] { return cached }
        let candidates = OpenLoopCandidate.find(in: threads[person.id] ?? [])
        let result = await OpenLoopJudge.evaluate(candidates, name: { handle in
            handle.map { person.memberNames[$0] ?? person.title } ?? "You"
        })
        loops[person.id] = result
        return result
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
        syncing?.cancel()
        phase = .analyzing
        let conversations = picker.selectedConversations
        do {
            let (latest, loaded) = try await Task.detached { () throws -> (Int64, [[Message]]) in
                let store = try MessagesStore()
                // Read the cursor first: anything arriving mid-load is fetched again by sync and deduplicated.
                let latest = try store.latestRowID()
                let threads = try conversations.map { conversation in
                    try conversation.chatIDs.flatMap { try store.messages(chatID: $0, limit: .max) }.sorted { $0.date < $1.date }
                }
                return (latest, threads)
            }.value
            let health = await Task.detached {
                zip(conversations, loaded).map { PersonHealth.health(for: $0, messages: $1) }
            }.value
            cursor = latest
            loops = [:]
            threads = Dictionary(uniqueKeysWithValues: zip(conversations.map(\.id), loaded))
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
            startSyncing()
            updateMemory(for: people)
        } catch {
            phase = .failed(String(describing: error))
        }
    }

    private func startSyncing() {
        syncing = Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(5))
                await syncOnce()
            }
        }
    }

    private func syncOnce() async {
        let after = cursor
        guard let fresh = try? await Task.detached(operation: { () throws -> [Message]? in
            let store = try MessagesStore()
            guard try store.latestRowID() > after else { return nil }
            return try store.newMessages(after: after)
        }).value, let newest = fresh.last?.id else { return }
        cursor = newest

        for (id, arrived) in LiveSync.route(fresh, to: people.map(\.conversation)) {
            guard let conversation = people.first(where: { $0.id == id })?.conversation else { continue }
            let existing = threads[id] ?? []
            let known = Set(existing.suffix(500).map(\.id))
            let merged = (existing + arrived.filter { !known.contains($0.id) }).sorted { $0.date < $1.date }
            let health = await Task.detached { PersonHealth.health(for: conversation, messages: merged) }.value
            guard !Task.isCancelled, let index = people.firstIndex(where: { $0.id == id }) else { return }
            threads[id] = merged
            people[index].health = health
            loops[id] = nil
            updateMemory(for: [people[index]])
        }
    }
}
