# Waiting on You Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ode opens on a "Waiting on you" list of everyone who needs to hear from you: unanswered messages, open promises, and people gone quiet.

**Architecture:** OdeCore gains a pure `Waiting` type with three builders (`unanswered`, `promised`, `quiet`) and a `rank` function; the rules are tested there. The app's `AppModel` assembles the list from data it already holds (threads, judged open loops, relationship metrics), persists dismissals, and judges open loops for everyone in the background. A new `WaitingView` becomes the default center pane, reached from a new entry at the top of the sidebar.

**Tech Stack:** Swift 6, SwiftUI (macOS 26), Swift Testing, Swift Package Manager (OdeCore).

**Spec:** `docs/superpowers/specs/2026-10-09-waiting-on-you-design.md`

## Global Constraints

- Unanswered window: at least 1 hour and at most 21 days since their latest message.
- Unanswered applies to 1:1 conversations only; groups get promised items only. Gone quiet is 1:1 only.
- Kinds, in priority order: asked you, unanswered, promised, gone quiet. Oldest first within a kind. One row per conversation.
- Closers: ok, okay, k, kk, thanks, thank you, thx, ty, lol, haha, hahaha, lmao, nice, cool, sounds good, got it, np, no problem, you too, will do, perfect, great, 👍, ❤️. Trailing punctuation and emoji are ignored; any text containing `?` is never a closer.
- Steers: asked "answer their question"; unanswered "reply to their last message"; promised "follow up on: {task}"; gone quiet "reconnect".
- Only promises the on-device model judged and confirmed appear (`AppModel.confirmedLoops`).
- Done hides a row until a newer message arrives; stored in UserDefaults under `dismissedWaiting` as conversation id → newest message id.
- Code style: no comments that restate code, conventional commits, no emojis outside the closer list.
- Commands: on this Mac `xcode-select` points at the Command Line Tools, so prefix Swift and Xcode commands with `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`.

## Review Focus

1. Someone who texted you first and you never replied (no message from you at all) should still be waiting. Covered by `neverRepliedStillCounts` in Task 1.
2. A photo with no text, or a message whose text couldn't be decoded, should show "Attachment" or "Message", not a blank row. Covered by `attachmentsAndUndecodedTextGetALabel` in Task 1.
3. A real question followed by "lol" should still read as "asked you" and show the question. Covered by `aLaterCloserDoesNotHideAnEarlierQuestion` in Task 1.
4. A row you marked Done must come back when they write again, and stay gone when nothing new arrives. Covered by `dismissedStaysHiddenUntilSomethingNewArrives` in Task 2.
5. Replying from your phone (the message arrives through live sync) must clear the row within a sync cycle. `AppModel.waiting` is recomputed from `threads` on every render, so this follows from Task 1's `yourReplyClearsIt`; check it manually in Task 4, step 5.

---

### Task 1: Unanswered detection in OdeCore

**Files:**
- Create: `OdeCore/Sources/OdeCore/Waiting.swift`
- Test: `OdeCore/Tests/OdeCoreTests/WaitingTests.swift`

**Interfaces:**
- Consumes: `Message`, `Conversation`, `Chat` (OdeCore, existing).
- Produces:
  - `public struct Waiting: Sendable, Equatable, Identifiable` with `conversationID: Int64`, `kind: Kind`, `text: String`, `steer: String`, `since: Date`, `newestMessageID: Int64`, `id: Int64 { conversationID }`, and a public memberwise `init(conversationID:kind:text:steer:since:newestMessageID:)`.
  - `public enum Waiting.Kind: Int, Sendable, Comparable { case asked, unanswered, promised, quiet }`
  - `public static func unanswered(in conversation: Conversation, messages: [Message], now: Date = .now) -> Waiting?`. `messages` must be in date order, as `AppModel.threads` keeps them.
  - `static func isCloser(_ text: String?) -> Bool` (internal)

- [ ] **Step 1: Write the failing tests**

Create `OdeCore/Tests/OdeCoreTests/WaitingTests.swift`:

