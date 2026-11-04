import Foundation
import SalaryCore

func checkHolidayCalendars() {
    // Synthetic adjustments exercise the algorithm, not the official 2026 schedule.
    let fixture = #"{"year":2026,"days":[{"name":"测试放假","date":"2026-11-02","isOffDay":true},{"name":"测试补班","date":"2026-11-07","isOffDay":false},{"name":"周末休息","date":"2026-11-08","isOffDay":true},{"name":"正常工作日","date":"2026-11-03","isOffDay":false}]}"#
    let decoder = JSONDecoder()
    let calendar = try! decoder.decode(HolidayYear.self, from: Data(fixture.utf8))
    try! calendar.validate(expectedYear: 2026)
    let november = calendar.summary(month: 11)!
    precondition(november.weekdays == 21)
    precondition(november.holidays == 1 && november.makeupDays == 1 && november.total == 21)
    let december = calendar.summary(month: 12)!
    precondition(december.weekdays == 23 && december.total == 23)
    precondition(calendar.summary(month: 13) == nil)
    precondition((try? calendar.validate(expectedYear: 2027)) == nil)

    for invalid in [
        #"{"year":2026,"days":[]}"#,
        #"{"year":2026,"days":[{"name":"bad","date":"2026-02-30","isOffDay":true}]}"#,
        #"{"year":2026,"days":[{"name":"bad","date":"2027-01-01","isOffDay":true}]}"#,
        #"{"year":2026,"days":[{"name":"a","date":"2026-11-02","isOffDay":true},{"name":"b","date":"2026-11-02","isOffDay":false}]}"#
    ] {
        let decoded = try! decoder.decode(HolidayYear.self, from: Data(invalid.utf8))
        precondition((try? decoded.validate(expectedYear: 2026)) == nil)
    }

    let leap = try! decoder.decode(HolidayYear.self, from: Data(#"{"year":2024,"days":[{"name":"测试","date":"2024-02-29","isOffDay":true}]}"#.utf8))
    try! leap.validate(expectedYear: 2024)
    precondition(leap.summary(month: 2)!.weekdays == 21 && leap.summary(month: 2)!.total == 20)

    // Legacy numeric settings migrate to the fetched date calendar, retaining salary.
    let legacy = try! decoder.decode(WorkSettings.self, from: Data(#"{"income":9000,"workdays":22}"#.utf8))
    precondition(legacy.workdayOverrides.isEmpty && legacy.income == 9000 && legacy.workdays == 22)
    let automatic = legacy
    let restored = try! decoder.decode(WorkSettings.self, from: JSONEncoder().encode(automatic))
    precondition(restored == automatic && restored.workdays == 22)
}
