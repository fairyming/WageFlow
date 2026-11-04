import Foundation
import SalaryCore

@MainActor
private final class SyncFixture {
    var date = localDate(2026, 10, 31, 23, 59)
    var json = #"{"year":2026,"days":[{"name":"测试放假","date":"2026-11-02","isOffDay":true}]}"#
    var status = 200
    var offline = false
    var failedHosts: Set<String> = []
    var invalidHosts: Set<String> = []
    var requests: [URLRequest] = []
    var onRequest: (() -> Void)?

    func download(_ request: URLRequest) async throws -> (Data, URLResponse) {
        requests.append(request)
        onRequest?()
        if offline || failedHosts.contains(request.url!.host!) { throw URLError(.notConnectedToInternet) }
        let body = invalidHosts.contains(request.url!.host!) ? "not JSON" : json
        return (Data(body.utf8), HTTPURLResponse(url: request.url!, statusCode: status,
                                               httpVersion: "HTTP/1.1", headerFields: nil)!)
    }
}

private func localDate(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 12, _ minute: Int = 0) -> Date {
    Calendar(identifier: .gregorian).date(from: DateComponents(year: year, month: month, day: day,
                                                              hour: hour, minute: minute))!
}

@MainActor
func checkCalendarSync() async {
    await checkUnpublishedYearCalendar()
    let suite = "salary-calendar-checks-" + UUID().uuidString
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    let fixture = SyncFixture()
    let store = HolidayCalendarStore(defaults: defaults, now: { fixture.date }, download: fixture.download)

    await store.loadCurrentYear()
    precondition(fixture.requests.count == 1 && store.currentSummary?.total == 22)
    precondition(fixture.requests[0].url!.absoluteString == "https://raw.githubusercontent.com/NateScarlet/holiday-cn/master/2026.json")
    precondition(fixture.requests[0].cachePolicy == .reloadIgnoringLocalCacheData)
    precondition(defaults.dictionary(forKey: "holiday-workdays-2026")?["11"] as? Int == 20)
    let firstUpdate = store.fetchedAt[2026]!
    await store.loadCurrentYear()
    precondition(fixture.requests.count == 1, "Do not download twice in the same month")

    // Crossing into a new month must fetch even if the last success was two minutes ago.
    fixture.date = localDate(2026, 11, 1, 0, 1)
    fixture.json = #"{"year":2026,"days":[{"name":"测试放假","date":"2026-11-02","isOffDay":true},{"name":"新增补班","date":"2026-11-07","isOffDay":false}]}"#
    await store.loadCurrentYear()
    precondition(fixture.requests.count == 2 && store.currentSummary?.total == 21)
    precondition(defaults.dictionary(forKey: "holiday-workdays-2026")?["11"] as? Int == 21)
    let changedAt = store.fetchedAt[2026]!
    precondition(changedAt > firstUpdate && store.checkedAt[2026] == fixture.date)

    fixture.date = localDate(2026, 11, 20)
    await store.loadCurrentYear()
    precondition(fixture.requests.count == 2, "Later days in the same month must not download")
    await store.loadCurrentYear(force: true)
    precondition(fixture.requests.count == 3 && store.fetchedAt[2026] == changedAt)
    precondition(store.checkedAt[2026] == fixture.date, "Unchanged data still counts as a successful check")
    let reloaded = HolidayCalendarStore(defaults: defaults, now: { fixture.date }, download: fixture.download)
    precondition(reloaded.currentSummary?.total == 21)
    await reloaded.loadCurrentYear()
    precondition(fixture.requests.count == 3, "Restarting must preserve this month's successful check")

    fixture.date = localDate(2026, 12, 1)
    fixture.offline = true
    await store.loadCurrentYear()
    precondition(fixture.requests.count == 6 && store.currentSummary?.total == 23 && store.currentError != nil)
    await store.loadCurrentYear()
    precondition(fixture.requests.count == 6, "Failed requests must not loop every minute")
    fixture.date = fixture.date.addingTimeInterval(3600)
    fixture.offline = false
    fixture.json = "not valid JSON"
    await store.loadCurrentYear()
    precondition(fixture.requests.count == 9 && store.currentSummary?.total == 23)
    fixture.date = fixture.date.addingTimeInterval(3600)
    fixture.json = #"{"year":2026,"days":[{"name":"恢复后的日历","date":"2026-12-01","isOffDay":true}]}"#
    await store.loadCurrentYear()
    precondition(fixture.requests.count == 10 && store.currentSummary?.total == 22 && store.currentError == nil)
    await store.loadCurrentYear(force: true)
    precondition(fixture.requests.count == 11, "Manual refresh bypasses the monthly check")

    precondition(store.currentSummary?.total == 22, "December uses the updated monthly total")
    fixture.date = localDate(2027, 1, 1)
    fixture.json = #"{"year":2027,"days":[{"name":"测试元旦","date":"2027-01-01","isOffDay":true}]}"#
    await store.loadCurrentYear()
    precondition(fixture.requests.last!.url!.lastPathComponent == "2027.json")
    precondition(store.currentSummary?.year == 2027 && store.currentSummary?.total == 20)

    // An unavailable new year must never reuse the previous year's totals.
    fixture.date = localDate(2028, 1, 1)
    fixture.status = 404
    await store.loadCurrentYear()
    precondition(store.currentSummary == nil && store.currentError != nil)
    var custom = WorkSettings()
    let fallback = store.monthCalendar(settings: custom, year: 2028, month: 1)!
    precondition(fallback.isEstimated && fallback.workdays == 21)
    precondition(!fallback.days[0].isWorkday && fallback.days[2].isWorkday)
    precondition(defaults.data(forKey: "holiday-calendar-2028") == nil, "Estimated weekdays must not masquerade as fetched data")
    custom.toggleWorkday(fallback.days[0])
    precondition(store.monthCalendar(settings: custom, year: 2028, month: 1)!.workdays == 22)
    fixture.status = 200
    fixture.json = #"{"year":2028,"days":[{"name":"测试假期","date":"2028-01-03","isOffDay":true},{"name":"测试补班","date":"2028-01-08","isOffDay":false}]}"#
    await store.loadCurrentYear(force: true)
    let recovered = store.monthCalendar(settings: custom, year: 2028, month: 1)!
    precondition(!recovered.isEstimated && store.currentError == nil && recovered.workdays == 22)
    precondition(recovered.days[0].isWorkday && recovered.days[0].isCustomized)
    precondition(!recovered.days[2].isWorkday && recovered.days[7].isWorkday)

    // Selecting an uncached year downloads that year, independently of today's year.
    fixture.json = #"{"year":2029,"days":[{"name":"测试假期","date":"2029-01-01","isOffDay":true}]}"#
    await store.loadYear(2029)
    precondition(fixture.requests.last!.url!.lastPathComponent == "2029.json")
    precondition(store.monthCalendar(settings: WorkSettings(), year: 2029, month: 1)?.isEstimated == false)

    // Fall back in order, including when a source returns HTTP 200 with bad JSON.
    fixture.date = localDate(2026, 11, 2)
    fixture.status = 200
    fixture.json = #"{"year":2026,"days":[{"name":"测试放假","date":"2026-11-02","isOffDay":true}]}"#
    fixture.requests.removeAll()
    fixture.failedHosts = ["raw.githubusercontent.com"]
    await store.loadCurrentYear(force: true)
    precondition(fixture.requests.map { $0.url!.host! } == ["raw.githubusercontent.com", "cdn.jsdelivr.net"])
    precondition(store.currentError == nil && store.currentSummary?.total == 20)
    fixture.requests.removeAll()
    fixture.invalidHosts = ["cdn.jsdelivr.net"]
    await store.loadCurrentYear(force: true)
    precondition(fixture.requests.map { $0.url!.host! } == ["raw.githubusercontent.com", "cdn.jsdelivr.net", "fastly.jsdelivr.net"])
    precondition(store.currentError == nil && store.currentSummary?.total == 20)
    fixture.requests.removeAll()
    fixture.failedHosts.removeAll()
    fixture.invalidHosts.removeAll()
    await store.loadCurrentYear(force: true)
    precondition(fixture.requests.count == 1, "A successful primary request must not contact backups")
}

