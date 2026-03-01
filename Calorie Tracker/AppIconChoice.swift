import SwiftUI
import UIKit

enum AppIconChoice: String, CaseIterable, Identifiable {
    case standard
    case pink

    var id: String { rawValue }

    var title: String {
        switch self {
        case .standard:
            return "Standard"
        case .pink:
            return "Pink"
        }
    }

    var alternateIconName: String? {
        switch self {
        case .standard:
            return nil
        case .pink:
            return "AppIconPink"
        }
    }
}

enum AppIconManager {
    static func apply(_ choice: AppIconChoice) {
        guard UIApplication.shared.supportsAlternateIcons else { return }
        let desired = choice.alternateIconName
        guard UIApplication.shared.alternateIconName != desired else { return }
        UIApplication.shared.setAlternateIconName(desired)
    }
}
