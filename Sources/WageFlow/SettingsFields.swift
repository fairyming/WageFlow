import SwiftUI
import Foundation
import SalaryCore

/// A prominent currency editor with a tinted focus ring.
struct AmountField: View {
    let title: String
    @Binding var text: String
    let tint: Color
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("¥")
                    .font(.system(size: 20, weight: .medium, design: .rounded))
                    .foregroundStyle(tint)
                TextField("", text: $text)
                    .textFieldStyle(.plain)
                    .font(.system(size: 26, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .focused($focused)
                    .accessibilityLabel(title)
                Text("元").font(.callout).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 14)
            .frame(height: 56)
            .background(tint.opacity(focused ? 0.10 : 0.05), in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12)
                .stroke(focused ? tint : Color.secondary.opacity(0.15), lineWidth: focused ? 1.5 : 1))
            .contentShape(RoundedRectangle(cornerRadius: 12))
            .onTapGesture { focused = true }
        }
    }
}

/// A compact HH:mm editor that draws its own well but keeps native text editing.
struct TimeField: View {
    let title: String
    @Binding var minute: Int
    let tint: Color
    @StateObject private var model = TimeFieldModel()
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            HStack(spacing: 8) {
                Image(systemName: "clock")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(tint)
                    .accessibilityHidden(true)
                TextField("", text: $model.text)
                    .textFieldStyle(.plain)
                    .font(.system(size: 16, weight: .medium, design: .monospaced))
                    .focused($focused)
                    .onSubmit { finishEditing() }
                    .onChange(of: model.text) { updated in
                        let cleaned = TimeCode.sanitize(updated)
                        if cleaned != updated { model.text = cleaned }
                        guard focused, let value = TimeCode.parse(cleaned), value != minute else { return }
                        // Record before assigning so the observation below ignores our own edit.
                        model.lastCommitted = value
                        minute = value
                    }
                    .accessibilityLabel(title)
                    .accessibilityValue(TimeCode.format(minute))
            }
            .padding(.horizontal, 12)
            .frame(height: 40)
            .background(tint.opacity(focused ? 0.10 : 0.05), in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10)
                .stroke(focused ? tint : Color.secondary.opacity(0.15), lineWidth: focused ? 1.5 : 1))
            .contentShape(RoundedRectangle(cornerRadius: 10))
            .onTapGesture { focused = true }
        }
        .onAppear { syncText() }
        // Accept preset changes even while the field keeps keyboard focus.
        .onChange(of: minute) { updated in
            guard updated != model.lastCommitted else { return }
            model.lastCommitted = updated
            model.text = TimeCode.format(updated)
        }
        .onChange(of: focused) { isFocused in
            if isFocused {
                // Only rewrite when the text disagrees, so clicking into the field keeps the caret.
                guard TimeCode.parse(model.text) != minute else { return }
                model.lastCommitted = minute
                model.text = TimeCode.format(minute)
            } else {
                finishEditing()
            }
        }
    }

    private func syncText() {
        model.lastCommitted = minute
        model.text = TimeCode.format(minute)
    }

    private func finishEditing() {
        if let value = TimeCode.parse(model.text) {
            model.lastCommitted = value
            minute = value
        }
        model.text = TimeCode.format(minute)
    }
}

/// A small metric block used by the calculation preview.
struct StatTile: View {
    let title: String
    let value: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.caption2).foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 17, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(tint.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
    }
}

/// A pill that acts like a segment; the selected state carries the accent color.
struct ChoiceChip: View {
    let title: String
    let selected: Bool
    let tint: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.callout.weight(selected ? .semibold : .regular))
                .foregroundStyle(selected ? tint : Color.secondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
                .background(selected ? tint.opacity(0.16) : Color.clear, in: Capsule())
                .overlay(Capsule().stroke(selected ? tint.opacity(0.35) : .clear, lineWidth: 1))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }
}

/// A quiet capsule button for one-tap presets.
struct ActionChip: View {
    let title: String
    let tint: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.caption)
                .foregroundStyle(tint)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(tint.opacity(0.10), in: Capsule())
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .help(title)
    }
}

private final class TimeFieldModel: ObservableObject {
    @Published var text = ""
    var lastCommitted: Int?
}

/// A miniature dashboard used to preview the selected theme.
struct DashboardPreview: View {
    let theme: WorkTheme

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 5) {
                Text("11月4日 周三").font(.system(size: 10)).foregroundStyle(.secondary)
                Spacer()
                Circle().fill(theme.color).frame(width: 5, height: 5)
                Text("LIVE")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundStyle(theme.color)
            }
            VStack(alignment: .leading, spacing: 6) {
                Text("今日已赚 / EARNED")
                    .font(.system(size: 9, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.secondary)
                Text("¥714.29")
                    .font(.system(size: 30, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(theme.color)
                HStack(spacing: 4) {
                    Image(systemName: "sparkles").font(.system(size: 9))
                    Text("正在赚钱，每一秒都算数").font(.system(size: 10))
                }
                .foregroundStyle(theme.color)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(theme.color.opacity(0.09), in: RoundedRectangle(cornerRadius: 12))
        }
        .padding(16)
        .background(Color(nsColor: .windowBackgroundColor), in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.secondary.opacity(0.12), lineWidth: 1))
        .accessibilityHidden(true)
    }
}
