import SwiftUI
import SalaryCore

@MainActor
final class SettingsEditor: ObservableObject {
    @Published var draft: WorkSettings
    @Published var income: String
    @Published var lunchEnabled: Bool
    @Published var page = 0
    private var original: WorkSettings

    init(settings: WorkSettings) {
        draft = settings
        original = settings
        income = Self.number(settings.income)
        lunchEnabled = settings.lunchEnd > settings.lunchStart
    }

    var candidate: WorkSettings {
        var result = draft
        result.income = Self.parse(income) ?? .nan
        if !lunchEnabled {
            let anchor = min(max(draft.lunchStart, result.start), result.end)
            result.lunchStart = anchor
            result.lunchEnd = anchor
        }
        return result
    }

    var errors: [String] {
        var messages: [String] = []
        let s = candidate
        if !s.income.isFinite || s.income < 0 { messages.append("请输入大于或等于 0 的收入金额。") }
        if s.end <= s.start { messages.append("下班时间须晚于上班时间，暂不支持跨午夜班次。") }
        if lunchEnabled && (s.lunchStart < s.start || s.lunchEnd > s.end || s.lunchEnd <= s.lunchStart) {
            messages.append("午休须位于上下班之间，结束时间须晚于开始时间。")
        }
        if s.end > s.start && s.paidMinutes <= 0 { messages.append("扣除午休后，每天至少需要保留一段工作时间。") }
        return messages
    }

    var hasChanges: Bool { candidate != original }
    var canSave: Bool { hasChanges && errors.isEmpty && candidate.valid }

    func reset(to settings: WorkSettings) {
        original = settings
        draft = settings
        income = Self.number(settings.income)
        lunchEnabled = settings.lunchEnd > settings.lunchStart
    }

    func setShift(start: Int, end: Int) {
        draft.start = start
        draft.end = end
        draft.lunchStart = 12 * 60
        draft.lunchEnd = 13 * 60
    }

    func enableLunch(_ enabled: Bool) {
        lunchEnabled = enabled
        if enabled && draft.lunchEnd <= draft.lunchStart {
            draft.lunchStart = min(max(12 * 60, draft.start), max(draft.start, draft.end - 60))
            draft.lunchEnd = min(draft.lunchStart + 60, draft.end)
        }
    }

    private static func number(_ value: Double) -> String {
        value.formatted(.number.grouping(.never).precision(.significantDigits(1...17)))
    }

    private static func parse(_ text: String) -> Double? {
        // Validate the complete input instead of accepting a numeric prefix.
        let decimal = Locale.current.decimalSeparator ?? "."
        let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: decimal, with: ".")
        guard normalized.range(of: #"^[+-]?(?:[0-9]+(?:\.[0-9]*)?|\.[0-9]+)$"#, options: .regularExpression) != nil else { return nil }
        return Double(normalized)
    }
}

struct SettingsPanel: View {
    @ObservedObject var store: SalaryStore
    @ObservedObject private var holidays: HolidayCalendarStore
    @StateObject private var editor: SettingsEditor

    init(store: SalaryStore) {
        self.store = store
        self.holidays = store.holidays
        _editor = StateObject(wrappedValue: SettingsEditor(settings: store.settings))
    }

    private var previewSettings: WorkSettings? {
        var settings = editor.candidate
        guard let month = holidays.monthCalendar(settings: settings, year: holidays.currentYear,
                                                  month: holidays.currentMonth) else { return nil }
        settings.workdays = Double(month.workdays)
        return settings.valid ? settings : nil
    }