```swift
import Foundation
import Testing
@testable import OdeCore

private let now = Date(timeIntervalSinceReferenceDate: 800_000_000)
private let hour: TimeInterval = 3_600
private let day: TimeInterval = 86_400

private func w(_ id: Int64, me: Bool, _ text: String?, hoursAgo: Double, kind: Message.Kind = .text) -> Message {
    Message(id: id, guid: "g\(id)", chatID: 7, sender: me ? nil : "+15550001111", isFromMe: me,
            date: now.addingTimeInterval(-hoursAgo * hour), text: text, textSource: .column, kind: kind)
}

private func conversation(group: Bool = false) -> Conversation {
    Conversation(chats: [Chat(id: 7, identifier: "x", displayName: nil, isGroup: group,
                              participants: group ? ["+15550001111", "+15550002222"] : ["+15550001111"],
                              messageCount: 0, lastMessageDate: nil)])
}

@Suite struct UnansweredTests {
    func find(_ messages: [Message], group: Bool = false) -> Waiting? {
        Waiting.unanswered(in: conversation(group: group), messages: messages, now: now)
    }

    @Test func theirMessageAfterYoursIsWaiting() {
        let item = find([w(1, me: true, "how was the trip", hoursAgo: 30), w(2, me: false, "amazing, sending pics soon", hoursAgo: 5)])
        #expect(item?.kind == .unanswered)
        #expect(item?.text == "amazing, sending pics soon")
        #expect(item?.steer == "reply to their last message")
        #expect(item?.since == now.addingTimeInterval(-5 * hour))
        #expect(item?.newestMessageID == 2)
        #expect(item?.conversationID == 7)
    }

    @Test func aQuestionIsAsked() {
        let item = find([w(1, me: true, "hey", hoursAgo: 30), w(2, me: false, "are you free Saturday?", hoursAgo: 4)])
        #expect(item?.kind == .asked)
        #expect(item?.steer == "answer their question")
    }

    @Test func yourReplyClearsIt() {
        #expect(find([w(1, me: false, "are you free Saturday?", hoursAgo: 6), w(2, me: true, "yes!", hoursAgo: 5)]) == nil)
    }

    @Test func yourReactionClearsIt() {
        #expect(find([w(1, me: false, "landed safe", hoursAgo: 6),
                      w(2, me: true, "Loved “landed safe”", hoursAgo: 5, kind: .reaction)]) == nil)
    }

    @Test func theirReactionIsNotAMessage() {
        #expect(find([w(1, me: true, "see you then", hoursAgo: 6),
                      w(2, me: false, "Liked “see you then”", hoursAgo: 5, kind: .reaction)]) == nil)
    }

    @Test func tooRecentIsNotWaitingYet() {
        #expect(find([w(1, me: false, "are you free Saturday?", hoursAgo: 0.5)]) == nil)
    }

    @Test func olderThanThreeWeeksIsLeftToGoneQuiet() {
        #expect(find([w(1, me: false, "are you free Saturday?", hoursAgo: 22 * 24)]) == nil)
    }

    @Test func windowEdgesAreIncluded() {
        #expect(find([w(1, me: false, "call me", hoursAgo: 1)]) != nil)
        #expect(find([w(1, me: false, "call me", hoursAgo: 21 * 24)]) != nil)
    }

    @Test func windowUsesTheirLatestMessage() {
        #expect(find([w(1, me: false, "dinner friday?", hoursAgo: 30), w(2, me: false, "also call me", hoursAgo: 0.2)]) == nil)
    }

    @Test(arguments: ["ok", "Okay.", "thanks!!", "Thank you 🙏", "lol 😂", "sounds good", "Got it", "👍", "❤️", "kk", "you too!"])
    func closersAreNotWaiting(_ text: String) {
        #expect(find([w(1, me: true, "see you at 7", hoursAgo: 6), w(2, me: false, text, hoursAgo: 5)]) == nil)
    }

    @Test(arguments: ["ok?", "ok but when", "thanks for the help, how much do I owe you", "lol what"])
    func nearClosersStillCount(_ text: String) {
        #expect(find([w(1, me: true, "see you at 7", hoursAgo: 6), w(2, me: false, text, hoursAgo: 5)]) != nil)
    }

    @Test func aLaterCloserDoesNotHideAnEarlierQuestion() {
        let item = find([w(1, me: true, "hey", hoursAgo: 30), w(2, me: false, "can you send the address?", hoursAgo: 8),
                         w(3, me: false, "lol", hoursAgo: 7)])
        #expect(item?.kind == .asked)
        #expect(item?.text == "can you send the address?")
        #expect(item?.since == now.addingTimeInterval(-8 * hour))
        #expect(item?.newestMessageID == 3)
    }

    @Test func onlyClosersMeansNothingIsWaiting() {
        #expect(find([w(1, me: true, "done", hoursAgo: 9), w(2, me: false, "thanks", hoursAgo: 8),
                      w(3, me: false, "👍", hoursAgo: 7)]) == nil)
    }

    @Test func neverRepliedStillCounts() {
        #expect(find([w(1, me: false, "hi it's Sam from the climbing gym", hoursAgo: 3)])?.kind == .unanswered)
    }

    @Test func attachmentsAndUndecodedTextGetALabel() {
        #expect(find([w(1, me: false, nil, hoursAgo: 3, kind: .attachmentOnly)])?.text == "Attachment")
        #expect(find([w(1, me: false, nil, hoursAgo: 3)])?.text == "Message")
    }

    @Test func groupsAreLeftOut() {
        #expect(find([w(1, me: false, "anyone free Saturday?", hoursAgo: 3)], group: true) == nil)
    }

    @Test func emptyThreadIsNothing() {
        #expect(find([]) == nil)
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `cd OdeCore && DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter UnansweredTests`
Expected: a build failure, "cannot find 'Waiting' in scope".

- [ ] **Step 3: Write the implementation**

Create `OdeCore/Sources/OdeCore/Waiting.swift`:

```swift
import Foundation

