import Foundation

/// Annual mainland China holiday adjustments, compatible with holiday-cn JSON.
public struct HolidayYear: Codable, Equatable {
    public struct Day: Codable, Equatable {
        public let name: String
        public let date: String
        public let isOffDay: Bool
    }
    public let year: Int
    public let days: [Day]

    public func validate(expectedYear: Int) throws {
        guard year == expectedYear, !days.isEmpty,
              Set(days.map(\.date)).count == days.count else { throw HolidayError.invalidData }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        for day in days {
            let parts = day.date.split(separator: "-").compactMap { Int($0) }
            guard parts.count == 3, parts[0] == year,
                  let date = calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2])),
                  calendar.component(.year, from: date) == parts[0],
                  calendar.component(.month, from: date) == parts[1],
                  calendar.component(.day, from: date) == parts[2],
                  day.date == String(format: "%04d-%02d-%02d", parts[0], parts[1], parts[2]) else {
                throw HolidayError.invalidData
            }
        }
    }

    public func summary(month: Int) -> WorkdaySummary? {
        guard (1...12).contains(month) else { return nil }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        guard let first = calendar.date(from: DateComponents(year: year, month: month, day: 1)),
              let range = calendar.range(of: .day, in: .month, for: first) else { return nil }
        let overrides = Dictionary(days.map { ($0.date, $0.isOffDay) }, uniquingKeysWith: { _, last in last })
        var weekdays = 0
        var removed = 0
        var added = 0
        for day in range {
            guard let date = calendar.date(from: DateComponents(year: year, month: month, day: day)) else { continue }
            let weekday = calendar.component(.weekday, from: date)
            let usualWorkday = weekday != 1 && weekday != 7
            if usualWorkday { weekdays += 1 }
            let key = String(format: "%04d-%02d-%02d", year, month, day)
            if let off = overrides[key] {
                if usualWorkday && off { removed += 1 }
                if !usualWorkday && !off { added += 1 }
            }
        }
        return WorkdaySummary(year: year, month: month, weekdays: weekdays, holidays: removed, makeupDays: added)
    }

    public func monthCalendar(month: Int, overrides: [String: Bool] = [:]) -> WorkMonth? {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        guard (1...12).contains(month),
              let first = calendar.date(from: DateComponents(year: year, month: month, day: 1)),
              let range = calendar.range(of: .day, in: .month, for: first) else { return nil }
        let adjustments = Dictionary(days.map { ($0.date, $0) }, uniquingKeysWith: { _, last in last })
        let dates = range.map { day -> WorkCalendarDay in
            let date = calendar.date(from: DateComponents(year: year, month: month, day: day))!
            let weekday = calendar.component(.weekday, from: date)
            let key = String(format: "%04d-%02d-%02d", year, month, day)
            let adjustment = adjustments[key]
            let baseline = adjustment.map { !$0.isOffDay } ?? (weekday != 1 && weekday != 7)
            return WorkCalendarDay(day: day, date: key, isWorkday: overrides[key] ?? baseline,
                                   defaultIsWorkday: baseline, holidayName: adjustment?.name)
        }
        return WorkMonth(year: year, month: month,
                         leadingSpaces: (calendar.component(.weekday, from: first) + 5) % 7, days: dates)
    }
}

public struct WorkCalendarDay: Identifiable, Equatable {
    public let day: Int
    public let date: String
    public let isWorkday: Bool
    public let defaultIsWorkday: Bool
    public let holidayName: String?
    public var id: String { date }
    public var isCustomized: Bool { isWorkday != defaultIsWorkday }
}

public struct WorkMonth: Equatable {
    public let year: Int
    public let month: Int
    public let leadingSpaces: Int
    public let days: [WorkCalendarDay]
    public internal(set) var isEstimated = false
    public var workdays: Int { days.filter(\.isWorkday).count }
}

public struct WorkdaySummary: Equatable {
    public let year: Int
    public let month: Int
    public let weekdays: Int
    public let holidays: Int
    public let makeupDays: Int
    public var total: Int { weekdays - holidays + makeupDays }
}

public enum HolidayError: Error {
    case invalidData
}
