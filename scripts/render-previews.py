#!/usr/bin/env python3
"""Render real SwiftUI views with isolated, synthetic data on macOS."""
from pathlib import Path
import os
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parent.parent
OUTPUT = ROOT / "resource"
OUTPUT.mkdir(exist_ok=True)

RENDERER = r'''
import AppKit
import SwiftUI

let previewCalendarDate = Calendar(identifier: .gregorian).date(from:
    DateComponents(year: 2026, month: 11, day: 4, hour: 14, minute: 30))!
@MainActor var previewDate = previewCalendarDate
let previewSuiteName = "local.wageflow.previews.\(UUID().uuidString)"
@MainActor let previewDefaults = UserDefaults(suiteName: previewSuiteName)!

@main
struct PreviewRenderer {
    @MainActor static func main() throws {
        defer { previewDefaults.removePersistentDomain(forName: previewSuiteName) }
        let application = NSApplication.shared
        application.setActivationPolicy(.accessory)
        application.appearance = NSAppearance(named: .aqua)
        // Fixture only: November has no holiday adjustments in this example.
        let calendar = Data(#"{"year":2026,"days":[{"name":"演示假期","date":"2026-01-01","isOffDay":true}]}"#.utf8)
        previewDefaults.set(calendar, forKey: "holiday-calendar-2026")
        previewDefaults.set(previewDate, forKey: "holiday-calendar-checked-2026")
        let store = SalaryStore()
        try render(Dashboard(store: store), name: "dashboard-workday", width: 400, height: 538)
        previewDate = Calendar(identifier: .gregorian).date(from:
            DateComponents(year: 2026, month: 11, day: 4, hour: 12, minute: 30))!
        try render(Dashboard(store: store), name: "dashboard-lunch", width: 400, height: 472)
        previewDate = Calendar(identifier: .gregorian).date(from:
            DateComponents(year: 2026, month: 11, day: 7, hour: 11, minute: 30))!
        try render(Dashboard(store: store), name: "dashboard-restday", width: 400, height: 430)
        for (page, name, height) in [(0, "settings-salary", 650.0),
                                     (1, "settings-schedule", 1030.0),
                                     (2, "settings-appearance", 650.0)] {
            try render(SettingsPanel(store: store, previewPage: page), name: name, width: 560, height: height)
        }
    }

    @MainActor static func render<V: View>(_ content: V, name: String, width: Double, height: Double) throws {
        let view = NSHostingView(rootView: content
            .environment(\.locale, Locale(identifier: "zh_CN"))
            .environment(\.colorScheme, .light))
        view.frame = NSRect(x: 0, y: 0, width: width, height: height)
        let window = NSWindow(contentRect: view.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = view
        view.layoutSubtreeIfNeeded()
        // Let native controls and lazy calendar cells complete their initial layout.
        RunLoop.main.run(until: Date().addingTimeInterval(0.15))
        view.layoutSubtreeIfNeeded()
        guard let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else {
            throw NSError(domain: "PreviewRenderer", code: 1)
        }
        view.cacheDisplay(in: view.bounds, to: bitmap)
        guard let png = bitmap.representation(using: .png, properties: [:]) else {
            throw NSError(domain: "PreviewRenderer", code: 2)
        }
        let path = URL(fileURLWithPath: CommandLine.arguments[1]).appendingPathComponent(name + ".png")
        try png.write(to: path)
        print("Rendered \(path.lastPathComponent) (\(bitmap.pixelsWide) × \(bitmap.pixelsHigh))")
        window.close()
    }
}
'''

with tempfile.TemporaryDirectory(prefix="wageflow-previews-") as temp:
    work = Path(temp)
    sources = []
    for source in sorted((ROOT / "Sources").rglob("*.swift")):
        text = source.read_text().replace("import SalaryCore\n", "")
        text = text.replace(r"@Environment(\.accessibilityReduceMotion) private var reduceMotion",
                            "private let reduceMotion = true")
        if source.name == "WageFlowApp.swift":
            text = text.replace("@main\nenum WageFlowApp", "enum WageFlowApp")
            text = text.replace("Self.migratePreferences(to: UserDefaults.standard)", "")
            text = text.replace("HolidayCalendarStore()", "HolidayCalendarStore(defaults: previewDefaults, now: { previewDate })")
            text = text.replace("UserDefaults.standard", "previewDefaults")
            text = text.replace("context.date", "previewDate")
        if source.name == "SettingsPanel.swift":
            text = text.replace("init(store: SalaryStore) {", "init(store: SalaryStore, previewPage: Int = 0) {")
            text = text.replace("_editor = StateObject(wrappedValue: SettingsEditor(settings: store.settings))",
                                "let editor = SettingsEditor(settings: store.settings)\n"
                                "        editor.page = previewPage\n"
                                "        _editor = StateObject(wrappedValue: editor)")
        if source.name == "WorkCalendarPicker.swift":
            text = text.replace("Date()", "previewCalendarDate")
        target = work / source.name
        target.write_text(text)
        sources.append(str(target))
    renderer = work / "PreviewRenderer.swift"
    renderer.write_text(RENDERER)
    executable = work / "render-previews"
    env = os.environ.copy()
    env.setdefault("CLANG_MODULE_CACHE_PATH", str(Path(tempfile.gettempdir()) / "wageflow-preview-module-cache"))
    subprocess.run(["swiftc", "-parse-as-library", *sources, str(renderer), "-o", str(executable)],
                   env=env, check=True)
    subprocess.run([str(executable), str(OUTPUT)], env=env, check=True)