/// Something a person is waiting on from you, for the home list.
public struct Waiting: Sendable, Equatable, Identifiable {
    /// In priority order: the list shows asked before unanswered before promised before quiet.
    public enum Kind: Int, Sendable, Comparable {
        case asked, unanswered, promised, quiet

        public static func < (lhs: Kind, rhs: Kind) -> Bool { lhs.rawValue < rhs.rawValue }
    }

    public let conversationID: Int64
    public let kind: Kind
    public let text: String
    /// What the draft composer is asked to do when you reply from the list.
    public let steer: String
    /// When it started waiting; the list shows the oldest first within a kind.
    public let since: Date
    /// A dismissal lasts until a message newer than this arrives.
    public let newestMessageID: Int64
    public var id: Int64 { conversationID }

    public init(conversationID: Int64, kind: Kind, text: String, steer: String, since: Date, newestMessageID: Int64) {
        self.conversationID = conversationID
        self.kind = kind
        self.text = text
        self.steer = steer
        self.since = since
        self.newestMessageID = newestMessageID
    }
}

extension Waiting {
    static let minimumAge: TimeInterval = 3_600
    static let maximumAge: TimeInterval = 21 * 86_400

    /// Their messages since your last one, in a 1:1 conversation. `messages` must be in date order.
    /// Younger than an hour isn't waiting yet; older than three weeks is left to `quiet`.
    public static func unanswered(in conversation: Conversation, messages: [Message], now: Date = .now) -> Waiting? {
        guard !conversation.isGroup, let newest = messages.map(\.id).max() else { return nil }
        let isSpoken = { (message: Message) in message.kind == .text || message.kind == .attachmentOnly }
        let start = messages.lastIndex { $0.isFromMe && isSpoken($0) }.map { $0 + 1 } ?? messages.startIndex
        let after = messages[start...]
        let theirs = after.filter { !$0.isFromMe && isSpoken($0) }
        guard let latest = theirs.last, let first = theirs.first else { return nil }
        guard !after.contains(where: { $0.isFromMe && $0.kind == .reaction && $0.date >= latest.date }) else { return nil }
        let age = now.timeIntervalSince(latest.date)
        guard age >= minimumAge, age <= maximumAge else { return nil }
        guard let shown = theirs.last(where: { !isCloser($0.text) }) else { return nil }

        let asked = theirs.contains { $0.text?.contains("?") == true }
        let text = shown.text ?? (shown.kind == .attachmentOnly ? "Attachment" : "Message")
        return Waiting(conversationID: conversation.id, kind: asked ? .asked : .unanswered, text: text,
                       steer: asked ? "answer their question" : "reply to their last message",
                       since: first.date, newestMessageID: newest)
    }

