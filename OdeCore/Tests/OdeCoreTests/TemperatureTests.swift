import Foundation
import Testing
@testable import OdeCore

private let now = Date(timeIntervalSinceReferenceDate: 800_000_000)
private let day: TimeInterval = 86_400

/// `perWeek` exchanges a week for `weeks` weeks ending `endingDaysAgo`, each a message from
/// them and a reply from you `replyAfter` seconds later with `myText`.
private func history(weeks: Int, perWeek: Int, endingDaysAgo: Double = 0, myText: String = "sounds good, see you then",
                     replyAfter: TimeInterval = 300, startID: Int64 = 0) -> [Message] {
    var messages: [Message] = []
    var id = startID
    for week in 0..<weeks {
        for n in 0..<perWeek {
            let at = now.addingTimeInterval(-(endingDaysAgo + Double(week) * 7 + Double(n) * 7 / Double(perWeek)) * day)
            id += 1
            messages.append(Message(id: id, guid: "\(id)", chatID: 1, sender: "x", isFromMe: false, date: at, text: "hey", textSource: .column, kind: .text))
            id += 1
            messages.append(Message(id: id, guid: "\(id)", chatID: 1, sender: nil, isFromMe: true, date: at.addingTimeInterval(replyAfter),
                                    text: myText, textSource: .column, kind: .text))
        }
    }
    return messages
}

@Suite struct TemperatureTests {
    @Test func steadyFrequentQuickContactIsWarmAndSteady() {
        let temperature = Temperature(of: history(weeks: 26, perWeek: 6), now: now)
        #expect(temperature.level == .warm)
        #expect(temperature.trend == .steady)
        #expect(temperature.sparkline.count == 12)
    }

    @Test func fallingVolumeAndShorterRepliesIsCooling() {
        let before = history(weeks: 20, perWeek: 6, endingDaysAgo: 28, startID: 0)
        let lately = history(weeks: 4, perWeek: 1, myText: "ok", replyAfter: 6 * 3600, startID: 10_000)
        let temperature = Temperature(of: before + lately, now: now)
        #expect(temperature.trend == .cooling)
        #expect(temperature.reason == "Your replies are shorter and slower than usual lately.")
    }

    @Test func pickingBackUpIsWarming() {
        let before = history(weeks: 20, perWeek: 1, endingDaysAgo: 28, startID: 0)
        let lately = history(weeks: 4, perWeek: 8, startID: 10_000)
        #expect(Temperature(of: before + lately, now: now).trend == .warming)
    }

    @Test func rareContactIsCool() {
        #expect(Temperature(of: history(weeks: 26, perWeek: 1, endingDaysAgo: 0).filter { $0.id % 8 < 2 }, now: now).level == .cool)
    }

    @Test func noHistoryIsQuiet() {
        let temperature = Temperature(of: [], now: now)
        #expect(temperature.level == .quiet)
        #expect(temperature.label == "Quiet")
    }

    @Test func labelCombinesLevelAndTrend() {
        let before = history(weeks: 20, perWeek: 6, endingDaysAgo: 28)
        let lately = history(weeks: 4, perWeek: 4, myText: "ok", replyAfter: 4 * 3600, startID: 10_000)
        let temperature = Temperature(of: before + lately, now: now)
        #expect(temperature.label == "\(temperature.level.rawValue), \(temperature.trend.rawValue)".capitalizedFirst)
    }
}

@Suite struct ScopedMemorySearchTests {
    @Test func searchCanBeLimitedToOneConversationAndAge() throws {
        let path = FileManager.default.temporaryDirectory.appendingPathComponent("memory-\(UUID().uuidString)/m.sqlite").path
        let index = try MemoryIndex(path: path)
        let old = Date(timeIntervalSinceReferenceDate: 700_000_000)
        try index.add([
            Moment(conversationID: 1, firstMessageID: 1, lastMessageID: 2, start: old, end: old, text: "trip photos"),
            Moment(conversationID: 2, firstMessageID: 3, lastMessageID: 4, start: old, end: old, text: "trip photos"),
            Moment(conversationID: 1, firstMessageID: 5, lastMessageID: 6, start: now, end: now, text: "trip photos again"),
        ], embedder: WordEmbedder())
        let hits = try index.search("photos", embedder: WordEmbedder(), limit: 5, conversationID: 1, endingBefore: now.addingTimeInterval(-day))
        #expect(hits.map(\.moment.firstMessageID) == [1])
    }
}