@MainActor
private func checkUnpublishedYearCalendar() async {
    let suite = "salary-unpublished-year-checks-" + UUID().uuidString
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    let fixture = SyncFixture()
    fixture.json = #"{"year":2027,"papers":[],"days":[]}"#
    let store = HolidayCalendarStore(defaults: defaults, now: { fixture.date }, download: fixture.download)
    var settings = WorkSettings()
    settings.workdayOverrides["2027-01-04"] = false
    let initial = store.monthCalendar(settings: settings, year: 2027, month: 1)!
    precondition(initial.isEstimated && initial.days.count == 31 && initial.workdays == 20,
                 "Uncached years must display an editable calendar before any request completes")
    fixture.onRequest = {
        let pending = store.monthCalendar(settings: settings, year: 2027, month: 1)!
        precondition(store.loading.contains(2027) && pending.isEstimated && pending.workdays == 20,
                     "The calendar must remain visible while trying each source")
    }
    await store.loadYear(2027)
    fixture.onRequest = nil
    precondition(fixture.requests.count == 3 && store.errors[2027] != nil)
    precondition(store.years[2027] == nil && defaults.data(forKey: "holiday-calendar-2027") == nil,
                 "HTTP 200 with empty days is unavailable data, not a confirmed holiday calendar")
    precondition(store.monthCalendar(settings: settings, year: 2027, month: 1)?.workdays == 20)
    await store.loadYear(2027)
    precondition(fixture.requests.count == 3, "Keep the retry delay for unpublished calendars")

    let restarted = HolidayCalendarStore(defaults: defaults, now: { fixture.date }, download: fixture.download)
    await restarted.loadYear(2027)
    precondition(fixture.requests.count == 3)
    precondition(restarted.monthCalendar(settings: settings, year: 2027, month: 1)?.isEstimated == true,
                 "Restarting during the retry delay must not leave an empty calendar")

    fixture.json = #"{"year":2027,"days":[{"name":"测试假期","date":"2027-01-01","isOffDay":true},{"name":"测试补班","date":"2027-01-02","isOffDay":false}]}"#
    await restarted.loadYear(2027, force: true)
    let updated = restarted.monthCalendar(settings: settings, year: 2027, month: 1)!
    precondition(!updated.isEstimated && restarted.errors[2027] == nil)
    precondition(!updated.days[0].isWorkday && updated.days[1].isWorkday)
    precondition(!updated.days[3].isWorkday && updated.days[3].isCustomized,
                 "Fetching published holidays must preserve manual edits")
}