    private static let closers: Set<String> = [
        "ok", "okay", "k", "kk", "thanks", "thank you", "thx", "ty", "lol", "haha", "hahaha", "lmao", "nice", "cool",
        "sounds good", "got it", "np", "no problem", "you too", "will do", "perfect", "great",
    ]
    private static let closingEmoji: Set<Character> = ["👍", "❤️"]

    /// A message that ends an exchange and doesn't need a reply.
    static func isCloser(_ text: String?) -> Bool {
        guard let text else { return false }
        let trimmed = text.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.contains("?") else { return false }
        if trimmed.allSatisfy({ closingEmoji.contains($0) || $0.isWhitespace }) { return true }
        var core = Substring(trimmed)
        while let last = core.last, last.isPunctuation || last.isWhitespace || isEmoji(last) { core = core.dropLast() }
        return closers.contains(String(core))
    }

    /// Emoji, but not the digits and symbols Unicode also flags as emoji-capable.
    private static func isEmoji(_ character: Character) -> Bool {
        character.unicodeScalars.contains { $0.properties.isEmojiPresentation || ($0.properties.isEmoji && $0.value > 0x238C) }
    }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `cd OdeCore && DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter UnansweredTests`
Expected: all UnansweredTests pass.

Then run the whole suite: `cd OdeCore && DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test`
Expected: every test passes (130 existing plus the new ones).

- [ ] **Step 5: Commit**

```bash
git add OdeCore/Sources/OdeCore/Waiting.swift OdeCore/Tests/OdeCoreTests/WaitingTests.swift
git commit -m "feat(core): find messages you haven't answered"
```

---

### Task 2: Promises, gone quiet and ranking in OdeCore

**Files:**
- Modify: `OdeCore/Sources/OdeCore/Waiting.swift` (append a second extension)
- Modify: `OdeCore/Tests/OdeCoreTests/WaitingTests.swift` (append two suites)

**Interfaces:**
- Consumes: `Waiting` and `Waiting.Kind` from Task 1; `RelationshipMetrics` and `RelationshipMetrics.Observation.overdue(since:usual:)` (existing).
- Produces:
  - `public static func promised(in conversation: Conversation, task: String, made: Date, newestMessageID: Int64) -> Waiting`
  - `public static func quiet(in conversation: Conversation, metrics: RelationshipMetrics, newestMessageID: Int64, now: Date = .now) -> Waiting?`
  - `public static func rank(_ items: [Waiting], dismissed: [Int64: Int64] = [:]) -> [Waiting]`
  - `static func every(_ interval: TimeInterval) -> String` and `static func been(_ interval: TimeInterval) -> String` (internal)

- [ ] **Step 1: Write the failing tests**

Append to `OdeCore/Tests/OdeCoreTests/WaitingTests.swift`:

```swift
@Suite struct WaitingKindsTests {
    func metrics(lastLongDaysAgo: Double, usualGapDays: Double) -> RelationshipMetrics {
        RelationshipMetrics(
            messageCount: 100, conversations: 10, youStartShare: 0.5, yourMedianReply: 600, theirMedianReply: 600,
            yourRecentMedianReply: 600, lastLongConversation: now.addingTimeInterval(-lastLongDaysAgo * day),
            usualGapBetweenLongConversations: usualGapDays * day, weekly: [])
    }

    @Test func promiseReadsAsWhatYouSaid() {
        let item = Waiting.promised(in: conversation(), task: "Send the Big Sur photos", made: now, newestMessageID: 40)
        #expect(item.kind == .promised)
        #expect(item.text == "You said you'd send the Big Sur photos")
        #expect(item.steer == "follow up on: send the Big Sur photos")
        #expect(item.since == now)
        #expect(item.newestMessageID == 40)
        #expect(item.conversationID == 7)
    }

    @Test func goneQuietUsesTheOverdueObservation() {
        let item = Waiting.quiet(in: conversation(), metrics: metrics(lastLongDaysAgo: 35, usualGapDays: 14),
                                 newestMessageID: 9, now: now)
        #expect(item?.kind == .quiet)
        #expect(item?.text == "You usually talk every 2 weeks; it's been 5 weeks")
        #expect(item?.steer == "reconnect")
        #expect(item?.since == now.addingTimeInterval(-35 * day))
        #expect(item?.newestMessageID == 9)
    }

    @Test func onScheduleIsNotQuiet() {
        #expect(Waiting.quiet(in: conversation(), metrics: metrics(lastLongDaysAgo: 10, usualGapDays: 14),
                              newestMessageID: 9, now: now) == nil)
    }

    @Test func groupsAreNeverQuiet() {
        #expect(Waiting.quiet(in: conversation(group: true), metrics: metrics(lastLongDaysAgo: 35, usualGapDays: 14),
                              newestMessageID: 9, now: now) == nil)
    }

    @Test(arguments: [(1.0, "every day", "a day"), (3.0, "every 3 days", "3 days"), (14.0, "every 2 weeks", "2 weeks"),
                      (30.0, "every 4 weeks", "4 weeks"), (90.0, "every 3 months", "3 months")])
    func durationsReadNaturally(_ c: (days: Double, every: String, been: String)) {
        #expect(Waiting.every(c.days * day) == c.every)
        #expect(Waiting.been(c.days * day) == c.been)
    }
}

@Suite struct WaitingRankTests {
    func item(_ id: Int64, _ kind: Waiting.Kind, daysAgo: Double, newest: Int64 = 100) -> Waiting {
        Waiting(conversationID: id, kind: kind, text: "", steer: "", since: now.addingTimeInterval(-daysAgo * day),
                newestMessageID: newest)
    }

    @Test func mostUrgentKindFirstThenOldest() {
        let ranked = Waiting.rank([item(1, .quiet, daysAgo: 40), item(2, .unanswered, daysAgo: 1), item(3, .asked, daysAgo: 1),
                                   item(4, .unanswered, daysAgo: 3), item(5, .promised, daysAgo: 2)])
        #expect(ranked.map(\.conversationID) == [3, 4, 2, 5, 1])
    }

    @Test func oneRowPerConversationUnderItsMostUrgentKind() {
        let ranked = Waiting.rank([item(1, .promised, daysAgo: 5), item(1, .unanswered, daysAgo: 1), item(1, .quiet, daysAgo: 40)])
        #expect(ranked.map(\.kind) == [.unanswered])
    }

    @Test func oldestPromiseRepresentsAConversation() {
        let ranked = Waiting.rank([item(1, .promised, daysAgo: 2), item(1, .promised, daysAgo: 9)])
        #expect(ranked.map(\.since) == [now.addingTimeInterval(-9 * day)])
    }

    @Test func dismissedStaysHiddenUntilSomethingNewArrives() {
        #expect(Waiting.rank([item(1, .asked, daysAgo: 1, newest: 100)], dismissed: [1: 100]).isEmpty)
        #expect(Waiting.rank([item(1, .asked, daysAgo: 1, newest: 101)], dismissed: [1: 100]).count == 1)
        #expect(Waiting.rank([item(2, .asked, daysAgo: 1)], dismissed: [1: 100]).count == 1)
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `cd OdeCore && DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter "WaitingKindsTests|WaitingRankTests"`
Expected: a build failure, "type 'Waiting' has no member 'promised'".

- [ ] **Step 3: Write the implementation**

Append to `OdeCore/Sources/OdeCore/Waiting.swift`:

```swift
extension Waiting {
    /// A promise the on-device model confirmed is still open.
    public static func promised(in conversation: Conversation, task: String, made: Date, newestMessageID: Int64) -> Waiting {
        let phrase = task.prefix(1).lowercased() + task.dropFirst()
        return Waiting(conversationID: conversation.id, kind: .promised, text: "You said you'd \(phrase)",
                       steer: "follow up on: \(phrase)", since: made, newestMessageID: newestMessageID)
    }

