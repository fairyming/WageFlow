import Foundation

/// Parses and formats the HH:mm text used by the schedule fields.
public enum TimeCode {
    public static func format(_ minutes: Int) -> String {
        let clamped = min(max(minutes, 0), 24 * 60 - 1)
        return String(format: "%02d:%02d", clamped / 60, clamped % 60)
    }

    /// Accepts 9, 09, 930, 0930 and 9:30; a trailing colon means ":00".
    public static func parse(_ raw: String) -> Int? {
        let trimmed = raw.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        if trimmed.contains(":") {
            let parts = trimmed.split(separator: ":", omittingEmptySubsequences: false)
            guard parts.count == 2 else { return nil }
            let hour = parts[0].isEmpty ? nil : Int(parts[0])
            let minute = parts[1].isEmpty ? 0 : Int(parts[1])
            guard let hour, let minute, (0...23).contains(hour), (0...59).contains(minute) else { return nil }
            return hour * 60 + minute
        }
        let digits = trimmed.filter(\.isNumber)
        guard (1...4).contains(digits.count), let value = Int(digits) else { return nil }
        let hour = digits.count <= 2 ? value : value / 100
        let minute = digits.count <= 2 ? 0 : value % 100
        guard (0...23).contains(hour), (0...59).contains(minute) else { return nil }
        return hour * 60 + minute
    }

    /// Keeps digits and one colon, up to four digits, so typing stays predictable.
    public static func sanitize(_ raw: String) -> String {
        var result = ""
        var digits = 0
        var hasColon = false
        for character in raw {
            if character.isNumber {
                guard digits < 4 else { continue }
                result.append(character)
                digits += 1
            } else if character == ":" && !hasColon && !result.isEmpty {
                result.append(character)
                hasColon = true
            }
        }
        return result
    }
}
