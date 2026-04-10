import Foundation

/// MET-based calorie estimation for exercise.
/// Uses pace/speed-aware METs for running/cycling when available; otherwise falls back to light-intensity METs.
/// Running uses extra-only calories (steps already cover walking-equivalent burn).
struct ExerciseCalorieService {
    private static let runningMinutesPerMile: Double = 10
    private static let cyclingMinutesPerMile: Double = 5
    // Distance-based running economy baseline (net) used for best per-mile consistency.
    private static let runningCaloriesPerKgPerKmBase: Double = 1.0
    // Keep overlap removal aligned with step model (0.50 kcal/kg/km walking net).
    private static let walkingNetCaloriesPerKgPerKm = 0.50
    private static let walkingEquivalentFractionOfRunningFallback = 0.75

    /// Light MET values used when pace/speed context is unavailable.
    private static func metLight(for type: ExerciseType) -> Double {
        switch type {
        case .weightLifting: return 2.0 // ~20% active time with 2-3 min rests; effective blended MET
        case .running: return 6.0
        case .cycling: return 4.0
        case .swimming: return 5.0
        case .directCalories: return 0
        }
    }

    /// Prefer exact duration when available (e.g., HealthKit). Fall back to minutes, then distance-based estimates.
    private static func durationHours(
        type: ExerciseType,
        durationMinutes: Int,
        distanceMiles: Double?,
        durationSeconds: Double?
    ) -> Double {
        if let durationSeconds, durationSeconds > 0 {
            return durationSeconds / 3600.0
        }

        if durationMinutes > 0 {
            return Double(durationMinutes) / 60.0
        }

        if (type == .running || type == .cycling), let distanceMiles, distanceMiles > 0 {
            let minutesPerMile = type == .running ? runningMinutesPerMile : cyclingMinutesPerMile
            return (distanceMiles * minutesPerMile) / 60.0
        }

        return 0
    }

    private static func calories(weightPounds: Int, hours: Double, metValue: Double) -> Int {
        guard hours > 0, weightPounds > 0 else { return 0 }
        let weightKg = Double(weightPounds) * 0.453592
        return max(Int((metValue * weightKg * hours).rounded()), 0)
    }

    private static func runningDistanceCalories(weightPounds: Int, distanceMiles: Double) -> Int {
        guard weightPounds > 0, distanceMiles > 0 else { return 0 }
        let weightKg = Double(weightPounds) * 0.453592
        let distanceKm = distanceMiles * 1.609344
        let total = weightKg * distanceKm * runningCaloriesPerKgPerKmBase
        return max(Int(total.rounded()), 0)
    }

    private static func walkingDistanceCalories(weightPounds: Int, distanceMiles: Double) -> Int {
        guard weightPounds > 0, distanceMiles > 0 else { return 0 }
        let weightKg = Double(weightPounds) * 0.453592
        let distanceKm = distanceMiles * 1.609344
        let total = weightKg * distanceKm * walkingNetCaloriesPerKgPerKm
        return max(Int(total.rounded()), 0)
    }

    private static func speedMph(
        distanceMiles: Double?,
        durationMinutes: Int,
        paceMinutesPerMile: Double?,
        durationSeconds: Double?
    ) -> Double? {
        if let paceMinutesPerMile, paceMinutesPerMile > 0 {
            return 60.0 / paceMinutesPerMile
        }

        if let distanceMiles, distanceMiles > 0, let durationSeconds, durationSeconds > 0 {
            return distanceMiles / (durationSeconds / 3600.0)
        }

        guard
            let distanceMiles, distanceMiles > 0,
            durationMinutes > 0
        else {
            return nil
        }

        return distanceMiles / (Double(durationMinutes) / 60.0)
    }

    // MET mappings are based on Compendium-style pace/speed bins.
    private static func runningMET(speedMph: Double) -> Double {
        switch speedMph {
        case ..<5.0: return 6.0
        case ..<5.5: return 8.3
        case ..<6.5: return 9.8
        case ..<7.5: return 11.0
        case ..<8.5: return 11.8
        case ..<9.5: return 12.8
        default: return 14.5
        }
    }