    /// A 1:1 relationship well past its usual gap between long conversations.
    public static func quiet(in conversation: Conversation, metrics: RelationshipMetrics, newestMessageID: Int64,
                             now: Date = .now) -> Waiting? {
        guard !conversation.isGroup else { return nil }
        for case .overdue(let since, let usual) in metrics.observations(now: now) {
            return Waiting(conversationID: conversation.id, kind: .quiet,
                           text: "You usually talk \(every(usual)); it's been \(been(since))", steer: "reconnect",
                           since: now.addingTimeInterval(-since), newestMessageID: newestMessageID)
        }
        return nil
    }

    /// One row per conversation under its most urgent kind, most urgent first and oldest first within a kind.
    /// `dismissed` maps a conversation to the newest message id when it was dismissed.
    public static func rank(_ items: [Waiting], dismissed: [Int64: Int64] = [:]) -> [Waiting] {
        Dictionary(grouping: items, by: \.conversationID).values
            .compactMap { group in group.min { ($0.kind, $0.since) < ($1.kind, $1.since) } }
            .filter { item in dismissed[item.conversationID].map { item.newestMessageID > $0 } ?? true }
            .sorted { ($0.kind, $0.since, $0.conversationID) < ($1.kind, $1.since, $1.conversationID) }
    }

