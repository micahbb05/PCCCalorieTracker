import Foundation
import HealthKit

struct HealthKitWorkoutMapper {
    struct Presentation {
        let name: String
        let symbolName: String
        let exerciseType: ExerciseType
    }

    static func makeExerciseEntry(from workout: HKWorkout, profile: BMRProfile?) -> ExerciseEntry {
        let activityType = workout.workoutActivityType
        let presentation = presentation(for: workout.workoutActivityType)
        let durationMinutes = max(Int(workout.duration / 60), 1)
        let weightPounds = profile?.weightPounds ?? 170
        let distanceMiles = workout.totalDistance?.doubleValue(for: .mile())
        let paceMinutesPerMile: Double? = {
            guard let miles = distanceMiles, miles > 0, workout.duration > 0 else { return nil }
            return (workout.duration / 60.0) / miles
        }()

        let estimatedCalories = ExerciseCalorieService.fullCalories(
            type: presentation.exerciseType,
            durationMinutes: durationMinutes,
            distanceMiles: distanceMiles,
            weightPounds: weightPounds,
            paceMinutesPerMile: paceMinutesPerMile,
            durationSeconds: workout.duration
        )
        let healthKitCalories: Int? = {
            guard let quantity = workout.totalEnergyBurned else { return nil }
            return max(Int(quantity.doubleValue(for: .kilocalorie()).rounded()), 0)
        }()
        let shouldPreferEstimatedCalories = activityType == .running || isStrengthActivity(activityType)

        let calories: Int = {
            if shouldPreferEstimatedCalories {
                return estimatedCalories
            }
            if let healthKitCalories, healthKitCalories > 0 {
                return healthKitCalories
            }
            return estimatedCalories
        }()

        let reclassifiedWalkingCalories: Int = {
            guard activityType == .running else { return 0 }
            return ExerciseCalorieService.walkingEquivalentCalories(
                type: presentation.exerciseType,
                durationMinutes: durationMinutes,
                distanceMiles: distanceMiles,
                weightPounds: weightPounds,
                paceMinutesPerMile: paceMinutesPerMile,
                durationSeconds: workout.duration
            )
        }()

        return ExerciseEntry(
            id: UUID(),
            exerciseType: presentation.exerciseType,
            customName: presentation.name,
            symbolName: presentation.symbolName,
            durationMinutes: durationMinutes,
            distanceMiles: distanceMiles,
            calories: calories,
            reclassifiedWalkingCalories: reclassifiedWalkingCalories,
            createdAt: workout.startDate
        )
    }

