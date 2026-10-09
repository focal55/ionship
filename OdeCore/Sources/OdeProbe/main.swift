import Foundation
import OdeCore

// Prints aggregate health of a chat.db. Never prints message bodies, and masks handles,
// so the output is safe to paste into an issue or an AI chat.

func mask(_ handle: String) -> String {
    if handle.contains("@") {
        let parts = handle.split(separator: "@", maxSplits: 1)
        return "\(parts[0].prefix(1))•••@\(parts.count > 1 ? parts[1] : "")"
    }
    return handle.count > 4 ? String(repeating: "•", count: handle.count - 4) + handle.suffix(4) : handle
}

func percent(_ part: Int, of whole: Int) -> String {
    whole == 0 ? "0.0%" : String(format: "%.1f%%", Double(part) / Double(whole) * 100)
}

let path = CommandLine.arguments.dropFirst().first ?? MessagesStore.defaultPath
print("ode-probe  \(path)")
print("macOS \(ProcessInfo.processInfo.operatingSystemVersionString)\n")

let store: MessagesStore
do {
    store = try MessagesStore(path: path)
} catch MessagesStoreError.accessDenied {
    print("""
        Access denied: macOS is blocking this process from reading Messages.
        Grant Full Disk Access to your terminal app in
        System Settings › Privacy & Security › Full Disk Access, then quit and reopen the terminal.
        """)
    exit(2)
} catch {
    print("Could not open database: \(error)")
    exit(1)
}

let schema = try store.schemaReport()
print("Schema: \(schema.present.count) required columns present, \(schema.missing.count) missing")
for column in schema.missing { print("  missing \(column)") }
guard schema.isUsable else { exit(3) }

var total = 0
var kinds: [Message.Kind: Int] = [:]
var fromColumn = 0, fromUnarchiver = 0, fromFallback = 0, undecodable = 0, noText = 0
var failureSamples: [Int64] = []
var newest: Date?
var cursor: Int64 = 0
let started = Date()

while true {
    let batch = try store.newMessages(after: cursor, limit: 20_000)
    guard let last = batch.last else { break }
    cursor = last.id
    for message in batch {
        total += 1
        kinds[message.kind, default: 0] += 1
        newest = max(newest ?? message.date, message.date)
        switch message.textSource {
        case .column: fromColumn += 1
        case .attributedBody(.unarchiver): fromUnarchiver += 1
        case .attributedBody(.fallback): fromFallback += 1
        case .undecodable:
            undecodable += 1
            if failureSamples.count < 5 { failureSamples.append(message.id) }
        case .none: noText += 1
        }
    }
}

let elapsed = Date().timeIntervalSince(started)
print("\nMessages: \(total)  (read in \(String(format: "%.1f", elapsed))s, newest \(newest.map { $0.formatted() } ?? "n/a"))")
print("  text \(kinds[.text, default: 0])  reactions \(kinds[.reaction, default: 0])  attachment-only \(kinds[.attachmentOnly, default: 0])  other \(kinds[.other, default: 0])")

print("\nWhere text came from (the fragility metric):")
print("  text column          \(fromColumn)  \(percent(fromColumn, of: total))")
print("  attributedBody/NSUnarchiver  \(fromUnarchiver)  \(percent(fromUnarchiver, of: total))")
print("  attributedBody/fallback      \(fromFallback)  \(percent(fromFallback, of: total))")
print("  undecodable          \(undecodable)  \(percent(undecodable, of: total))")
print("  no text at all       \(noText)  \(percent(noText, of: total))")
if !failureSamples.isEmpty { print("  sample undecodable ROWIDs: \(failureSamples.map(String.init).joined(separator: ", "))") }

let chats = try store.chats()
print("\nChats: \(chats.count)  (\(chats.filter(\.isGroup).count) groups)")
print("Top 10 by message count:")
for chat in chats.sorted(by: { $0.messageCount > $1.messageCount }).prefix(10) {
    let name = chat.isGroup ? (chat.displayName.map { "group “\($0.prefix(1))…”" } ?? "unnamed group")
        : mask(chat.participants.first ?? chat.identifier)
    print("  \(String(chat.messageCount).padding(toLength: 8, withPad: " ", startingAt: 0)) \(name)  \(chat.participants.count) participant(s)")
}
