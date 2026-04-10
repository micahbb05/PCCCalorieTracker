// Calorie Tracker 2026

import Foundation
import SwiftUI

enum AppTab: String, CaseIterable, Identifiable {
    case today
    case history
    case add
    case profile
    case settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .today: return "Today"
        case .history: return "History"
        case .add: return "Add Food"
        case .profile: return "Profile"
        case .settings: return "Settings"
        }
    }

    var label: String {
        switch self {
        case .today: return "Today"
        case .history: return "History"
        case .add: return "Add"
        case .profile: return "Profile"
        case .settings: return "Settings"
        }
    }

    var iconName: String {
        switch self {
        case .today: return "fork.knife"
        case .history: return "clock.arrow.circlepath"
        case .add: return "plus"
        case .profile: return "person"
        case .settings: return "gearshape"
        }
    }
}