    static func presentation(for activity: HKWorkoutActivityType) -> Presentation {
        switch activity {
        case .americanFootball: return .init(name: "American Football", symbolName: "figure.american.football", exerciseType: .weightLifting)
        case .archery: return .init(name: "Archery", symbolName: "figure.archery", exerciseType: .weightLifting)
        case .australianFootball: return .init(name: "Australian Football", symbolName: "figure.american.football", exerciseType: .weightLifting)
        case .badminton: return .init(name: "Badminton", symbolName: "figure.badminton", exerciseType: .weightLifting)
        case .baseball: return .init(name: "Baseball", symbolName: "figure.baseball", exerciseType: .weightLifting)
        case .basketball: return .init(name: "Basketball", symbolName: "figure.basketball", exerciseType: .weightLifting)
        case .bowling: return .init(name: "Bowling", symbolName: "figure.bowling", exerciseType: .weightLifting)
        case .boxing: return .init(name: "Boxing", symbolName: "figure.boxing", exerciseType: .weightLifting)
        case .climbing: return .init(name: "Climbing", symbolName: "figure.climbing", exerciseType: .weightLifting)
        case .cricket: return .init(name: "Cricket", symbolName: "figure.cricket", exerciseType: .weightLifting)
        case .crossTraining: return .init(name: "Cross Training", symbolName: "figure.highintensity.intervaltraining", exerciseType: .weightLifting)
        case .curling: return .init(name: "Curling", symbolName: "figure.curling", exerciseType: .weightLifting)
        case .cycling: return .init(name: "Cycling", symbolName: "bicycle", exerciseType: .cycling)
        case .dance: return .init(name: "Dance", symbolName: "figure.dance", exerciseType: .weightLifting)
        case .danceInspiredTraining: return .init(name: "Dance Inspired Training", symbolName: "figure.dance", exerciseType: .weightLifting)
        case .elliptical: return .init(name: "Elliptical", symbolName: "figure.elliptical", exerciseType: .weightLifting)
        case .equestrianSports: return .init(name: "Equestrian Sports", symbolName: "figure.equestrian.sports", exerciseType: .weightLifting)
        case .fencing: return .init(name: "Fencing", symbolName: "figure.fencing", exerciseType: .weightLifting)
        case .fishing: return .init(name: "Fishing", symbolName: "fish", exerciseType: .weightLifting)
        case .functionalStrengthTraining: return .init(name: "Functional Strength Training", symbolName: "figure.strengthtraining.functional", exerciseType: .weightLifting)
        case .golf: return .init(name: "Golf", symbolName: "figure.golf", exerciseType: .weightLifting)
        case .gymnastics: return .init(name: "Gymnastics", symbolName: "figure.gymnastics", exerciseType: .weightLifting)
        case .handball: return .init(name: "Handball", symbolName: "figure.handball", exerciseType: .weightLifting)
        case .hiking: return .init(name: "Hiking", symbolName: "figure.hiking", exerciseType: .weightLifting)
        case .hockey: return .init(name: "Hockey", symbolName: "figure.hockey", exerciseType: .weightLifting)
        case .hunting: return .init(name: "Hunting", symbolName: "scope", exerciseType: .weightLifting)
        case .lacrosse: return .init(name: "Lacrosse", symbolName: "figure.lacrosse", exerciseType: .weightLifting)
        case .martialArts: return .init(name: "Martial Arts", symbolName: "figure.martial.arts", exerciseType: .weightLifting)
        case .mindAndBody: return .init(name: "Mind and Body", symbolName: "figure.mind.and.body", exerciseType: .weightLifting)
        case .mixedMetabolicCardioTraining: return .init(name: "Mixed Metabolic Cardio Training", symbolName: "figure.mixed.cardio", exerciseType: .weightLifting)
        case .paddleSports: return .init(name: "Paddle Sports", symbolName: "figure.open.water.swim", exerciseType: .weightLifting)
        case .play: return .init(name: "Play", symbolName: "figure.play", exerciseType: .weightLifting)
        case .preparationAndRecovery: return .init(name: "Preparation and Recovery", symbolName: "figure.cooldown", exerciseType: .weightLifting)
        case .racquetball: return .init(name: "Racquetball", symbolName: "figure.racquetball", exerciseType: .weightLifting)
        case .rowing: return .init(name: "Rowing", symbolName: "figure.rower", exerciseType: .weightLifting)
        case .rugby: return .init(name: "Rugby", symbolName: "figure.rugby", exerciseType: .weightLifting)
        case .running: return .init(name: "Running", symbolName: "figure.run", exerciseType: .running)
        case .sailing: return .init(name: "Sailing", symbolName: "figure.sailing", exerciseType: .weightLifting)
        case .skatingSports: return .init(name: "Skating Sports", symbolName: "figure.skating", exerciseType: .weightLifting)
        case .snowSports: return .init(name: "Snow Sports", symbolName: "figure.snowboarding", exerciseType: .weightLifting)
        case .soccer: return .init(name: "Soccer", symbolName: "figure.soccer", exerciseType: .weightLifting)
        case .softball: return .init(name: "Softball", symbolName: "figure.baseball", exerciseType: .weightLifting)
        case .squash: return .init(name: "Squash", symbolName: "figure.squash", exerciseType: .weightLifting)
        case .stairClimbing: return .init(name: "Stair Climbing", symbolName: "figure.stair.stepper", exerciseType: .weightLifting)
        case .surfingSports: return .init(name: "Surfing Sports", symbolName: "figure.surfing", exerciseType: .weightLifting)
        case .swimming: return .init(name: "Swimming", symbolName: "figure.pool.swim", exerciseType: .swimming)
        case .tableTennis: return .init(name: "Table Tennis", symbolName: "figure.table.tennis", exerciseType: .weightLifting)
        case .tennis: return .init(name: "Tennis", symbolName: "figure.tennis", exerciseType: .weightLifting)
        case .trackAndField: return .init(name: "Track and Field", symbolName: "figure.track.and.field", exerciseType: .weightLifting)
        case .traditionalStrengthTraining: return .init(name: "Traditional Strength Training", symbolName: "dumbbell.fill", exerciseType: .weightLifting)
        case .volleyball: return .init(name: "Volleyball", symbolName: "figure.volleyball", exerciseType: .weightLifting)
        case .walking: return .init(name: "Walking", symbolName: "figure.walk", exerciseType: .weightLifting)
        case .waterFitness: return .init(name: "Water Fitness", symbolName: "figure.water.fitness", exerciseType: .weightLifting)
        case .waterPolo: return .init(name: "Water Polo", symbolName: "figure.waterpolo", exerciseType: .weightLifting)
        case .waterSports: return .init(name: "Water Sports", symbolName: "figure.open.water.swim", exerciseType: .weightLifting)
        case .wrestling: return .init(name: "Wrestling", symbolName: "figure.wrestling", exerciseType: .weightLifting)
        case .yoga: return .init(name: "Yoga", symbolName: "figure.yoga", exerciseType: .weightLifting)
        case .barre: return .init(name: "Barre", symbolName: "figure.barre", exerciseType: .weightLifting)
        case .coreTraining: return .init(name: "Core Training", symbolName: "figure.core.training", exerciseType: .weightLifting)
        case .crossCountrySkiing: return .init(name: "Cross Country Skiing", symbolName: "figure.skiing.crosscountry", exerciseType: .weightLifting)
        case .downhillSkiing: return .init(name: "Downhill Skiing", symbolName: "figure.skiing.downhill", exerciseType: .weightLifting)
        case .flexibility: return .init(name: "Flexibility", symbolName: "figure.flexibility", exerciseType: .weightLifting)
        case .highIntensityIntervalTraining: return .init(name: "HIIT", symbolName: "figure.highintensity.intervaltraining", exerciseType: .weightLifting)
        case .jumpRope: return .init(name: "Jump Rope", symbolName: "figure.jumprope", exerciseType: .weightLifting)
        case .kickboxing: return .init(name: "Kickboxing", symbolName: "figure.kickboxing", exerciseType: .weightLifting)
        case .pilates: return .init(name: "Pilates", symbolName: "figure.pilates", exerciseType: .weightLifting)
        case .snowboarding: return .init(name: "Snowboarding", symbolName: "figure.snowboarding", exerciseType: .weightLifting)
        case .stairs: return .init(name: "Stairs", symbolName: "figure.stairs", exerciseType: .weightLifting)
        case .stepTraining: return .init(name: "Step Training", symbolName: "figure.step.training", exerciseType: .weightLifting)
        case .wheelchairWalkPace: return .init(name: "Wheelchair Walk Pace", symbolName: "figure.roll", exerciseType: .weightLifting)
        case .wheelchairRunPace: return .init(name: "Wheelchair Run Pace", symbolName: "figure.roll.runningpace", exerciseType: .weightLifting)
        case .taiChi: return .init(name: "Tai Chi", symbolName: "figure.taichi", exerciseType: .weightLifting)
        case .mixedCardio: return .init(name: "Mixed Cardio", symbolName: "figure.mixed.cardio", exerciseType: .weightLifting)
        case .handCycling: return .init(name: "Hand Cycling", symbolName: "figure.hand.cycling", exerciseType: .cycling)
        case .discSports: return .init(name: "Disc Sports", symbolName: "figure.disc.sports", exerciseType: .weightLifting)
        case .fitnessGaming: return .init(name: "Fitness Gaming", symbolName: "gamecontroller.fill", exerciseType: .weightLifting)
        case .cardioDance: return .init(name: "Cardio Dance", symbolName: "figure.dance", exerciseType: .weightLifting)
        case .socialDance: return .init(name: "Social Dance", symbolName: "figure.socialdance", exerciseType: .weightLifting)
        case .pickleball: return .init(name: "Pickleball", symbolName: "figure.pickleball", exerciseType: .weightLifting)
        case .cooldown: return .init(name: "Cooldown", symbolName: "figure.cooldown", exerciseType: .weightLifting)
        case .swimBikeRun: return .init(name: "Swim Bike Run", symbolName: "figure.triathlon", exerciseType: .weightLifting)
        case .transition: return .init(name: "Transition", symbolName: "figure.transition", exerciseType: .weightLifting)
        case .underwaterDiving: return .init(name: "Underwater Diving", symbolName: "figure.open.water.swim", exerciseType: .weightLifting)
        case .other: return .init(name: "Other Workout", symbolName: "figure.mixed.cardio", exerciseType: .weightLifting)
        @unknown default:
            return .init(name: "Workout", symbolName: "figure.mixed.cardio", exerciseType: .weightLifting)
        }
    }

    private static func isStrengthActivity(_ activity: HKWorkoutActivityType) -> Bool {
        switch activity {
        case .traditionalStrengthTraining, .functionalStrengthTraining, .crossTraining:
            return true
        default:
            return false
        }
    }
}
