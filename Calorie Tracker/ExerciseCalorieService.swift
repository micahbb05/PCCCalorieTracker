import Foundation

/// MET-based calorie estimation for exercise. Always uses light intensity.
/// Running uses extra-only calories (steps already cover walking-equivalent burn).
struct ExerciseCalorieService {
    private static let walkingBaselineMET = 3.0
    private static let runningMinutesPerMile: Double = 10
    private static let cyclingMinutesPerMile: Double = 5

    /// Light MET values.
    private static func metLight(for type: ExerciseType) -> Double {
        switch type {
        case .weightLifting: return 3.0
        case .running: return 6.0
        case .cycling: return 4.0
        case .swimming: return 5.0
        case .directCalories: return 0
        }
    }

    private static func durationHours(type: ExerciseType, durationMinutes: Int, distanceMiles: Double?) -> Double {
        if (type == .running || type == .cycling), let distanceMiles, distanceMiles > 0 {
            let minutesPerMile = type == .running ? runningMinutesPerMile : cyclingMinutesPerMile
            return (distanceMiles * minutesPerMile) / 60.0
        }
        return Double(max(durationMinutes, 0)) / 60.0
    }

    private static func calories(weightPounds: Int, hours: Double, metValue: Double) -> Int {
        guard hours > 0, weightPounds > 0 else { return 0 }
        let weightKg = Double(weightPounds) * 0.453592
        return max(Int((metValue * weightKg * hours).rounded()), 0)
    }

    static func fullCalories(type: ExerciseType, durationMinutes: Int, distanceMiles: Double?, weightPounds: Int) -> Int {
        let hours = durationHours(type: type, durationMinutes: durationMinutes, distanceMiles: distanceMiles)
        return calories(weightPounds: weightPounds, hours: hours, metValue: metLight(for: type))
    }

    static func walkingEquivalentCalories(type: ExerciseType, durationMinutes: Int, distanceMiles: Double?, weightPounds: Int) -> Int {
        guard type == .running else { return 0 }
        let hours = durationHours(type: type, durationMinutes: durationMinutes, distanceMiles: distanceMiles)
        return calories(weightPounds: weightPounds, hours: hours, metValue: walkingBaselineMET)
    }

    /// Calories from duration (weight lifting, walking). Uses light intensity.
    static func caloriesFromDuration(type: ExerciseType, durationMinutes: Int, weightPounds: Int) -> Int {
        if type == .running {
            let full = fullCalories(type: type, durationMinutes: durationMinutes, distanceMiles: nil, weightPounds: weightPounds)
            let walkingEquivalent = walkingEquivalentCalories(type: type, durationMinutes: durationMinutes, distanceMiles: nil, weightPounds: weightPounds)
            return max(full - walkingEquivalent, 0)
        }
        return fullCalories(type: type, durationMinutes: durationMinutes, distanceMiles: nil, weightPounds: weightPounds)
    }

    /// Calories from distance in miles (running, cycling). Uses light intensity.
    /// Running ~10 min/mi, cycling ~5 min/mi.
    static func caloriesFromDistance(type: ExerciseType, distanceMiles: Double, weightPounds: Int) -> Int {
        if type == .running {
            let full = fullCalories(type: type, durationMinutes: 0, distanceMiles: distanceMiles, weightPounds: weightPounds)
            let walkingEquivalent = walkingEquivalentCalories(type: type, durationMinutes: 0, distanceMiles: distanceMiles, weightPounds: weightPounds)
            return max(full - walkingEquivalent, 0)
        }
        return fullCalories(type: type, durationMinutes: 0, distanceMiles: distanceMiles, weightPounds: weightPounds)
    }

    /// Unified: use distance for running/cycling when provided, else duration.
    static func calories(type: ExerciseType, durationMinutes: Int, distanceMiles: Double?, weightPounds: Int) -> Int {
        if type == .running || type == .cycling, let miles = distanceMiles, miles > 0 {
            return caloriesFromDistance(type: type, distanceMiles: miles, weightPounds: weightPounds)
        }
        return caloriesFromDuration(type: type, durationMinutes: durationMinutes, weightPounds: weightPounds)
    }
}