    static func every(_ interval: TimeInterval) -> String {
        let (count, unit) = span(interval)
        return count == 1 ? "every \(unit)" : "every \(count) \(unit)s"
    }

    static func been(_ interval: TimeInterval) -> String {
        let (count, unit) = span(interval)
        return count == 1 ? "a \(unit)" : "\(count) \(unit)s"
    }

    private static func span(_ interval: TimeInterval) -> (count: Int, unit: String) {
        let days = max(1, Int((interval / 86_400).rounded()))
        if days < 14 { return (days, "day") }
        if days < 60 { return (Int((Double(days) / 7).rounded()), "week") }
        return (Int((Double(days) / 30).rounded()), "month")
    }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `cd OdeCore && DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test`
Expected: every test passes, including WaitingKindsTests and WaitingRankTests.

- [ ] **Step 5: Commit**

```bash
git add OdeCore/Sources/OdeCore/Waiting.swift OdeCore/Tests/OdeCoreTests/WaitingTests.swift
git commit -m "feat(core): promises, gone quiet and ranking for the waiting list"
```

---

### Task 3: The waiting list in AppModel

**Files:**
- Modify: `Ode/AppModel.swift`. Add the stored properties near `labels` (around line 76); add `waiting`, `dismiss` and `judgePromises` next to `confirmedLoops` (around line 324); call `judgePromises()` at the end of `analyze()` and `syncOnce()`; add a Mom thread to `preview()`.

**Interfaces:**
- Consumes: `Waiting.unanswered`, `Waiting.promised`, `Waiting.quiet`, `Waiting.rank` from Tasks 1 and 2; the existing `confirmedLoops(for:)`, `openLoops(for:)`, `threads`, `people` and `loops`.
- Produces, for Task 4:
  - `var waiting: [Waiting] { get }`
  - `private(set) var checkingPromises: Bool`
  - `func dismiss(_ item: Waiting)`

There is no unit-test target for the app, so this task is verified by building it and by Task 4's preview and manual check. All of its logic sits in OdeCore functions tested in Tasks 1 and 2.

- [ ] **Step 1: Add the stored state**

In `Ode/AppModel.swift`, below `private static let pinnedKey = "pinnedConversations"`, add:

```swift
    private static let dismissedKey = "dismissedWaiting"
```

Below the `pinned` property, add:

```swift
    private(set) var dismissedWaiting: [Int64: Int64] = (UserDefaults.standard.dictionary(forKey: AppModel.dismissedKey) as? [String: Int] ?? [:])
        .reduce(into: [:]) { result, entry in
            if let id = Int64(entry.key) { result[id] = Int64(entry.value) }
        }
    private(set) var checkingPromises = false
```

- [ ] **Step 2: Add the list, dismissal and background judging**

Directly after the `confirmedLoops(for:)` function, add:

```swift
    /// The home list: who is waiting to hear from you, most urgent first.
    var waiting: [Waiting] {
        let items = people.flatMap { person -> [Waiting] in
            let thread = threads[person.id] ?? []
            let newest = thread.map(\.id).max() ?? 0
            var found = confirmedLoops(for: person).map {
                Waiting.promised(in: person.conversation, task: $0.task, made: $0.date, newestMessageID: newest)
            }
            if let unanswered = Waiting.unanswered(in: person.conversation, messages: thread) { found.append(unanswered) }
            if case .person(let metrics) = person.health,
               let quiet = Waiting.quiet(in: person.conversation, metrics: metrics, newestMessageID: newest) {
                found.append(quiet)
            }
            return found
        }
        return Waiting.rank(items, dismissed: dismissedWaiting)
    }

    func dismiss(_ item: Waiting) {
        dismissedWaiting[item.conversationID] = item.newestMessageID
        UserDefaults.standard.set(Dictionary(uniqueKeysWithValues: dismissedWaiting.map { (String($0.key), Int($0.value)) }),
                                  forKey: Self.dismissedKey)
    }

    /// Judges open loops for everyone not judged yet, so promises reach the home list without opening each person.
    private func judgePromises() {
        guard !checkingPromises else { return }
        checkingPromises = true
        Task {
            while let person = people.first(where: { loops[$0.id] == nil }) {
                _ = await openLoops(for: person)
            }
            checkingPromises = false
        }
    }
```

The `while` loop also picks up people whose loops live sync clears while it is running, so a second call during a run can return early.

- [ ] **Step 3: Start judging after analysis and after sync**

In `analyze()`, after the line `updateMemory(for: people)`, add:

```swift
            judgePromises()
```

In `syncOnce()`, after the closing brace of the `for (id, arrived) in LiveSync.route(...)` loop (the last statement in the function), add:

```swift
        judgePromises()
```

- [ ] **Step 4: Give the preview a question from Mom**

In `preview()`, after the line `model.threads = [2: maya.sorted { $0.date < $1.date }]`, add:

```swift
        model.threads[1] = [
            message(2000, true, "landed, love you", daysAgo: 2, chat: 1),
            message(2001, false, "Are you still coming Sunday? Dad wants to grill", daysAgo: 0.15, chat: 1),
        ]
```

- [ ] **Step 5: Build**

Run: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project Ode.xcodeproj -scheme Ode -destination 'platform=macOS' build 2>&1 | grep -E ' error: |\*\* BUILD'`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 6: Commit**

```bash
git add Ode/AppModel.swift
git commit -m "feat(app): assemble the waiting list and judge promises in the background"
```

---

### Task 4: The Waiting on You screen

**Files:**
- Create: `Ode/WaitingView.swift`
- Modify: `Ode/MainView.swift`. Add `home` state; route the center pane; pass home state to `Sidebar`; add the sidebar entry.

**Interfaces:**
- Consumes: `AppModel.waiting`, `AppModel.checkingPromises`, `AppModel.dismiss(_:)` from Task 3; `Waiting` from Tasks 1 and 2; the existing `Avatar`, `AccentButtonStyle`, `Theme`, `DraftComposerView` and `MainView.DraftRequest`.
- Produces: `struct WaitingView: View` with `init(model: AppModel, reply: @escaping (PersonHealth, String) -> Void, open: @escaping (Int64) -> Void)`.

- [ ] **Step 1: Create the view**

Create `Ode/WaitingView.swift`:

```swift
import OdeCore
import SwiftUI

/// The home list: who is waiting to hear from you, most urgent first.
struct WaitingView: View {
    let model: AppModel
    let reply: (PersonHealth, String) -> Void
    let open: (Int64) -> Void

