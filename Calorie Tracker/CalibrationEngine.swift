import Foundation

struct CalibrationAdjustmentParameters {
    let errorClamp: Double
    let alpha: Double
    let maxStep: Double
    let offsetLimit: Double
}

struct CalibrationEngine {
    static let calibrationErrorWeights: [Double] = [0.1, 0.2, 0.3, 0.4]

    static func weightedErrorMean(_ values: [Double]) -> Double {
        guard !values.isEmpty else { return 0 }
        let trimmed = Array(values.suffix(calibrationErrorWeights.count))
        let weights = Array(calibrationErrorWeights.suffix(trimmed.count))
        let weightedSum = zip(trimmed, weights).reduce(0.0) { partial, element in
            partial + (element.0 * element.1)
        }
        let totalWeight = weights.reduce(0, +)
        guard totalWeight > 0 else { return 0 }
        return weightedSum / totalWeight
    }

    static func spikeExcludedDayIDs(orderedDayIDs: [String], weightByDay: [String: Double]) -> Set<String> {
        guard orderedDayIDs.count > 1 else { return [] }
        var excluded: Set<String> = []
        for index in 1..<orderedDayIDs.count {
            let previous = orderedDayIDs[index - 1]
            let current = orderedDayIDs[index]
            guard let previousWeight = weightByDay[previous], let currentWeight = weightByDay[current] else {
                continue
            }
            if abs(currentWeight - previousWeight) > 4.0 {
                excluded.insert(current)
            }
        }
        return excluded
    }

    static func clamp(_ value: Double, lower: Double, upper: Double) -> Double {
        min(max(value, lower), upper)
    }

    static func calibrationAdjustmentParameters(recentErrors: [Double], isFastStart: Bool) -> CalibrationAdjustmentParameters {
        let defaultParams = CalibrationAdjustmentParameters(
            errorClamp: 100,
            alpha: isFastStart ? 0.5 : 0.2,
            maxStep: isFastStart ? 60 : 40,
            offsetLimit: 300
        )

        let trailing = Array(recentErrors.suffix(3))
        guard trailing.count == 3 else { return defaultParams }

        let signs = trailing.map { value -> Int in
            if value > 0 { return 1 }
            if value < 0 { return -1 }
            return 0
        }
        guard let firstSign = signs.first, firstSign != 0, signs.allSatisfy({ $0 == firstSign }) else {
            return defaultParams
        }

        let absErrors = trailing.map { abs($0) }
        guard absErrors.allSatisfy({ $0 >= 250 }) else { return defaultParams }

        let meanAbs = absErrors.reduce(0, +) / Double(absErrors.count)
        let intensity = clamp((meanAbs - 250) / 600 + 1, lower: 1, upper: 2)

        return CalibrationAdjustmentParameters(
            errorClamp: 100 * intensity,
            alpha: (isFastStart ? 0.5 : 0.2) + (isFastStart ? 0.1 : 0.15) * (intensity - 1),
            maxStep: (isFastStart ? 60 : 40) * intensity,
            offsetLimit: 300 + (300 * (intensity - 1))
        )
    }
}
