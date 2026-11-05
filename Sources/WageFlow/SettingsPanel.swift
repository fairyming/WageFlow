import SwiftUI
import SalaryCore

enum SettingsPage: String, CaseIterable, Identifiable {
    case pay = "薪资"
    case appearance = "外观"

    var id: String { rawValue }
}

@MainActor
final class SettingsEditor: ObservableObject {
    @Published var draft: WorkSettings
    @Published var income: String
    @Published var lunchEnabled: Bool
    @Published var page: SettingsPage = .pay
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
            HStack(spacing: 12) {
                Image(systemName: "slider.horizontal.3").font(.title2).foregroundStyle(store.tint)
                Text("按你的节奏，记录每一秒").font(.title3.bold()).lineLimit(1).minimumScaleFactor(0.85)
                Spacer(minLength: 12)
                HStack(spacing: 2) {
                    ForEach(SettingsPage.allCases) { page in
                        ChoiceChip(title: page.rawValue, selected: editor.page == page, tint: store.tint) {
                            editor.page = page
                        }
                    }
                }
                .padding(3)
                .background(Color.secondary.opacity(0.08), in: Capsule())
                .frame(width: 180)
            }.padding(24)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if editor.page == .pay {
                        incomeCard
                        shiftCard
                        calendarCard
                        previewCard
                    } else {
                        appearancePreview
                        themeCard
                        opacityCard
                    }
                }.padding(24)
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
            Divider()
            footer
        }
        .frame(minWidth: 540, minHeight: 600)
        .background(Color(nsColor: .windowBackgroundColor))
        .tint(store.tint)
        .onChange(of: store.settings) { updated in
            if !editor.hasChanges { editor.reset(to: updated) }
        }
        .task { await holidays.loadCurrentYear() }
    }

    private var footer: some View {
        VStack(spacing: 14) {
            if !editor.errors.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(editor.errors, id: \.self) { message in
                        Label(message, systemImage: "exclamationmark.circle").font(.caption)
                    }
                }.foregroundStyle(.red).frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12).background(Color.red.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
            }
            HStack {
                Label(editor.hasChanges ? "有未保存的修改" : "设置已保存在本机", systemImage: editor.hasChanges ? "pencil.circle" : "checkmark.circle")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("还原更改") { editor.reset(to: store.settings) }.disabled(!editor.hasChanges)
                Button("保存设置") { save() }
                    .buttonStyle(.borderedProminent).disabled(!canSave)
                    .keyboardShortcut("s", modifiers: .command)
            }
        }.padding(20)
    }

    private func save() {
        guard canSave else { return }
        // Preserve preferences that are edited outside this panel.
        var settings = editor.candidate
        settings.commute = store.settings.commute
        settings.dailyCost = store.settings.dailyCost
        settings.hideIncome = store.settings.hideIncome
        store.settings = settings
        editor.reset(to: settings)
    }

    private var incomeCard: some View {
        card("收入方式", icon: "yensign.circle") {
            HStack(spacing: 2) {
                ForEach(PayCycle.allCases, id: \.self) { cycle in
                    ChoiceChip(title: cycle.rawValue, selected: editor.draft.cycle == cycle, tint: store.tint) {
                        editor.draft.cycle = cycle
                    }
                }
            }
            .padding(3)
            .background(Color.secondary.opacity(0.08), in: Capsule())
            AmountField(title: editor.draft.cycle.rawValue + "金额", text: $editor.income, tint: store.tint)
        }
    }

    private var previewCard: some View {
        card("本月计算预览", icon: "equal.circle") {
            if let settings = previewSettings {
                HStack(spacing: 10) {
                    StatTile(title: "每日目标", value: money(settings.dailyPay), tint: store.tint)
                    StatTile(title: "每小时", value: money(settings.hourlyPay), tint: store.tint)
                    StatTile(title: "每日计薪", value: String(format: "%.1f 小时", settings.paidMinutes / 60),
                             tint: store.tint)
                }
            } else {
                Text("完善金额和作息后，即可预览计算结果。").font(.callout).foregroundStyle(.secondary)
            }
        }
    }

    private var shiftCard: some View {
        card("上下班与午休", icon: "clock") {
            HStack(spacing: 6) {
                ActionChip(title: "朝九晚六", tint: store.tint) { editor.setShift(start: 540, end: 1080) }
                ActionChip(title: "朝十晚七", tint: store.tint) { editor.setShift(start: 600, end: 1140) }
                ActionChip(title: "9:00–17:30", tint: store.tint) { editor.setShift(start: 540, end: 1050) }
                Spacer()
            }
            HStack(alignment: .top, spacing: 6) {
                TimeField(title: "上班", minute: $editor.draft.start, tint: store.tint)
                Image(systemName: "arrow.right")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(store.tint.opacity(0.7))
                    .padding(.top, 36)
                    .accessibilityHidden(true)
                TimeField(title: "下班", minute: $editor.draft.end, tint: store.tint)
            }
            Divider()
            HStack(spacing: 10) {
                Text("扣除午休时间").font(.callout)
                Spacer()
                Toggle("", isOn: Binding(get: { editor.lunchEnabled }, set: { editor.enableLunch($0) }))
                    .labelsHidden().toggleStyle(.switch).controlSize(.small)
                    .accessibilityLabel("扣除午休时间")
            }
            if editor.lunchEnabled {
                HStack(alignment: .top, spacing: 6) {
                    TimeField(title: "午休开始", minute: $editor.draft.lunchStart, tint: store.tint)
                    Image(systemName: "arrow.right")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(store.tint.opacity(0.7))
                        .padding(.top, 36)
                        .accessibilityHidden(true)
                    TimeField(title: "午休结束", minute: $editor.draft.lunchEnd, tint: store.tint)
                }
            }
            if let summary = shiftSummary {
                Label(summary, systemImage: "hourglass")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private var calendarCard: some View {
        card("计薪日历", icon: "calendar") {
            WorkCalendarPicker(settings: $editor.draft, holidays: holidays, tint: store.tint)
        }
    }

    private var shiftSummary: String? {
        let settings = editor.candidate
        guard settings.valid else { return nil }
        let paid = String(format: "%.1f", settings.paidMinutes / 60)
        let span = String(format: "%.1f", Double(settings.end - settings.start) / 60)
        return "每日计薪 \(paid) 小时 · 在岗 \(span) 小时"
    }

    private var appearancePreview: some View {
        card("看板预览", icon: "eye") {
            DashboardPreview(theme: WorkTheme.named(editor.draft.theme))
                .opacity(editor.draft.dashboardOpacity)
        }
    }

    private var themeCard: some View {
        card("主题", icon: "paintpalette") {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 4), spacing: 10) {
                ForEach(WorkTheme.all) { theme in
                    swatch(theme)
                }
            }
        }
    }

    private var opacityCard: some View {
        card("透明度", icon: "circle.lefthalf.filled") {
            HStack {
                Text("透明度")
                Spacer()
                Text(editor.draft.dashboardTransparency, format: .percent.precision(.fractionLength(0)))
                    .monospacedDigit().foregroundStyle(.secondary)
            }
            Slider(value: $editor.draft.dashboardTransparency, in: 0...0.4, step: 0.01) {
                Text("透明度")
            }
            .labelsHidden()
            Text("保存后应用于菜单栏看板和桌面看板，0% 为完全不透明。")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private func swatch(_ theme: WorkTheme) -> some View {
        // Unknown stored names fall back to the default accent, so highlight it too.
        let selected = WorkTheme.named(editor.draft.theme) == theme
        return Button { editor.draft.theme = theme.name } label: {
            VStack(spacing: 8) {
                RoundedRectangle(cornerRadius: 8).fill(theme.color.opacity(0.15))
                    .frame(height: 44)
                    .overlay(Image(systemName: "yensign.circle.fill").font(.title3).foregroundStyle(theme.color))
                HStack(spacing: 4) {
                    Text(theme.name).font(.callout).lineLimit(1)
                    Spacer(minLength: 2)
                    Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                        .font(.caption).foregroundStyle(selected ? theme.color : .secondary.opacity(0.6))
                }
            }.padding(8).frame(maxWidth: .infinity)
                .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12)
                    .stroke(selected ? theme.color : .secondary.opacity(0.15), lineWidth: selected ? 2 : 1))
        }.buttonStyle(.plain)
            .help("\(theme.name)配色")
            .accessibilityLabel("\(theme.name)配色")
            .accessibilityValue(selected ? "已选择" : "未选择")
    }

    private func card<Content: View>(_ title: String, icon: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(store.tint)
                    .frame(width: 22, height: 22)
                    .background(store.tint.opacity(0.10), in: RoundedRectangle(cornerRadius: 6))
                Text(title).font(.headline)
            }
            content()
        }.padding(18).frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 14))
    }
}

private func money(_ value: Double) -> String { String(format: "¥%.2f", value) }
