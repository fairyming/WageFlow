import Foundation
import SalaryCore

func checkWorkCalendarSelection() {
    let json = #"{"year":2026,"days":[{"name":"测试放假","date":"2026-11-02","isOffDay":true},{"name":"测试补班","date":"2026-11-07","isOffDay":false}]}"#
    let decoder = JSONDecoder()
    let holidays = try! decoder.decode(HolidayYear.self, from: Data(json.utf8))
    var settings = WorkSettings()
    precondition(settings.workdayOverrides.isEmpty)
    let automatic = settings.monthCalendar(year: 2026, month: 11, holidays: holidays)!
    precondition(automatic.days.count == 30 && automatic.leadingSpaces == 6 && automatic.workdays == 21)
    precondition(!automatic.days[1].isWorkday && automatic.days[6].isWorkday)
    precondition(settings.monthCalendar(year: 2027, month: 11, holidays: holidays) == nil)
    precondition(settings.monthCalendar(year: 2026, month: 11, holidays: nil) == nil)
    let fallback = settings.monthCalendar(year: 2026, month: 11, holidays: nil, fallbackToWeekdays: true)!
    precondition(fallback.workdays == 21 && fallback.isEstimated && fallback.days[1].isWorkday && !fallback.days[6].isWorkday)

    precondition(settings.monthCalendar(year: 2026, month: 11, holidays: holidays) == automatic)
    settings.toggleWorkday(automatic.days[1])
    let custom = settings.monthCalendar(year: 2026, month: 11, holidays: holidays)!
    precondition(custom.workdays == 22 && custom.days[1].isCustomized)
    precondition(settings.monthCalendar(year: 2026, month: 12, holidays: holidays)!.workdays == 23)
    let restored = try! decoder.decode(WorkSettings.self, from: JSONEncoder().encode(settings))
    precondition(restored == settings && restored.workdayOverrides["2026-11-02"] == true)

    // Official data refreshes untouched dates without overwriting explicit choices.
    let update = json.replacingOccurrences(of: "]}", with: #",{"name":"新补班","date":"2026-11-08","isOffDay":false}]}"#)
    let newer = try! decoder.decode(HolidayYear.self, from: Data(update.utf8))
    precondition(settings.monthCalendar(year: 2026, month: 11, holidays: newer)!.workdays == 23)
    settings.toggleWorkday(custom.days[1])
    precondition(settings.workdayOverrides.isEmpty, "Toggling back restores the fetched default")
    settings.toggleWorkday(automatic.days[1])
    settings.workdayOverrides["2026-12-01"] = false
    settings.resetWorkdays(year: 2026, month: 11)
    precondition(settings.monthCalendar(year: 2026, month: 11, holidays: holidays) == automatic)
    precondition(settings.workdayOverrides == ["2026-12-01": false], "Reset only clears the displayed month")
    settings.resetWorkdays(year: 2026, month: 12)

    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    let saturday = calendar.date(from: DateComponents(year: 2026, month: 11, day: 7, hour: 14))!
    let monday = calendar.date(from: DateComponents(year: 2026, month: 11, day: 2, hour: 14))!
    let paidSaturday = WorkSnapshot(settings: settings, now: saturday, calendar: calendar, isWorkday: automatic.days[6].isWorkday)
    let offMonday = WorkSnapshot(settings: settings, now: monday, calendar: calendar, isWorkday: automatic.days[1].isWorkday)
    precondition(paidSaturday.earned > 0 && paidSaturday.progress == 0.5)
    precondition(offMonday.earned == 0 && offMonday.remaining == 0)

    settings.workdayOverrides = Dictionary(uniqueKeysWithValues: automatic.days.map { ($0.date, false) })
    settings.workdays = Double(settings.monthCalendar(year: 2026, month: 11, holidays: holidays)!.workdays)
    precondition(settings.valid && settings.workdays == 0 && settings.dailyPay == 0 && settings.effectiveHourlyPay == 0)
    let allRest = WorkSnapshot(settings: settings, now: saturday, calendar: calendar, isWorkday: false)
    precondition(allRest.earned == 0 && allRest.progress == 0)

    let legacy = try! decoder.decode(WorkSettings.self, from: Data(#"{"income":12000,"workdayMode":"手动填写","weekdays":[2,3,4],"workdays":21.75}"#.utf8))
    precondition(legacy.income == 12000 && legacy.workdayOverrides.isEmpty)
    let encoded = try! JSONSerialization.jsonObject(with: JSONEncoder().encode(legacy)) as! [String: Any]
    precondition(encoded["weekdays"] == nil && encoded["workdayMode"] == nil)
    let active = try! decoder.decode(WorkSettings.self, from: Data(#"{"workdayMode":"手动填写","workdayOverrides":{"2026-11-02":true}}"#.utf8))
    precondition(active.workdayOverrides["2026-11-02"] == true)
    let inactive = try! decoder.decode(WorkSettings.self, from: Data(#"{"workdayMode":"自动获取当月工作日","workdayOverrides":{"2026-11-02":true}}"#.utf8))
    precondition(inactive.workdayOverrides.isEmpty)
}