    var body: some View {
        let items = model.waiting
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Waiting on you").font(.system(size: 22, weight: .semibold)).tracking(-0.4)
                    Text("Watching \(model.people.count) conversations").foregroundStyle(Theme.muted)
                }
                .padding(.bottom, 12)
                if items.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Nobody's waiting on you").font(.system(size: 17, weight: .semibold))
                        Text("When someone needs a reply, or you promised them something, they'll show up here.")
                            .foregroundStyle(Theme.secondary)
                    }
                    .padding(.vertical, 24)
                }
                ForEach(items) { item in
                    if let person = model.people.first(where: { $0.id == item.conversationID }) {
                        row(item, person)
                        Divider().overlay(Theme.hairline)
                    }
                }
                if model.checkingPromises {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text("Checking promises")
                    }
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.muted)
                    .padding(.top, 16)
                }
            }
            .padding(28)
            .frame(maxWidth: 760, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Theme.surface)
    }

    private func row(_ item: Waiting, _ person: PersonHealth) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Avatar(title: person.title, size: 36)
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(person.title).font(.system(size: 15, weight: .semibold)).lineLimit(1)
                    Text(Self.label(item.kind).uppercased())
                        .font(.system(size: 10, weight: .semibold))
                        .tracking(0.8)
                        .foregroundStyle(item.kind == .asked ? Theme.accent : Theme.muted)
                    Spacer()
                    Text(item.since, format: .relative(presentation: .named))
                        .font(Theme.mono(11))
                        .foregroundStyle(Theme.muted)
                }
                Text(item.text).font(.system(size: 14)).foregroundStyle(Theme.secondary).lineLimit(2)
                HStack(spacing: 8) {
                    Button("Reply") { reply(person, item.steer) }.buttonStyle(AccentButtonStyle())
                    Button("Open thread") { open(person.id) }
                    Button("Done") { model.dismiss(item) }
                }
                .padding(.top, 6)
            }
        }
        .padding(.vertical, 16)
    }

    static func label(_ kind: Waiting.Kind) -> String {
        switch kind {
        case .asked: "Asked you"
        case .unanswered: "Unanswered"
        case .promised: "You promised"
        case .quiet: "Gone quiet"
        }
    }
}