    private var canSave: Bool { editor.canSave && previewSettings != nil }

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 12) {
                    Image(systemName: "slider.horizontal.3").font(.title2).foregroundStyle(store.tint)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("按你的节奏，记录每一秒").font(.title3.bold())
                        Text("修改后保存，即可更新所有看板。").font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                Picker("设置分类", selection: $editor.page) {
                    Text("薪资计算").tag(0)
                    Text("工作作息").tag(1)
                    Text("外观与隐私").tag(2)
                }.pickerStyle(.segmented)
            }.padding(24)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if editor.page == 0 { salary }
                    else if editor.page == 1 { schedule }
                    else { appearance }
                    if !editor.errors.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            ForEach(editor.errors, id: \.self) { message in
                                Label(message, systemImage: "exclamationmark.circle").font(.caption)
                            }
                        }.foregroundStyle(.red).frame(maxWidth: .infinity, alignment: .leading)
                            .padding(14).background(Color.red.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
                    }
                }.padding(24)
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
            Divider()
            HStack {
                Label(editor.hasChanges ? "有未保存的修改" : "设置已保存在本机", systemImage: editor.hasChanges ? "pencil.circle" : "checkmark.circle")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("还原更改") { editor.reset(to: store.settings) }.disabled(!editor.hasChanges)
                Button("保存设置") {
                    guard canSave else { return }
                    // Preserve existing stored cost preferences.
                    var settings = editor.candidate
                    settings.commute = store.settings.commute
                    settings.dailyCost = store.settings.dailyCost
                    store.settings = settings
                    editor.reset(to: settings)
                }.buttonStyle(.borderedProminent).disabled(!canSave)
                    .keyboardShortcut("s", modifiers: .command)
            }.padding(20)
        }
        .frame(minWidth: 540, minHeight: 600)
        .background(Color(nsColor: .windowBackgroundColor))
        .tint(store.tint)
        .onChange(of: store.settings) { updated in
            if !editor.hasChanges { editor.reset(to: updated) }
        }
        .task { await holidays.loadCurrentYear() }
    }

    private var salary: some View {
        VStack(alignment: .leading, spacing: 18) {
            card("收入方式", icon: "yensign.circle") {
                Picker("薪资周期", selection: $editor.draft.cycle) {
                    ForEach(PayCycle.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }.pickerStyle(.segmented).labelsHidden()
                input(editor.draft.cycle.rawValue + "金额", text: $editor.income, unit: "元")
            }
            card("本月计算预览", icon: "equal.circle") {
                if let settings = previewSettings {
                    HStack {
                        preview("每日目标", money(settings.dailyPay))
                        Spacer()
                        preview("每小时", money(settings.hourlyPay))
                        Spacer()
                        preview("每日计薪", String(format: "%.1f 小时", settings.paidMinutes / 60))
                    }
                } else {
                    Text("完善金额和作息后，即可预览计算结果。").font(.callout).foregroundStyle(.secondary)
                }
            }
        }
    }

    private var schedule: some View {
        VStack(alignment: .leading, spacing: 18) {
            card("计薪日历", icon: "calendar") {
                WorkCalendarPicker(settings: $editor.draft, holidays: holidays, tint: store.tint)
            }
            card("上下班与午休", icon: "clock") {
                HStack(spacing: 8) {
                    Button("朝九晚六") { editor.setShift(start: 540, end: 1080) }
                    Button("朝十晚七") { editor.setShift(start: 600, end: 1140) }
                    Button("9:00–17:30") { editor.setShift(start: 540, end: 1050) }
                }.controlSize(.small)
                HStack(spacing: 24) {
                    timeInput("上班", minute: $editor.draft.start)
                    timeInput("下班", minute: $editor.draft.end)
                }
                Divider()
                Toggle("扣除午休时间", isOn: Binding(get: { editor.lunchEnabled }, set: { editor.enableLunch($0) }))
                    .toggleStyle(.switch).controlSize(.small)
                if editor.lunchEnabled {
                    HStack(spacing: 24) {
                        timeInput("午休开始", minute: $editor.draft.lunchStart)
                        timeInput("午休结束", minute: $editor.draft.lunchEnd)
                    }
                }
                Text("仅支持当天班次；关闭午休扣除后，整个班次均计薪。").font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private var appearance: some View {
        VStack(alignment: .leading, spacing: 18) {
            card("看板配色", icon: "paintpalette") {
                HStack(spacing: 12) {
                    theme("薄荷", color: Color(red: 0.13, green: 0.68, blue: 0.52))
                    theme("落日", color: .orange)
                    theme("鸢尾", color: .purple)
                }
                Text("配色将在保存后应用于看板。").font(.caption).foregroundStyle(.secondary)
            }
            card("隐私保护", icon: "eye.slash") {
                Toggle("隐藏收入金额", isOn: $editor.draft.hideIncome).toggleStyle(.switch)
                Text("隐藏今日看板和菜单栏悬停提示中的收入。薪资设置仍可查看和编辑。")
                    .font(.caption).foregroundStyle(.secondary)
                Divider()
                Label("所有设置仅保存在这台 Mac 上，不上传薪资数据。", systemImage: "lock.shield")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private func theme(_ title: String, color: Color) -> some View {
        Button { editor.draft.theme = title } label: {
            VStack(spacing: 10) {
                RoundedRectangle(cornerRadius: 8).fill(color.opacity(0.15))
                    .frame(height: 54).overlay(Image(systemName: "yensign.circle.fill").font(.title2).foregroundStyle(color))
                HStack {
                    Text(title)
                    Image(systemName: editor.draft.theme == title ? "checkmark.circle.fill" : "circle").foregroundStyle(color)
                }.font(.callout)
            }.padding(10).frame(maxWidth: .infinity)
                .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(editor.draft.theme == title ? color : .clear, lineWidth: 2))
        }.buttonStyle(.plain).accessibilityValue(editor.draft.theme == title ? "已选择" : "未选择")
    }

    private func input(_ title: String, text: Binding<String>, unit: String) -> some View {
        HStack {
            Text(title)
            Spacer()
            TextField(title, text: text).textFieldStyle(.roundedBorder)
                .multilineTextAlignment(.trailing).frame(width: 140)
            Text(unit).foregroundStyle(.secondary).frame(width: 20)
        }
    }

    private func timeInput(_ title: String, minute: Binding<Int>) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            DatePicker(title, selection: Binding(get: {
                Calendar.current.date(bySettingHour: minute.wrappedValue / 60, minute: minute.wrappedValue % 60,
                                      second: 0, of: Date()) ?? Date()
            }, set: {
                let c = Calendar.current.dateComponents([.hour, .minute], from: $0)
                minute.wrappedValue = (c.hour ?? 0) * 60 + (c.minute ?? 0)
            }), displayedComponents: .hourAndMinute)
                .datePickerStyle(.field).labelsHidden().controlSize(.large)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }

    private func card<Content: View>(_ title: String, icon: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Label(title, systemImage: icon).font(.headline)
            content()
        }.padding(18).frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 14))
    }

    private func preview(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.system(size: 17, weight: .semibold, design: .rounded)).monospacedDigit()
        }
    }
}

private func money(_ value: Double) -> String { String(format: "¥%.2f", value) }
