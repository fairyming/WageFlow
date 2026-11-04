import Foundation
import Combine

@MainActor
public final class HolidayCalendarStore: ObservableObject {
    @Published public private(set) var years: [Int: HolidayYear] = [:]
    @Published public private(set) var loading: Set<Int> = []
    @Published public private(set) var errors: [Int: String] = [:]
    @Published public private(set) var fetchedAt: [Int: Date] = [:]
    @Published public private(set) var checkedAt: [Int: Date] = [:]
    @Published public private(set) var summaries: [Int: [Int: WorkdaySummary]] = [:]
    @Published public private(set) var fallbackYears: Set<Int> = []
    private var attemptedAt: [Int: Date] = [:]
    private let defaults: UserDefaults
    private let now: () -> Date
    private let download: (URLRequest) async throws -> (Data, URLResponse)

    public var currentYear: Int { Calendar(identifier: .gregorian).component(.year, from: now()) }
    public var currentMonth: Int { Calendar(identifier: .gregorian).component(.month, from: now()) }
    public var currentSummary: WorkdaySummary? { summaries[currentYear]?[currentMonth] }
    public var currentError: String? { errors[currentYear] }
    public var isLoading: Bool { loading.contains(currentYear) }

    public func monthCalendar(settings: WorkSettings, year: Int, month: Int) -> WorkMonth? {
        settings.monthCalendar(year: year, month: month, holidays: years[year],
                               fallbackToWeekdays: true)
    }

    public init(
        defaults: UserDefaults = .standard,
        now: @escaping () -> Date = Date.init,
        download: @escaping (URLRequest) async throws -> (Data, URLResponse) = { try await URLSession.shared.data(for: $0) }
    ) {
        self.defaults = defaults
        self.now = now
        self.download = download
        restore(year: currentYear)
    }

    private func restore(year: Int) {
        attemptedAt[year] = defaults.object(forKey: "holiday-calendar-attempted-\(year)") as? Date
        guard years[year] == nil,
              let data = defaults.data(forKey: "holiday-calendar-\(year)"),
              let calendar = try? JSONDecoder().decode(HolidayYear.self, from: data),
              (try? calendar.validate(expectedYear: year)) != nil else { return }
        years[year] = calendar
        fetchedAt[year] = defaults.object(forKey: "holiday-calendar-date-\(year)") as? Date
        checkedAt[year] = defaults.object(forKey: "holiday-calendar-checked-\(year)") as? Date
        updateSummaries(calendar)
    }

    private func updateSummaries(_ calendar: HolidayYear) {
        let months = Dictionary(uniqueKeysWithValues: (1...12).compactMap { month in
            calendar.summary(month: month).map { (month, $0) }
        })
        summaries[calendar.year] = months
        // Keep a locally stored total for each month, derived only from validated data.
        defaults.set(Dictionary(uniqueKeysWithValues: months.map { (String($0.key), $0.value.total) }),
                     forKey: "holiday-workdays-\(calendar.year)")
    }

    public func loadCurrentYear(force: Bool = false) async {
        await loadYear(currentYear, force: force)
    }

    public func loadYear(_ year: Int, force: Bool = false) async {
        restore(year: year)
        guard !loading.contains(year) else { return }
        let timestamp = now()
        if !force {
            if years[year] != nil, let date = checkedAt[year],
               Calendar(identifier: .gregorian).isDate(date, equalTo: timestamp, toGranularity: .month) { return }
            // Retry failed requests after an hour instead of disabling refresh forever.
            if let attempt = attemptedAt[year],
               errors[year] != nil || attempt > (checkedAt[year] ?? .distantPast),
               timestamp.timeIntervalSince(attempt) >= 0,
               timestamp.timeIntervalSince(attempt) < 3600 { return }
        }
        attemptedAt[year] = timestamp
        defaults.set(timestamp, forKey: "holiday-calendar-attempted-\(year)")
        loading.insert(year)
        errors[year] = nil
        defer { loading.remove(year) }
        do {
            let (data, calendar) = try await fetchCalendar(year: year)
            let completedAt = now()
            fallbackYears.remove(year)
            if years[year] != calendar {
                years[year] = calendar
                updateSummaries(calendar)
                fetchedAt[year] = completedAt
                defaults.set(data, forKey: "holiday-calendar-\(year)")
                defaults.set(completedAt, forKey: "holiday-calendar-date-\(year)")
            }
            checkedAt[year] = completedAt
            defaults.set(completedAt, forKey: "holiday-calendar-checked-\(year)")
        } catch {
            if Task.isCancelled || (error as? URLError)?.code == .cancelled || error is CancellationError {
                attemptedAt[year] = nil
                defaults.removeObject(forKey: "holiday-calendar-attempted-\(year)")
                return
            }
            if years[year] == nil { fallbackYears.insert(year) }
            errors[year] = years[year] == nil
                ? "未能获取 \(year) 年节假日，暂按周一至周五计算。"
                : "日历更新失败，正在使用本机已缓存的数据。"
        }
    }

    private func fetchCalendar(year: Int) async throws -> (Data, HolidayYear) {
        let sources = [
            "https://raw.githubusercontent.com/NateScarlet/holiday-cn/master/\(year).json",
            "https://cdn.jsdelivr.net/gh/NateScarlet/holiday-cn@master/\(year).json",
            "https://fastly.jsdelivr.net/gh/NateScarlet/holiday-cn@master/\(year).json"
        ]
        var lastError: Error = HolidayError.invalidData
        for source in sources {
            try Task.checkCancellation()
            do {
                var request = URLRequest(url: URL(string: source)!)
                request.timeoutInterval = 20
                request.cachePolicy = .reloadIgnoringLocalCacheData
                let (data, response) = try await download(request)
                guard let response = response as? HTTPURLResponse, response.statusCode == 200,
                      data.count < 1_000_000 else { throw HolidayError.invalidData }
                let calendar = try JSONDecoder().decode(HolidayYear.self, from: data)
                try calendar.validate(expectedYear: year)
                return (data, calendar)
            } catch {
                if Task.isCancelled || (error as? URLError)?.code == .cancelled || error is CancellationError {
                    throw CancellationError()
                }
                lastError = error
            }
        }
        throw lastError
    }
}