#Preview {
    WaitingView(model: .preview(), reply: { _, _ in }, open: { _ in })
        .frame(width: 900, height: 640)
        .foregroundStyle(Theme.ink)
        .preferredColorScheme(.light)
}
```

- [ ] **Step 2: Make it the default center pane**

In `Ode/MainView.swift`:

1. Below `@State private var showingSettings = false`, add:

```swift
    @State private var home = true
```

2. Replace the `Sidebar(...)` call in `body`:

```swift
                Sidebar(model: model, selection: selected?.id) { id in
                    selection = id
                    draftRequest = nil
                    focus = nil
                    results = nil
                }
```

with:

```swift
                Sidebar(model: model, selection: home ? nil : selected?.id, home: home, showHome: {
                    home = true
                    draftRequest = nil
                    focus = nil
                    results = nil
                }) { id in
                    selection = id
                    home = false
                    draftRequest = nil
                    focus = nil
                    results = nil
                }
```

3. In the same `HStack`, replace:

```swift
                } else if let person = selected {
                    center(person)
```

with:

```swift
                } else if home {
                    WaitingView(model: model, reply: { person, steer in
                        draftRequest = DraftRequest(person: person, steer: steer)
                    }, open: { id in
                        selection = id
                        tab = .thread
                        home = false
                    })
                } else if let person = selected {
                    center(person)
```

4. In `open(_ result: MemoryResult)`, add `home = false` as the first line of the function body.

- [ ] **Step 3: Add the sidebar entry**

In `private struct Sidebar` in `Ode/MainView.swift`:

1. Below `let selection: Int64?`, add:

```swift
    let home: Bool
    let showHome: () -> Void
```

2. In `body`, make `homeEntry` the first child of `VStack(alignment: .leading, spacing: 20)`, directly before `let individuals = ...`:

```swift
                    homeEntry
```

3. Add this property to `Sidebar`, after `body`:

```swift
    private var homeEntry: some View {
        let count = model.waiting.count
        return Button(action: showHome) {
            HStack(spacing: 10) {
                Image(systemName: "tray").font(.system(size: 14)).frame(width: 32, height: 32)
                Text("Waiting on you").font(.system(size: 14, weight: .medium))
                Spacer()
                if count > 0 {
                    Text("\(count)")
                        .font(Theme.mono(11))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 7)
                        .frame(height: 18)
                        .background(Theme.accent, in: .capsule)
                }
            }
            .padding(8)
            .background(home ? Theme.surface : .clear, in: .rect(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(home ? Theme.hairline : .clear))
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Waiting on you, \(count)")
    }
```

- [ ] **Step 4: Build**

Run: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project Ode.xcodeproj -scheme Ode -destination 'platform=macOS' build 2>&1 | grep -E ' error: |\*\* BUILD'`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 5: Manual check against real data**

Run the app from Xcode and confirm:
- It opens on "Waiting on you", the sidebar entry is highlighted, and the badge count matches the number of rows.
- Rows appear for real conversations where the other person wrote last. A closer like "ok" or "thanks" does not produce a row.
- "Checking promises" shows, then promised rows appear, for people with no unanswered message.
- Reply opens the composer with the steer filled in; closing it returns to the list.
- Open thread jumps to that person's Thread tab.
- Done removes the row, and it stays gone after quitting and relaunching.
- Reply to someone on the list from your phone: the row disappears within about 5 seconds (live sync).

- [ ] **Step 6: Commit**

```bash
git add Ode/WaitingView.swift Ode/MainView.swift
git commit -m "feat(app): waiting on you is the home screen"
```
