import Foundation
import SalaryCore

@main
struct SalaryCalculatorTests {
    @MainActor static func main() async {
        let suite = SalaryCalculatorTests()
        suite.testBeforeWorkAndAfterWork()
        suite.testLunchPausesEarnings()
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
private func XCTAssertFalse(_ value: Bool) {
    precondition(!value, "Expected invalid settings")
}
