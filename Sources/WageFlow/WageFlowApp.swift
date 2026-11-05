import SwiftUI
import AppKit
import SalaryCore
import Combine

extension Notification.Name {
    /// Posted right before the settings window is shown again.
    static let settingsWindowWillOpen = Notification.Name("WageFlowSettingsWindowWillOpen")
}

@MainActor
final class SalaryStore: ObservableObject {
    let holidays: HolidayCalendarStore
    private var calendarSubscription: AnyCancellable?
    @Published var settings: WorkSettings {
        didSet {
            if settings.valid, let data = try? JSONEncoder().encode(settings) {
                UserDefaults.standard.set(data, forKey: "workSettings")
            }
        }
    }
    init() {
        Self.migratePreferences(to: UserDefaults.standard)
        holidays = HolidayCalendarStore()
        if let data = UserDefaults.standard.data(forKey: "workSettings"),
           let decoded = try? JSONDecoder().decode(WorkSettings.self, from: data), decoded.valid {
            settings = decoded
        } else { settings = WorkSettings() }
        // Rewrite saved settings without the retired opacity configuration.
        if let data = try? JSONEncoder().encode(settings) {
            UserDefaults.standard.set(data, forKey: "workSettings")
        }
        calendarSubscription = holidays.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
        }
    }

    private static func migratePreferences(to defaults: UserDefaults) {
        // Preserve salary settings and validated calendar caches after renaming.
        for domain in ["local.salary-panel.app", "SalaryPanel"] {
            for (key, value) in defaults.persistentDomain(forName: domain) ?? [:]
                where key == "workSettings" || key.hasPrefix("holiday-") {
                if defaults.object(forKey: key) == nil {
                    defaults.set(value, forKey: key)
                }
            }
        }
    }
    var calculationSettings: WorkSettings {
        var result = settings
        if let month = currentWorkMonth {
            result.workdays = Double(month.workdays)
        }
        return result
    }
    var currentWorkMonth: WorkMonth? {
        holidays.monthCalendar(settings: settings, year: holidays.currentYear, month: holidays.currentMonth)
    }
    var calendarReady: Bool { currentWorkMonth != nil }

    func isWorkday(at date: Date) -> Bool? {
        let parts = Calendar(identifier: .gregorian).dateComponents([.year, .month, .day], from: date)
        return holidays.monthCalendar(settings: settings, year: parts.year!, month: parts.month!)?
            .days.first(where: { $0.day == parts.day })?.isWorkday
    }

    func snapshot(at date: Date = Date()) -> WorkSnapshot {
        let calendar = Calendar(identifier: .gregorian)
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        let month = holidays.monthCalendar(settings: settings, year: c.year!, month: c.month!)
        var effective = settings
        effective.workdays = Double(month?.workdays ?? 0)
        return WorkSnapshot(settings: effective, now: date, calendar: calendar,
                            isWorkday: month?.days.first(where: { $0.day == c.day })?.isWorkday ?? false)
    }
    var tint: Color { WorkTheme.named(settings.theme).color }
}

@main
enum WageFlowApp {
    @MainActor
    static func main() {
        let application = NSApplication.shared
        let delegate = SalaryAppDelegate()
        application.delegate = delegate
        // `swift run` launches a bare executable without the bundle's LSUIElement.
        application.setActivationPolicy(.accessory)
        withExtendedLifetime(delegate) {
            application.run()
        }
    }
}

