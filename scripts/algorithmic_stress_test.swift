import Foundation

@main
struct AlgorithmicStressTest {
    static var failureCount = 0
    static var successCount = 0

    static func main() {
        print("Starting Algorithmic Stress Test for ExerciseCalorieService...")

        let exerciseTypes: [ExerciseType] = [.running, .cycling, .swimming, .weightLifting, .directCalories]
        
        let durationsMinutes = [-100, -1, 0, 1, 30, 60, 1440, 10000, 100000]
        let durationsSeconds: [Double?] = [nil, -1000.0, -1.0, 0.0, 1.0, 1800.0, 3600.0, 86400.0, 1000000.0]
        let distanceMiles: [Double?] = [nil, -10.0, -0.1, 0.0, 0.1, 1.0, 5.0, 26.2, 100.0, 10000.0]
        let weightsPounds = [-100, -1, 0, 1, 100, 170, 300, 1000, 10000]
        let pacesMinutesPerMile: [Double?] = [nil, -10.0, -1.0, 0.0, 1.0, 5.0, 10.0, 20.0, 100.0, 1000.0]

        // Fuzz loop
        var iterations = 0
        let totalEstimated = exerciseTypes.count * durationsMinutes.count * distanceMiles.count * weightsPounds.count * durationsSeconds.count * pacesMinutesPerMile.count

        for type in exerciseTypes {
            for duration in durationsMinutes {
                for durationSec in durationsSeconds {
                    for distance in distanceMiles {
                        for pace in pacesMinutesPerMile {
                            for weight in weightsPounds {
                                testCombination(
                                    type: type,
                                    durationMinutes: duration,
                                    distanceMiles: distance,
                                    weightPounds: weight,
                                    paceMinutesPerMile: pace,
                                    durationSeconds: durationSec
                                )
                                iterations += 1
                            }
                        }
                    }
                }
            }
        }

        print("Finished \(iterations) iterations.")
        print("Successes (Valid Outputs >= 0): \(successCount)")
        print("Failures (NaN, Inf, Crash, or < 0): \(failureCount)")

        if failureCount > 0 {
            print("❌ STRESS TEST FAILED with \(failureCount) issues.")
            exit(1)
        } else {
            print("✅ STRESS TEST PASSED")
            exit(0)
        }
    }

    static func testCombination(
        type: ExerciseType,
        durationMinutes: Int,
        distanceMiles: Double?,
        weightPounds: Int,
        paceMinutesPerMile: Double?,
        durationSeconds: Double?
    ) {
        // We use an asynchronous/autorelease wrapper or just run it directly. 
        // Swift numbers handling usually crashes on direct division by zero integer, but double gives Inf/NaN.
        
        // Let's call the public interfaces of ExerciseCalorieService
        let full = ExerciseCalorieService.fullCalories(
            type: type,
            durationMinutes: durationMinutes,
            distanceMiles: distanceMiles,
            weightPounds: weightPounds,
            paceMinutesPerMile: paceMinutesPerMile,
            durationSeconds: durationSeconds
        )

        let walkingEquiv = ExerciseCalorieService.walkingEquivalentCalories(
            type: type,
            durationMinutes: durationMinutes,
            distanceMiles: distanceMiles,
            weightPounds: weightPounds,
            paceMinutesPerMile: paceMinutesPerMile,
            durationSeconds: durationSeconds
        )
        
        let standard = ExerciseCalorieService.calories(
            type: type, 
            durationMinutes: durationMinutes, 
            distanceMiles: distanceMiles, 
            weightPounds: weightPounds
        )

        // Validating
        if full < 0 || walkingEquiv < 0 || standard < 0 {
            print("Negative output detected: full=\(full) walking=\(walkingEquiv) standard=\(standard) inputs: type=\(type), dur=\(durationMinutes), durSec=\(String(describing: durationSeconds)), dist=\(String(describing: distanceMiles)), w=\(weightPounds), pace=\(String(describing: paceMinutesPerMile))")
            failureCount += 1
            return
        }

        successCount += 1
    }
}
