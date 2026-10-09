import Foundation
import Testing
@testable import OdeCore

private func t(_ id: Int64, _ sender: String?, _ date: Date, text: String? = "hi", kind: Message.Kind = .text) -> Message {
    Message(id: id, guid: "g\(id)", chatID: 1, sender: sender, isFromMe: sender == nil, date: date,
            text: text, textSource: .column, kind: kind)
}

@Suite struct ThreadTimelineTests {
    let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York")!
        return calendar
    }()

    func date(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour, minute: minute))!
    }

    @Test func dayDividersSeparateCalendarDays() {
        let items = ThreadTimeline.items(for: [t(1, "A", date(1, 23)), t(2, nil, date(2, 0, 30)), t(3, "A", date(2, 9))],
                                         isGroup: false, calendar: calendar)
        #expect(items.map(\.kind) == [.day, .message, .day, .message, .message])
        #expect(items[2].date == calendar.startOfDay(for: date(2, 0)))
    }

    @Test func reactionsAndSystemRowsAreHidden() {
        let items = ThreadTimeline.items(for: [
            t(1, "A", date(1, 9)), t(2, nil, date(1, 9, 1), kind: .reaction), t(3, "A", date(1, 9, 2), kind: .other),
        ], isGroup: false, calendar: calendar)
        #expect(items.filter { $0.kind == .message }.map(\.message?.id) == [1])
    }

    @Test func groupsLabelASenderOnlyWhenTheSpeakerChanges() {
        let items = ThreadTimeline.items(for: [
            t(1, "A", date(1, 9)), t(2, "A", date(1, 9, 1)), t(3, "B", date(1, 9, 2)), t(4, nil, date(1, 9, 3)), t(5, "A", date(1, 9, 4)),
        ], isGroup: true, calendar: calendar).filter { $0.kind == .message }
        #expect(items.map(\.showsSender) == [true, false, true, false, true])
    }

    @Test func oneToOneThreadsNeverLabelSenders() {
        let items = ThreadTimeline.items(for: [t(1, "A", date(1, 9)), t(2, nil, date(1, 9, 1))], isGroup: false, calendar: calendar)
        #expect(items.allSatisfy { !$0.showsSender })
    }

    @Test func outOfOrderInputIsSortedAndAttachmentsKept() {
        let items = ThreadTimeline.items(for: [t(2, nil, date(1, 10), text: nil, kind: .attachmentOnly), t(1, "A", date(1, 9))],
                                         isGroup: false, calendar: calendar)
        #expect(items.compactMap(\.message?.id) == [1, 2])
    }

    @Test func idsAreUniqueAcrossDividersAndMessages() {
        let items = ThreadTimeline.items(for: [t(1, "A", date(1, 9)), t(2, "A", date(2, 9))], isGroup: false, calendar: calendar)
        #expect(Set(items.map(\.id)).count == items.count)
    }
}