@MainActor
final class SalaryAppDelegate: NSObject, NSApplicationDelegate {
    private let store = SalaryStore()
    private var statusItem: NSStatusItem?
    private let popover = NSPopover()
    private var desktopWindow: NSWindow?
    private var settingsWindow: NSWindow?
    private var timer: Timer?
    private var calendarTimer: Timer?
    private var clickMonitor: Any?
    private var appearanceSubscription: AnyCancellable?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Keep the item alive and use a native image instead of a TimelineView label.
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.autosaveName = "WageFlowStatusItem"
        item.isVisible = true
        if let button = item.button {
            let image = NSImage(systemSymbolName: "yensign.circle.fill", accessibilityDescription: "WageFlow")
            image?.isTemplate = true
            button.image = image
            button.imagePosition = .imageOnly
            button.target = self
            button.action = #selector(togglePopover)
            button.setAccessibilityLabel("WageFlow，点击查看今日收入")
        }
        statusItem = item
        appearanceSubscription = store.$settings.sink { [weak self] settings in
            self?.desktopWindow?.alphaValue = settings.dashboardOpacity
            self?.popover.contentViewController?.view.window?.alphaValue = settings.dashboardOpacity
        }
        popover.behavior = .transient
        popover.contentViewController = NSHostingController(rootView:
            Dashboard(store: store,
                      onOpenDesktop: { [weak self] in self?.showDesktop() },
                      onOpenSettings: { [weak self] in self?.showSettings() })
        )
        refreshTooltip()
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshTooltip() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        refreshHolidayCalendar()
        let calendarTimer = Timer(timeInterval: 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshHolidayCalendar() }
        }
        RunLoop.main.add(calendarTimer, forMode: .common)
        self.calendarTimer = calendarTimer
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(refreshHolidayCalendar),
                                                         name: NSWorkspace.didWakeNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(refreshHolidayCalendar),
                                               name: .NSCalendarDayChanged, object: nil)
        FileHandle.standardError.write(Data("[WageFlow] 菜单栏入口已创建：点击右上角人民币图标。\n".utf8))
    }

    @objc private func togglePopover() {
        guard let button = statusItem?.button else { return }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            NSApp.activate(ignoringOtherApps: true)
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.alphaValue = store.settings.dashboardOpacity
            popover.contentViewController?.view.window?.makeKey()
        }
    }

    private func refreshTooltip() {
        let snapshot = store.snapshot()
        statusItem?.button?.toolTip = store.settings.hideIncome
            ? "WageFlow · 点击查看看板"
            : (store.calendarReady ? String(format: "WageFlow · 今日已赚 ¥%.2f", snapshot.earned) : "WageFlow · 计薪日历尚未就绪，请打开设置")
    }

    @objc private func refreshHolidayCalendar() {
        Task { await store.holidays.loadCurrentYear() }
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        refreshHolidayCalendar()
    }

    private func showDesktop() {
        popover.performClose(nil)
        if desktopWindow == nil {
            let controller = NSHostingController(rootView: Dashboard(store: store, desktop: true, onOpenSettings: { [weak self] in self?.showSettings() }))
            let window = NSWindow(contentViewController: controller)
            window.title = "桌面看板 · WageFlow"
            window.styleMask = [.titled, .closable, .miniaturizable]
            window.isReleasedWhenClosed = false
            window.center()
            desktopWindow = window
        }
        NSApp.activate(ignoringOtherApps: true)
        desktopWindow?.alphaValue = store.settings.dashboardOpacity
        desktopWindow?.makeKeyAndOrderFront(nil)
    }

    private func showSettings() {
        popover.performClose(nil)
        if settingsWindow == nil {
            let controller = NSHostingController(rootView: SettingsPanel(store: store))
            let window = NSWindow(contentViewController: controller)
            window.title = "WageFlow 设置"
            window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
            window.isReleasedWhenClosed = false
            window.setContentSize(NSSize(width: 560, height: 650))
            window.contentMinSize = NSSize(width: 540, height: 600)
            window.setFrameAutosaveName("WageFlowSettings")
            window.center()
            settingsWindow = window
        }
        NSApp.activate(ignoringOtherApps: true)
        NotificationCenter.default.post(name: .settingsWindowWillOpen, object: nil)
        settingsWindow?.makeKeyAndOrderFront(nil)
        // Opening the page should not grab the first text field.
        settingsWindow?.makeFirstResponder(nil)
        installClickToDismiss()
    }

    /// Clicking outside a text field always ends editing, as native panels do.
    private func installClickToDismiss() {
        guard clickMonitor == nil else { return }
        clickMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown]) { [weak self] event in
            self?.resignTextFocus(for: event)
            return event
        }
    }

    private func resignTextFocus(for event: NSEvent) {
        guard let window = settingsWindow, event.window === window,
              let content = window.contentView else { return }
        let point = content.convert(event.locationInWindow, from: nil)
        let hit = content.hitTest(point)
        if hit is NSTextField || hit is NSTextView { return }
        window.makeFirstResponder(nil)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func applicationWillTerminate(_ notification: Notification) {
        timer?.invalidate()
        calendarTimer?.invalidate()
        if let clickMonitor { NSEvent.removeMonitor(clickMonitor) }
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        NotificationCenter.default.removeObserver(self)
        if let statusItem { NSStatusBar.system.removeStatusItem(statusItem) }
    }
}

