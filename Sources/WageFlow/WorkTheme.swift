import SwiftUI

/// A dashboard accent palette, stored by name so existing settings keep working.
struct WorkTheme: Identifiable, Equatable {
    let name: String
    let color: Color

    var id: String { name }

    static let mint = WorkTheme(name: "薄荷", color: Color(red: 0.13, green: 0.68, blue: 0.52))
    static let sunset = WorkTheme(name: "落日", color: .orange)
    static let iris = WorkTheme(name: "鸢尾", color: .purple)
    static let seaSalt = WorkTheme(name: "海盐", color: Color(red: 0.29, green: 0.53, blue: 0.85))
    static let coral = WorkTheme(name: "珊瑚", color: Color(red: 0.85, green: 0.40, blue: 0.36))
    static let amber = WorkTheme(name: "琥珀", color: Color(red: 0.80, green: 0.58, blue: 0.20))
    static let sakura = WorkTheme(name: "樱花", color: Color(red: 0.83, green: 0.44, blue: 0.62))
    static let graphite = WorkTheme(name: "石墨", color: Color(red: 0.39, green: 0.45, blue: 0.55))

    static let all: [WorkTheme] = [
        .mint, .sunset, .iris, .seaSalt, .coral, .amber, .sakura, .graphite
    ]

    /// Unknown or legacy names keep the default accent instead of failing to load.
    static func named(_ name: String) -> WorkTheme {
        all.first { $0.name == name } ?? .mint
    }
}
