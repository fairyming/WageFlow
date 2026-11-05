import Foundation
import SalaryCore

@main
struct SalaryCalculatorTests {
    @MainActor static func main() async {
        let suite = SalaryCalculatorTests()
        suite.testBeforeWorkAndAfterWork()
        suite.testLunchPausesEarnings()
        suite.testLunchBreakWindow()
        suite.testAfterWorkWindow()
        suite.testWeekendHasNoEarnings()
        suite.testCyclesAndEffectivePay()
        suite.testInvalidSchedules()
        suite.testAppearanceSettings()
        checkHolidayCalendars()
        checkWorkCalendarSelection()
        checkTimeCode()
        await checkCalendarSync()
        print("Passed salary, holiday-calendar, monthly-sync, and time-entry checks")
    }
    private var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(secondsFromGMT: 0)!
        return c
    }
    func testAppearanceSettings() {
        let legacy = try! JSONDecoder().decode(WorkSettings.self, from: Data("{}".utf8))
        precondition(legacy.dashboardOpacity == 1)
        let migrated = try! JSONDecoder().decode(WorkSettings.self, from: Data(#"{"dashboardOpacity":0.45,"income":12345}"#.utf8))
        precondition(migrated.dashboardOpacity == 1 && migrated.income == 12345)
        var settings = legacy
        settings.dashboardTransparency = 0.4
        let restored = try! JSONDecoder().decode(WorkSettings.self, from: JSONEncoder().encode(settings))
        precondition(restored == settings && restored.valid)
        for invalid in [-0.01, 0.41, 1.01, Double.nan, Double.infinity] {
            settings.dashboardTransparency = invalid
            precondition(!settings.valid)
        }
    }
    private func snapshot(_ hour: Int, _ minute: Int = 0, day: Int = 2) -> WorkSnapshot {
        let date = calendar.date(from: DateComponents(year: 2026, month: 11, day: day, hour: hour, minute: minute))!
        return WorkSnapshot(settings: WorkSettings(), now: date, calendar: calendar, isWorkday: day == 2)
    }
    private func onLunch(_ settings: WorkSettings, _ hour: Int, _ minute: Int) -> WorkSnapshot {
        let date = calendar.date(from: DateComponents(year: 2026, month: 11, day: 2, hour: hour, minute: minute))!
        return WorkSnapshot(settings: settings, now: date, calendar: calendar, isWorkday: true)
    }
    func testBeforeWorkAndAfterWork() {
        XCTAssertEqual(snapshot(8).earned, 0)
        XCTAssertEqual(snapshot(19).progress, 1)
        XCTAssertEqual(snapshot(19).remaining, 0)
    }
    func testLunchPausesEarnings() {
        XCTAssertEqual(snapshot(12).earned, snapshot(12, 45).earned)
        XCTAssertEqual(snapshot(13).progress, 3.0 / 8.0, accuracy: 0.0001)
        XCTAssertEqual(snapshot(14).progress, 0.5, accuracy: 0.0001)
    }
    func testLunchBreakWindow() {
        XCTAssertTrue(snapshot(12).isLunchBreak)
        XCTAssertTrue(snapshot(12, 59).isLunchBreak)
        XCTAssertFalse(snapshot(11, 59).isLunchBreak)
        XCTAssertFalse(snapshot(13).isLunchBreak)
        XCTAssertFalse(snapshot(12, day: 1).isLunchBreak, "休息日没有午休")
        XCTAssertEqual(snapshot(12).lunchRemaining, 3600, accuracy: 0.001)
        XCTAssertEqual(snapshot(12, 30).lunchRemaining, 1800, accuracy: 0.001)
        XCTAssertEqual(snapshot(12, 30).status, "午休中，给自己充个电")
        // A break later in the shift pages only inside its own window.
        var late = WorkSettings()
        late.start = 10 * 60
        late.end = 19 * 60
        late.lunchStart = 14 * 60
        late.lunchEnd = 15 * 60
        XCTAssertFalse(onLunch(late, 13, 30).isLunchBreak)
        XCTAssertTrue(onLunch(late, 14, 30).isLunchBreak)
        XCTAssertFalse(onLunch(late, 15, 30).isLunchBreak)
        // A zero-length lunch is a disabled break, never an all-day page.
        var disabled = WorkSettings()
        disabled.lunchEnd = disabled.lunchStart
        XCTAssertFalse(onLunch(disabled, 12, 30).isLunchBreak)
        XCTAssertEqual(onLunch(disabled, 12, 30).lunchRemaining, 0)
        XCTAssertEqual(onLunch(disabled, 12, 30).status, "正在赚钱，每一秒都算数")
        // Invalid schedules must not surface a break page either.
        var invalid = WorkSettings()
        invalid.end = invalid.start
        XCTAssertFalse(onLunch(invalid, 12, 30).isLunchBreak)
    }
    func testAfterWorkWindow() {
        XCTAssertFalse(snapshot(17, 59).isAfterWork)
        XCTAssertTrue(snapshot(18).isAfterWork)
        XCTAssertTrue(snapshot(23).isAfterWork)
        XCTAssertFalse(snapshot(12, 30).isAfterWork)
        XCTAssertFalse(snapshot(8).isAfterWork)
        XCTAssertFalse(snapshot(18, day: 1).isAfterWork)
        XCTAssertEqual(snapshot(19).earned, WorkSettings().dailyPay, accuracy: 0.001)
        XCTAssertEqual(snapshot(18).status, "今日收工，辛苦啦！")
    }
    func testWeekendHasNoEarnings() {
        XCTAssertEqual(snapshot(15, day: 1).earned, 0)
        XCTAssertEqual(snapshot(15, day: 1).remaining, 0)
    }
    func testCyclesAndEffectivePay() {
        var s = WorkSettings()
        s.cycle = .hourly
        s.income = 100
        XCTAssertEqual(s.dailyPay, 800)
        XCTAssertEqual(s.effectiveHourlyPay, 77)
        s.cycle = .daily
        XCTAssertEqual(s.dailyPay, 100)
    }
    func testInvalidSchedules() {
        var s = WorkSettings()
        s.end = s.start
        XCTAssertFalse(s.valid)
        s = WorkSettings()
        s.workdays = -1
        XCTAssertFalse(s.valid)
        s = WorkSettings()
        s.lunchEnd = s.end + 1
        XCTAssertFalse(s.valid)
    }
}

private func XCTAssertEqual(_ actual: Double, _ expected: Double, accuracy: Double = 0.000001) {
    precondition(abs(actual - expected) <= accuracy, "Expected \(expected), got \(actual)")
}
private func XCTAssertEqual(_ actual: String, _ expected: String) {
    precondition(actual == expected, "Expected \(expected), got \(actual)")
}
private func XCTAssertFalse(_ value: Bool, _ message: String = "") {
    precondition(!value, "Expected false. \(message)")
}
private func XCTAssertTrue(_ value: Bool, _ message: String = "") {
    precondition(value, "Expected true. \(message)")
}