struct Dashboard: View {
    @ObservedObject var store: SalaryStore
    var desktop = false
    var onOpenDesktop: (() -> Void)? = nil
    var onOpenSettings: (() -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            today
            Divider()
            HStack {
                Text("每一秒的努力，都值得被看见。").font(.system(size: 10)).foregroundStyle(.secondary)
                Spacer()
                if !desktop {
                    Button { onOpenDesktop?() } label: {
                        Image(systemName: "macwindow")
                    }.help("打开独立桌面看板")
                }
                Button { NSApp.terminate(nil) } label: {
                    Image(systemName: "power")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                        .frame(width: 22, height: 22)
                        .contentShape(Rectangle())
                }
                .help("退出 WageFlow")
                .accessibilityLabel("退出 WageFlow")
            }.buttonStyle(.plain)
        }
        .padding(22)
        .frame(width: 400, height: 545)
        .background(Color(nsColor: .windowBackgroundColor))
        .tint(store.tint)
    }

    private func phaseLabel(restDay: Bool, snapshot: WorkSnapshot) -> String {
        if restDay { return "DAY OFF" }
        if snapshot.isLunchBreak { return "LUNCH" }
        if snapshot.isAfterWork { return "DONE" }
        return "LIVE"
    }

    private var today: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let s = store.snapshot(at: context.date)
            let previous = store.snapshot(at: context.date.addingTimeInterval(-1))
            let gain = max(0, s.earned - previous.earned)
            let isRestDay = store.isWorkday(at: context.date) == false
            let phase = phaseLabel(restDay: isRestDay, snapshot: s)
            VStack(alignment: .leading, spacing: 18) {
                HStack(spacing: 8) {
                    Text(context.date, format: .dateTime.month().day().weekday()).foregroundStyle(.secondary)
                    Spacer()
                    Circle().fill(store.tint).frame(width: 6, height: 6)
                    Text(phase).font(.system(size: 10, weight: .bold, design: .monospaced)).foregroundStyle(store.tint)
                    Button { onOpenSettings?() } label: {
                        Image(systemName: "gearshape").font(.system(size: 13))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .help("设置薪资与作息")
                    .accessibilityLabel("打开设置")
                    .keyboardShortcut(",", modifiers: .command)
                }.font(.caption)
                if isRestDay {
                    restDay
                } else if s.isLunchBreak {
                    lunchBreak(s)
                } else if s.isAfterWork {
                    finished(s)
                } else {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(spacing: 8) {
                            Text("今日已赚 / EARNED TODAY")
                                .font(.system(size: 10, weight: .semibold, design: .monospaced)).foregroundStyle(.secondary)
                            Spacer()
                            Button { store.settings.hideIncome.toggle() } label: {
                                Image(systemName: store.settings.hideIncome ? "eye.slash" : "eye")
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundStyle(store.tint)
                                    .frame(width: 22, height: 22)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .help(store.settings.hideIncome ? "显示收入金额" : "隐藏收入金额")
                            .accessibilityLabel(store.settings.hideIncome ? "显示收入金额" : "隐藏收入金额")
                        }
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Group {
                                if store.settings.hideIncome {
                                    Text("¥ ••••")
                                } else if store.calendarReady {
                                    AnimatedEarnings(value: s.earned)
                                } else {
                                    Text("¥ —")
                                }
                            }
                            .font(.system(size: 48, weight: .semibold, design: .rounded))
                            .monospacedDigit().minimumScaleFactor(0.5).lineLimit(1)
                            if !store.settings.hideIncome && store.calendarReady {
                                // Reserve space even while paused to keep the amount stable.
                                EarningsGain(value: gain, tint: store.tint, startedAt: context.date)
                                    .frame(width: 72, alignment: .leading)
                                    .opacity(gain > 0 ? 1 : 0)
                                    .layoutPriority(1)
                            }
                        }
                        Label(store.calendarReady ? s.status : "计薪日历未就绪，请在设置中重新获取", systemImage: "sparkles").font(.caption).foregroundStyle(store.tint)
                    }.padding(20).frame(maxWidth: .infinity, alignment: .leading)
                        .background(store.tint.opacity(0.09), in: RoundedRectangle(cornerRadius: 18))
                    HStack {
                        metric("今日目标", store.settings.hideIncome ? "••••" : (store.calendarReady ? money(store.calculationSettings.dailyPay) : "—"))
                        Spacer()
                        metric("每小时收入", store.settings.hideIncome ? "••••" : (store.calendarReady ? money(store.calculationSettings.hourlyPay) : "—"))
                    }
                    if store.currentWorkMonth?.isEstimated == true {
                        Label("日历暂按周一至周五计算", systemImage: "calendar.badge.exclamationmark")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text("上班进度").font(.caption).foregroundStyle(.secondary)
                            Spacer()
                            Text(String(format: "%.1f%%", s.progress * 100)).font(.caption.monospacedDigit())
                        }
                        ProgressView(value: s.progress)
                        HStack {
                            Text(clock(store.settings.start))
                            Spacer()
                            Text(clock(store.settings.end))
                        }.font(.caption2).foregroundStyle(.secondary)
                    }
                    HStack {
                        Image(systemName: "hourglass").foregroundStyle(store.tint)
                        Text("距离下班").font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        Text(duration(s.remaining)).font(.system(size: 22, weight: .medium, design: .monospaced))
                    }.padding(16).background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 12))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var restDay: some View {
        breakCard {
            RestDayIllustration(tint: store.tint)
            Text("今日休息")
                .font(.system(size: 30, weight: .semibold, design: .rounded))
            Text("把时间留给生活，也留给自己。")
                .font(.subheadline).foregroundStyle(.secondary)
        }
    }

    private func lunchBreak(_ s: WorkSnapshot) -> some View {
        breakCard {
            LunchBreakIllustration(tint: store.tint)
            Text("午休时间")
                .font(.system(size: 30, weight: .semibold, design: .rounded))
            Text("吃好这一餐，下午再出发。")
                .font(.subheadline).foregroundStyle(.secondary)
            HStack(spacing: 8) {
                Image(systemName: "hourglass")
                    .font(.system(size: 12)).foregroundStyle(store.tint)
                    .accessibilityHidden(true)
                Text("距离午休结束").font(.caption).foregroundStyle(.secondary)
                Text(duration(s.lunchRemaining))
                    .font(.system(size: 18, weight: .medium, design: .monospaced))
                    .monospacedDigit()
            }
            .padding(.horizontal, 14).padding(.vertical, 8)
            .background(store.tint.opacity(0.12), in: Capsule())
            .padding(.top, 2)
            .padding(.bottom, 14)
            .accessibilityElement(children: .combine)
        }
    }

    private func finished(_ s: WorkSnapshot) -> some View {
        breakCard {
            AfterWorkIllustration(tint: store.tint)
            Text("今日收工")
                .font(.system(size: 30, weight: .semibold, design: .rounded))
            Text("辛苦啦，今天也认真生活了。")
                .font(.subheadline).foregroundStyle(.secondary)
            VStack(spacing: 6) {
                Text("今日已赚 / EARNED")
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.secondary)
                Text(store.settings.hideIncome ? "¥ ••••" : (store.calendarReady ? money(s.earned) : "¥ —"))
                    .font(.system(size: 38, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(store.tint)
                Text("计薪 \(hours(store.settings.paidMinutes)) 小时 · 在岗 \(hours(Double(store.settings.end - store.settings.start))) 小时")
                    .font(.caption).foregroundStyle(.secondary)
                Text(workingHours)
                    .font(.caption2).foregroundStyle(.secondary)
            }
            .padding(.top, 2)
            .accessibilityElement(children: .combine)
        }
    }

    private var workingHours: String {
        let settings = store.settings
        var parts = ["\(clock(settings.start)) – \(clock(settings.end))"]
        if settings.lunchEnd > settings.lunchStart {
            parts.append("午休 \(clock(settings.lunchStart)) – \(clock(settings.lunchEnd))")
        }
        return parts.joined(separator: " · ")
    }

    private func hours(_ minutes: Double) -> String {
        String(format: "%.1f", minutes / 60)
    }

    /// Rest days and lunch breaks share the same quiet, illustration-led card.
    private func breakCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(spacing: 16) { content() }
            .frame(maxWidth: .infinity)
            .padding(20)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(store.tint.opacity(0.09), in: RoundedRectangle(cornerRadius: 18))
            .overlay(alignment: .bottom) {
                // Keep fallback calendars visible so an estimated day is clear.
                if store.currentWorkMonth?.isEstimated == true {
                    Text("日历暂按周一至周五计算")
                        .font(.caption2).foregroundStyle(.secondary).padding(.bottom, 8)
                }
            }
    }

}