    private static func cyclingMET(speedMph: Double) -> Double {
        switch speedMph {
        case ..<10.0: return 4.0
        case ..<12.0: return 6.8
        case ..<14.0: return 8.0
        case ..<16.0: return 10.0
        case ..<20.0: return 12.0
        default: return 15.8
        }
    }

    private static func metValue(
        for type: ExerciseType,
        durationMinutes: Int,
        distanceMiles: Double?,
        paceMinutesPerMile: Double?,
        durationSeconds: Double?
    ) -> Double {
        guard
            type == .running || type == .cycling,
            let mph = speedMph(
                distanceMiles: distanceMiles,
                durationMinutes: durationMinutes,
                paceMinutesPerMile: paceMinutesPerMile,
                durationSeconds: durationSeconds
            ),
            mph > 0
        else {
            return metLight(for: type)
        }

        if type == .running {
            return runningMET(speedMph: mph)
        }
        return cyclingMET(speedMph: mph)
    }

    static func fullCalories(
        type: ExerciseType,
        durationMinutes: Int,
        distanceMiles: Double?,
        weightPounds: Int,
        paceMinutesPerMile: Double? = nil,
        durationSeconds: Double? = nil
    ) -> Int {
        if type == .running, let distanceMiles, distanceMiles > 0 {
            return runningDistanceCalories(weightPounds: weightPounds, distanceMiles: distanceMiles)
        }

        let hours = durationHours(
            type: type,
            durationMinutes: durationMinutes,
            distanceMiles: distanceMiles,
            durationSeconds: durationSeconds
        )
        let met = metValue(
            for: type,
            durationMinutes: durationMinutes,
            distanceMiles: distanceMiles,
            paceMinutesPerMile: paceMinutesPerMile,
            durationSeconds: durationSeconds
        )
        return calories(weightPounds: weightPounds, hours: hours, metValue: met)
    }

    static func walkingEquivalentCalories(
        type: ExerciseType,
        durationMinutes: Int,
        distanceMiles: Double?,
        weightPounds: Int,
        paceMinutesPerMile: Double? = nil,
        durationSeconds: Double? = nil
    ) -> Int {
        guard type == .running else { return 0 }
        if let distanceMiles, distanceMiles > 0 {
            return walkingDistanceCalories(weightPounds: weightPounds, distanceMiles: distanceMiles)
        }

        if let inferredDistanceMiles = inferredRunningDistanceMiles(
            durationMinutes: durationMinutes,
            paceMinutesPerMile: paceMinutesPerMile,
            durationSeconds: durationSeconds
        ) {
            return walkingDistanceCalories(weightPounds: weightPounds, distanceMiles: inferredDistanceMiles)
        }

        let runningCalories = fullCalories(
            type: type,
            durationMinutes: durationMinutes,
            distanceMiles: distanceMiles,
            weightPounds: weightPounds,
            paceMinutesPerMile: paceMinutesPerMile,
            durationSeconds: durationSeconds
        )
        // Last-resort fallback if neither distance nor usable timing data are available.
        return max(Int((Double(runningCalories) * walkingEquivalentFractionOfRunningFallback).rounded()), 0)
    }

    private static func inferredRunningDistanceMiles(
        durationMinutes: Int,
        paceMinutesPerMile: Double?,
        durationSeconds: Double?
    ) -> Double? {
        if let paceMinutesPerMile, paceMinutesPerMile > 0 {
            if let durationSeconds, durationSeconds > 0 {
                let durationMinutes = durationSeconds / 60.0
                let miles = durationMinutes / paceMinutesPerMile
                return miles > 0 ? miles : nil
            }
            if durationMinutes > 0 {
                let miles = Double(durationMinutes) / paceMinutesPerMile
                return miles > 0 ? miles : nil
            }
        }

        let hours = durationHours(
            type: .running,
            durationMinutes: durationMinutes,
            distanceMiles: nil,
            durationSeconds: durationSeconds
        )
        guard hours > 0 else { return nil }
        let assumedSpeedMph = 60.0 / runningMinutesPerMile
        let miles = hours * assumedSpeedMph
        return miles > 0 ? miles : nil
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
