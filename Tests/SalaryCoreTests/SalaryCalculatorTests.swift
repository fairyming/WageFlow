import Foundation
import SalaryCore

@main
struct SalaryCalculatorTests {
    @MainActor static func main() async {
        let suite = SalaryCalculatorTests()
        suite.testBeforeWorkAndAfterWork()
        suite.testLunchPausesEarnings()
        suite.testLunchBreakWindow()
        suite.testWeekendHasNoEarnings()
        suite.testCyclesAndEffectivePay()
        suite.testInvalidSchedules()
        checkHolidayCalendars()
        checkWorkCalendarSelection()
        await checkCalendarSync()
        print("Passed salary, holiday-calendar, and monthly-sync checks")
    }
    private var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(secondsFromGMT: 0)!
        return c
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