private struct RestDayIllustration: View {
    let tint: Color
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        // Animate drawing properties only; opening the panel never animates layout.
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: reduceMotion)) { context in
            let time = reduceMotion ? 0 : context.date.timeIntervalSinceReferenceDate
            ZStack {
                Ellipse()
                    .fill(tint.opacity(0.08))
                    .frame(width: 100, height: 12)
                    .offset(y: 32)
                Image(systemName: "cup.and.saucer.fill")
                    .font(.system(size: 42, weight: .light))
                    .foregroundStyle(tint)
                    .offset(y: 10)
                SteamWisps(tint: tint, time: time)
                Image(systemName: "sun.max")
                    .font(.system(size: 24, weight: .light))
                    .foregroundStyle(tint.opacity(0.5))
                    .rotationEffect(.degrees(reduceMotion ? 0 : sin(time * .pi / 6) * 12))
                    .scaleEffect(1 + sin(time * .pi / 3) * 0.06)
                    .offset(x: 105, y: -20)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 90)
        }
        .transaction { $0.animation = nil }
        .accessibilityHidden(true)
        .allowsHitTesting(false)
    }
}

private struct SteamWisps: View {
    let tint: Color
    let time: Double

    var body: some View {
        ForEach(0..<3) { index in
            let phase = time * 1.4 + Double(index) * 1.2
            Path { path in
                path.move(to: CGPoint(x: 5, y: 22))
                path.addCurve(to: CGPoint(x: 5, y: 0),
                              control1: CGPoint(x: -3, y: 15),
                              control2: CGPoint(x: 13, y: 8))
            }
            .stroke(tint.opacity(0.25 + 0.12 * sin(phase)),
                    style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
            .frame(width: 10, height: 22)
            .offset(x: Double(index - 1) * 12 + sin(phase) * 2,
                    y: -25 - (sin(phase) + 1) * 3)
        }
    }
}

private struct LunchBreakIllustration: View {
    let tint: Color
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        // Same drawing-property animation as the rest-day coffee: never animate layout.
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: reduceMotion)) { context in
            let time = reduceMotion ? 0 : context.date.timeIntervalSinceReferenceDate
            ZStack {
                Ellipse()
                    .fill(tint.opacity(0.08))
                    .frame(width: 100, height: 12)
                    .offset(y: 32)
                BowlShape()
                    .fill(tint)
                    .frame(width: 66, height: 34)
                    .offset(y: 8)
                ForEach(0..<2) { index in
                    Capsule()
                        .fill(tint)
                        .frame(width: 3, height: 36)
                        .rotationEffect(.degrees(20), anchor: .bottom)
                        .offset(x: 18 + Double(index) * 7, y: -13 - Double(index) * 2)
                }
                SteamWisps(tint: tint, time: time)
                Image(systemName: "sun.max")
                    .font(.system(size: 24, weight: .light))
                    .foregroundStyle(tint.opacity(0.5))
                    .rotationEffect(.degrees(reduceMotion ? 0 : sin(time * .pi / 6) * 12))
                    .scaleEffect(1 + sin(time * .pi / 3) * 0.06)
                    .offset(x: 105, y: -20)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 90)
        }
        .transaction { $0.animation = nil }
        .accessibilityHidden(true)
        .allowsHitTesting(false)
    }
}

