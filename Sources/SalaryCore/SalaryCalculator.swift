import Foundation

public enum PayCycle: String, Codable, CaseIterable {
    case monthly = "月薪", daily = "日薪", hourly = "时薪"
}

public struct WorkSettings: Codable, Equatable {
    public var income: Double = 15000
    public var cycle: PayCycle = .monthly
    public var workdays: Double = 21.75
    public var workdayOverrides: [String: Bool] = [:]
    public var start: Int = 9 * 60
    public var end: Int = 18 * 60
    public var lunchStart: Int = 12 * 60
    public var lunchEnd: Int = 13 * 60
    public var commute: Double = 60
    public var dailyCost: Double = 30
    public var theme: String = "薄荷"
    public var hideIncome: Bool = false
    public init() {}

    private enum CodingKeys: String, CodingKey {
        case income, cycle, workdays, start, end, lunchStart, lunchEnd
        case workdayOverrides, commute, dailyCost, theme, hideIncome
    }

    private enum LegacyCodingKeys: String, CodingKey { case workdayMode }

    public init(from decoder: Decoder) throws {
        self.init()
        let c = try decoder.container(keyedBy: CodingKeys.self)
        income = try c.decodeIfPresent(Double.self, forKey: .income) ?? income
        cycle = try c.decodeIfPresent(PayCycle.self, forKey: .cycle) ?? cycle
        workdays = try c.decodeIfPresent(Double.self, forKey: .workdays) ?? workdays
        let legacy = try decoder.container(keyedBy: LegacyCodingKeys.self)
        // Preserve active date edits, but don't re-enable an old inactive manual calendar.
        if try legacy.decodeIfPresent(String.self, forKey: .workdayMode) != "自动获取当月工作日" {
            workdayOverrides = try c.decodeIfPresent([String: Bool].self, forKey: .workdayOverrides) ?? [:]
        }
        start = try c.decodeIfPresent(Int.self, forKey: .start) ?? start
        end = try c.decodeIfPresent(Int.self, forKey: .end) ?? end
        lunchStart = try c.decodeIfPresent(Int.self, forKey: .lunchStart) ?? lunchStart
        lunchEnd = try c.decodeIfPresent(Int.self, forKey: .lunchEnd) ?? lunchEnd
        commute = try c.decodeIfPresent(Double.self, forKey: .commute) ?? commute
        dailyCost = try c.decodeIfPresent(Double.self, forKey: .dailyCost) ?? dailyCost
        theme = try c.decodeIfPresent(String.self, forKey: .theme) ?? theme
        hideIncome = try c.decodeIfPresent(Bool.self, forKey: .hideIncome) ?? hideIncome
    }

    public var valid: Bool {
        income.isFinite && income >= 0 && workdays.isFinite && workdays >= 0 &&
        start >= 0 && end <= 1440 && end > start && lunchStart >= start &&
        lunchEnd >= lunchStart && lunchEnd <= end && paidMinutes > 0 &&
        commute.isFinite && commute >= 0 && dailyCost.isFinite && dailyCost >= 0
    }
    public var paidMinutes: Double { Double(end - start - (lunchEnd - lunchStart)) }
    public var dailyPay: Double {
        switch cycle {
        case .monthly: return workdays > 0 ? income / workdays : 0
        case .daily: return income
        case .hourly: return income * paidMinutes / 60
        }
    }
    public var hourlyPay: Double { dailyPay / max(paidMinutes / 60, 0.001) }
    public var effectiveHourlyPay: Double {
        if cycle == .monthly && workdays == 0 { return 0 }
        return (dailyPay - dailyCost) / max((Double(end - start) + commute) / 60, 0.001)
    }

    public func monthCalendar(year: Int, month: Int, holidays: HolidayYear?, fallbackToWeekdays: Bool = false) -> WorkMonth? {
        if let holidays {
            guard holidays.year == year else { return nil }
            return holidays.monthCalendar(month: month, overrides: workdayOverrides)
        }
        guard fallbackToWeekdays else { return nil }
        var result = HolidayYear(year: year, days: []).monthCalendar(month: month, overrides: workdayOverrides)
        result?.isEstimated = true
        return result
    }

    public mutating func toggleWorkday(_ day: WorkCalendarDay) {
        let working = !day.isWorkday
        if working == day.defaultIsWorkday { workdayOverrides.removeValue(forKey: day.date) }
        else { workdayOverrides[day.date] = working }
    }

    public mutating func resetWorkdays(year: Int, month: Int) {
        let prefix = String(format: "%04d-%02d-", year, month)
        workdayOverrides = workdayOverrides.filter { !$0.key.hasPrefix(prefix) }
    }
}

public struct WorkSnapshot {
    public let earned: Double
    public let progress: Double
    public let remaining: TimeInterval
    /// True only on a workday while an enabled lunch break is running.
    public let isLunchBreak: Bool
    /// Seconds left until the lunch break ends; zero outside the break.
    public let lunchRemaining: TimeInterval
    /// True only on a workday once the shift has ended.
    public let isAfterWork: Bool
    public let status: String

    public init(settings s: WorkSettings, now: Date = Date(), calendar: Calendar = .current, isWorkday: Bool) {
        let c = calendar.dateComponents([.hour, .minute, .second], from: now)
        let minute = Double((c.hour ?? 0) * 60 + (c.minute ?? 0)) + Double(c.second ?? 0) / 60
        let working = isWorkday
        let elapsed = max(0, min(minute, Double(s.end)) - Double(s.start))
        let lunch = max(0, min(minute, Double(s.lunchEnd)) - Double(s.lunchStart))
        progress = working && s.valid ? min(1, max(0, (elapsed - lunch) / s.paidMinutes)) : 0
        earned = s.valid ? s.dailyPay * progress : 0
        remaining = working ? max(0, (Double(s.end) - minute) * 60) : 0
        // A zero-length lunch means the break is disabled, not an all-day break.
        let onLunchBreak = working && s.valid && s.lunchEnd > s.lunchStart &&
            minute >= Double(s.lunchStart) && minute < Double(s.lunchEnd)
        isLunchBreak = onLunchBreak
        lunchRemaining = onLunchBreak ? max(0, (Double(s.lunchEnd) - minute) * 60) : 0
        isAfterWork = working && s.valid && minute >= Double(s.end)
        if !working { status = "今天休息，好好生活" }
        else if minute < Double(s.start) { status = "还没上班，先喝杯咖啡" }
        else if minute >= Double(s.end) { status = "今日收工，辛苦啦！" }
        else if onLunchBreak { status = "午休中，给自己充个电" }
        else { status = "正在赚钱，每一秒都算数" }
    }
}
