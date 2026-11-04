import SwiftUI
import SalaryCore

private final class CalendarNavigation: ObservableObject {
    @Published var month: Date = Calendar(identifier: .gregorian).date(from:
        Calendar(identifier: .gregorian).dateComponents([.year, .month], from: Date()))!
}

struct WorkCalendarPicker: View {
    @Binding var settings: WorkSettings
    @ObservedObject var holidays: HolidayCalendarStore
    var tint: Color
    @StateObject private var navigation = CalendarNavigation()
    private let calendar = Calendar(identifier: .gregorian)
    private var year: Int { calendar.component(.year, from: navigation.month) }
    private var month: Int { calendar.component(.month, from: navigation.month) }
    private var workMonth: WorkMonth? {
        holidays.monthCalendar(settings: settings, year: year, month: month)
    }
    private var monthKey: String { String(format: "%04d-%02d-", year, month) }
    private var hasCustomDays: Bool { settings.workdayOverrides.keys.contains { $0.hasPrefix(monthKey) } }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Button { changeMonth(-1) } label: { Image(systemName: "chevron.left") }
                    .help("上个月").accessibilityLabel("上个月")
                Menu {
                    ForEach((holidays.currentYear - 5)...(holidays.currentYear + 3), id: \.self) { value in
                        Button("\(String(value)) 年") {
                            if let date = calendar.date(from: DateComponents(year: value, month: month, day: 1)) {
                                navigation.month = date
                            }
                        }
                    }
                } label: { Text("\(String(year)) 年").font(.headline).monospacedDigit() }
                .menuStyle(.borderlessButton).fixedSize().accessibilityLabel("选择年份")
                Text("\(month) 月").font(.headline).monospacedDigit()
                Button { changeMonth(1) } label: { Image(systemName: "chevron.right") }
                    .help("下个月").accessibilityLabel("下个月")
                Spacer()
                Button("本月") { navigation.month = calendar.date(from: calendar.dateComponents([.year, .month], from: Date()))! }
                    .controlSize(.small)
            }.buttonStyle(.borderless)
            if let workMonth {
                calendarGrid(workMonth)
                if workMonth.isEstimated {
                    HStack(spacing: 8) {
                        if holidays.loading.contains(year) {
                            ProgressView().controlSize(.small)
                        }
                        Label(holidays.loading.contains(year)
                              ? "正在获取节假日，暂按周一至周五计算"
                              : "暂无可用节假日数据，暂按周一至周五计算",
                              systemImage: "calendar.badge.exclamationmark")
                            .font(.caption).foregroundStyle(.orange)
                    }
                }
                HStack(spacing: 12) {
                    legend("工作日", color: tint)
                    legend("休息日", color: .secondary)
                    Spacer()
                    Text("计薪 \(workMonth.workdays) 天").font(.callout.bold()).foregroundStyle(tint)
                }
                HStack {
                    Text("点击日期切换工作 / 休息").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button("重置本月") { settings.resetWorkdays(year: year, month: month) }
                        .controlSize(.small).disabled(!hasCustomDays)
                        .help("清除本月手动修改，恢复自动获取的日历；保存后生效")
                }
            } else {
                HStack(spacing: 10) {
                    if holidays.loading.contains(year) { ProgressView().controlSize(.small) }
                    Text(holidays.loading.contains(year) ? "正在获取工作日历…" : "暂无该年度的工作日历")
                        .font(.callout).foregroundStyle(.secondary)
                }.frame(maxWidth: .infinity, minHeight: 160)
            }
            if let error = holidays.errors[year], workMonth?.isEstimated != true {
                Label(error, systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(.orange)
            }
            HStack {
                if let date = holidays.checkedAt[year] {
                    Text("最近检查 \(date.formatted(date: .numeric, time: .omitted))")
                        .font(.caption2).foregroundStyle(.secondary)
                }
                Spacer()
                Button("更新日历") { Task { await holidays.loadYear(year, force: true) } }
                    .controlSize(.small).disabled(holidays.loading.contains(year))
            }
        }
        .task(id: year) { await holidays.loadYear(year) }
    }

    private func calendarGrid(_ month: WorkMonth) -> some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 7), spacing: 6) {
            ForEach(["一", "二", "三", "四", "五", "六", "日"], id: \.self) { day in
                Text(day).font(.caption).foregroundStyle(.secondary).frame(maxWidth: .infinity).padding(.bottom, 4)
            }
            ForEach(0..<month.leadingSpaces, id: \.self) { _ in Color.clear.frame(height: 46) }
            ForEach(month.days) { day in
                Button { toggle(day) } label: {
                    VStack(spacing: 3) {
                        Text("\(day.day)").font(.system(size: 14, weight: .medium, design: .rounded))
                        Text(day.isCustomized ? (day.isWorkday ? "班 ·" : "休 ·") : (day.isWorkday ? "班" : "休"))
                            .font(.system(size: 9))
                    }.frame(maxWidth: .infinity).frame(height: 46)
                        .foregroundStyle(day.isWorkday ? tint : .secondary)
                        .background(day.isWorkday ? tint.opacity(0.12) : Color.gray.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(isToday(day) ? tint : .clear, lineWidth: 1.5))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help([day.date, day.holidayName, day.isWorkday ? "工作日" : "休息日"].compactMap { $0 }.joined(separator: " · "))
                .accessibilityLabel("\(day.date)，\(day.isWorkday ? "工作日" : "休息日")")
                .accessibilityValue(day.isCustomized ? "已自定义" : "默认日历")
            }
        }
    }

    private func toggle(_ day: WorkCalendarDay) {
        settings.toggleWorkday(day)
    }

    private func changeMonth(_ value: Int) {
        if let date = calendar.date(byAdding: .month, value: value, to: navigation.month) { navigation.month = date }
    }

    private func isToday(_ day: WorkCalendarDay) -> Bool {
        let c = calendar.dateComponents([.year, .month, .day], from: Date())
        return c.year == year && c.month == month && c.day == day.day
    }

    private func legend(_ text: String, color: Color) -> some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 5, height: 5)
            Text(text).font(.caption2).foregroundStyle(.secondary)
        }
    }
}