private struct AfterWorkIllustration: View {
    let tint: Color
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        // Same drawing-property animation as the other break pages.
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: reduceMotion)) { context in
            let time = reduceMotion ? 0 : context.date.timeIntervalSinceReferenceDate
            let phase = time * 1.3
            ZStack {
                Ellipse()
                    .fill(tint.opacity(0.08))
                    .frame(width: 100, height: 12)
                    .offset(y: 32)
                Image(systemName: "sun.horizon.fill")
                    .font(.system(size: 42, weight: .light))
                    .foregroundStyle(tint)
                    .offset(y: 6)
                Image(systemName: "sparkles")
                    .font(.system(size: 20, weight: .light))
                    .foregroundStyle(tint.opacity(reduceMotion ? 0.55 : 0.45 + 0.15 * sin(phase)))
                    .scaleEffect(reduceMotion ? 1 : 1 + sin(phase) * 0.05)
                    .offset(x: 105, y: -20)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 90)
        }
        .transaction { $0.animation = nil }
        .accessibilityHidden(true)
        .allowsHitTesting(false)
    }
}

private struct BowlShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let rimY = rect.minY + rect.height * 0.3
        let radius = rect.width * 0.42
        path.move(to: CGPoint(x: rect.midX - radius, y: rimY))
        path.addLine(to: CGPoint(x: rect.midX + radius, y: rimY))
        path.addArc(center: CGPoint(x: rect.midX, y: rimY), radius: radius,
                    startAngle: .degrees(0), endAngle: .degrees(180), clockwise: false)
        path.closeSubpath()
        return path
    }
}

