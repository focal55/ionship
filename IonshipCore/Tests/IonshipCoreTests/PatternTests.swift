import Foundation
import Testing
@testable import IonshipCore

private let calendar: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "America/New_York")!
    return calendar
}()

/// A conversation of `length` alternating messages starting at the given weekday and hour,
/// `weeksAgo` weeks back. `replyGap` is your delay after each of their messages.
private func session(_ startID: Int64, weeksAgo: Int, weekday: Int, hour: Int, length: Int, theyStart: Bool = true,
                     replyGap: TimeInterval = 120) -> [Message] {
    let reference = calendar.date(from: DateComponents(year: 2026, month: 10, day: 4, hour: hour))! // a Sunday
    let day = calendar.date(byAdding: .day, value: weekday - 1 - weeksAgo * 7, to: reference)!
    var at = day
    return (0..<length).map { index in
        let fromMe = theyStart ? !index.isMultiple(of: 2) : index.isMultiple(of: 2)
        at = at.addingTimeInterval(fromMe ? replyGap : 60)
        return Message(id: startID + Int64(index), guid: "\(startID + Int64(index))", chatID: 1, sender: fromMe ? nil : "x",
                       isFromMe: fromMe, date: at, text: "msg", textSource: .column, kind: .text)
    }
}

private let now = calendar.date(from: DateComponents(year: 2026, month: 10, day: 8, hour: 12))!

@Suite struct PatternTests {
    @Test func theDayLongConversationsHappenOn() {
        var messages: [Message] = []
        for week in 1...10 { messages += session(Int64(week * 1000), weeksAgo: week, weekday: 1, hour: 19, length: 30) }
        for week in 1...3 { messages += session(Int64(50_000 + week * 1000), weeksAgo: week, weekday: 4, hour: 19, length: 30) }
        let pattern = Patterns.find(in: messages, calendar: calendar, now: now).first { $0.kind == .longTalkDay }
        #expect(pattern?.title == "Sunday is when real conversations happen")
        #expect(pattern?.detail == "77% of your conversations longer than 20 messages start on a Sunday.")
        #expect(pattern?.momentIDs.count == 10)
    }

    @Test func quickRepliesMakeLongerConversations() {
        var messages: [Message] = []
        for week in 1...8 { messages += session(Int64(week * 1000), weeksAgo: week, weekday: 2, hour: 12, length: 24, replyGap: 300) }
        for week in 1...8 { messages += session(Int64(50_000 + week * 1000), weeksAgo: week, weekday: 5, hour: 12, length: 4, replyGap: 3 * 3600) }
        let pattern = Patterns.find(in: messages, calendar: calendar, now: now).first { $0.kind == .replySpeed }
        #expect(pattern?.title == "Quick replies keep you talking")
        #expect(pattern?.detail == "When you reply within an hour, conversations run 6× longer.")
    }

    @Test func timeOfDay() {
        var messages: [Message] = []
        for week in 1...12 { messages += session(Int64(week * 1000), weeksAgo: week, weekday: 3, hour: 23, length: 6) }
        let pattern = Patterns.find(in: messages, calendar: calendar, now: now).first { $0.kind == .timeOfDay }
        #expect(pattern?.title == "Mostly late-night conversations")
    }

    @Test func aShiftInWhoStarts() {
        var messages: [Message] = []
        for week in 60...80 { messages += session(Int64(week * 1000), weeksAgo: week, weekday: 3, hour: 12, length: 4, theyStart: week.isMultiple(of: 2)) }
        for week in 1...20 { messages += session(Int64(200_000 + week * 1000), weeksAgo: week, weekday: 3, hour: 12, length: 4, theyStart: true) }
        let pattern = Patterns.find(in: messages, calendar: calendar, now: now).first { $0.kind == .initiationShift }
        #expect(pattern?.title == "They start more than they used to")
    }

    @Test func tooLittleHistoryFindsNothing() {
        #expect(Patterns.find(in: session(1, weeksAgo: 1, weekday: 1, hour: 12, length: 4), calendar: calendar, now: now).isEmpty)
    }
}
