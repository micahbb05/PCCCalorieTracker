import SwiftUI
import UIKit

enum AppThemeStyle: String, CaseIterable, Identifiable {
    case ember     = "ember"
    case blueprint = "blueprint"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .ember:     return "Ember"
        case .blueprint: return "Slate"
        }
    }

    // Cached to avoid hitting UserDefaults on every render call.
    // Invalidated whenever UserDefaults posts a change notification.
    private static var _cached: AppThemeStyle?
    private static let _observerToken: Any = {
        NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification,
            object: nil,
            queue: .main
        ) { _ in _cached = nil }
    }()

    static var active: AppThemeStyle {
        _ = _observerToken
        if let cached = _cached { return cached }
        let raw = UserDefaults.standard.string(forKey: "appThemeStyle") ?? "ember"
        let style = AppThemeStyle(rawValue: raw) ?? .ember
        _cached = style
        return style
    }
}

enum AppTheme {
    static func accent(for style: AppThemeStyle) -> Color {
        style == .ember
            ? Color(red: 0.722, green: 0.573, blue: 0.290)   // #B8924A — matches website amber
            : Color(red: 0.20, green: 0.50, blue: 0.98)
    }

    static var accent: Color {
        accent(for: AppThemeStyle.active)
    }

    static func neutral(for style: AppThemeStyle) -> Color {
        style == .ember
            ? Color(red: 0.58, green: 0.61, blue: 0.65)
            : Color(red: 0.62, green: 0.68, blue: 0.76)
    }

    // Cooler neutral used for non-critical UI so brand accent can stay reserved for actions.
    static var neutral: Color {
        neutral(for: AppThemeStyle.active)
    }

    // Higher-contrast secondary text for readability on dark cards/backgrounds.
    static var secondaryText: Color {
        AppThemeStyle.active == .ember
            ? Color(red: 0.66, green: 0.69, blue: 0.73)
            : Color(red: 0.78, green: 0.81, blue: 0.86)
    }

    static var info: Color {
        AppThemeStyle.active == .ember
            ? Color(red: 0.42, green: 0.58, blue: 0.72)
            : Color(red: 0.35, green: 0.66, blue: 0.98)
    }

    static var success: Color {
        AppThemeStyle.active == .ember
            ? Color(red: 0.47, green: 0.66, blue: 0.50)
            : Color(red: 0.36, green: 0.80, blue: 0.56)
    }

    static func surfaceBase(for style: AppThemeStyle) -> Color {
        style == .ember
            ? Color(red: 0.136, green: 0.116, blue: 0.098) // warm charcoal
            : Color(red: 0.13, green: 0.15, blue: 0.20)
    }

    static func surfaceElevated(for style: AppThemeStyle) -> Color {
        style == .ember
            ? Color(red: 0.176, green: 0.137, blue: 0.119) // slight red-brown lift
            : Color(red: 0.17, green: 0.19, blue: 0.25)
    }

    // Neutralized elevated card surface used by Profile/Settings cards.
    // Keeps ember warm identity but removes excess brown/orange cast.
    static func cardSurface(for style: AppThemeStyle) -> Color {
        surfaceBase(for: style)
    }

    static func inputSurface(for style: AppThemeStyle) -> Color {
        style == .ember
            ? Color(red: 0.157, green: 0.146, blue: 0.135) // cooler brown-gray
            : Color(red: 0.15, green: 0.18, blue: 0.24)
    }

    static func divider(for style: AppThemeStyle) -> Color {
        style == .ember
            ? Color(red: 0.42, green: 0.38, blue: 0.34)
            : Color(red: 0.42, green: 0.46, blue: 0.54)
    }

    static func inactiveFill(for style: AppThemeStyle) -> Color {
        style == .ember
            ? Color(red: 0.25, green: 0.22, blue: 0.20)
            : Color(red: 0.22, green: 0.25, blue: 0.32)
    }

    static var warning: Color {
        AppThemeStyle.active == .ember
            ? Color(red: 0.80, green: 0.63, blue: 0.39)
            : Color(red: 0.90, green: 0.72, blue: 0.42)
    }

    static var danger: Color {
        AppThemeStyle.active == .ember
            ? Color(red: 0.82, green: 0.46, blue: 0.42)
            : Color(red: 0.88, green: 0.45, blue: 0.48)
    }

    static var sheetBackgroundGradient: [Color] {
        AppThemeStyle.active == .ember
            ? [Color(red: 0.039, green: 0.031, blue: 0.020),
               Color(red: 0.051, green: 0.039, blue: 0.024),
               Color(red: 0.031, green: 0.024, blue: 0.016)]
            : [Color(red: 0.04, green: 0.06, blue: 0.15),
               Color(red: 0.07, green: 0.09, blue: 0.19),
               Color(red: 0.04, green: 0.05, blue: 0.12)]
    }

    static func applyControlAppearance(style: AppThemeStyle) {
        let segmented = UISegmentedControl.appearance()
        segmented.selectedSegmentTintColor = nil
        segmented.backgroundColor = nil
        segmented.setTitleTextAttributes(nil, for: .selected)
        segmented.setTitleTextAttributes(nil, for: .normal)

        let toggle = UISwitch.appearance()
        toggle.onTintColor = nil
        toggle.tintColor = nil
        toggle.backgroundColor = nil
        toggle.layer.cornerRadius = 0
    }
}