private struct AnimatedEarnings: View {
    let value: Double
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        if #available(macOS 14.0, *) {
            Text(money(value))
                .contentTransition(.numericText(value: value))
                .animation(reduceMotion ? nil : .spring(response: 0.35, dampingFraction: 0.85), value: money(value))
        } else {
            Text(money(value))
                .contentTransition(.interpolate)
                .animation(reduceMotion ? nil : .easeOut(duration: 0.25), value: money(value))
        }
    }
}

private struct EarningsGain: View {
    let value: Double
    let tint: Color
    let startedAt: Date
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        // Derive the phase from time instead of animating state during the
        // hosting view's first layout. Each salary tick supplies a new origin.
        TimelineView(.animation(paused: reduceMotion)) { context in
            let elapsed = min(1, max(0, context.date.timeIntervalSince(startedAt) / 0.85))
            let progress = 1 - pow(1 - elapsed, 3)
            Text("+¥" + value.formatted(.number.grouping(.never).precision(.significantDigits(2...2))))
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .monospacedDigit().foregroundStyle(tint)
                .lineLimit(1).minimumScaleFactor(0.6)
                .offset(y: reduceMotion ? 0 : 5 - progress * 13)
                .opacity(reduceMotion ? 1 : 1 - progress)
                .accessibilityHidden(true)
        }
        .transaction { $0.animation = nil }
    }
}

private func money(_ value: Double) -> String { String(format: "¥%.2f", value.isFinite ? value : 0) }
private func clock(_ minute: Int) -> String { String(format: "%02d:%02d", minute / 60, minute % 60) }
private func duration(_ interval: TimeInterval) -> String {
    let seconds = max(0, Int(interval))
    return String(format: "%02d:%02d:%02d", seconds / 3600, seconds / 60 % 60, seconds % 60)
}
private func metric(_ title: String, _ value: String) -> some View {
    VStack(alignment: .leading, spacing: 6) {
        Text(title).font(.caption).foregroundStyle(.secondary)
        Text(value).font(.system(size: 19, weight: .semibold, design: .rounded)).monospacedDigit()
    }
}
