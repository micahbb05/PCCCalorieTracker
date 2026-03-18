import Foundation

enum NutrientCatalog {
    private static let known: [String: NutrientDefinition] = [
        "g_protein": NutrientDefinition(key: "g_protein", name: "Protein", unit: "g", defaultGoal: 150, minGoal: 10, maxGoal: 400, step: 5),
        "g_carbs": NutrientDefinition(key: "g_carbs", name: "Carbs", unit: "g", defaultGoal: 250, minGoal: 10, maxGoal: 700, step: 5),
        "g_fat": NutrientDefinition(key: "g_fat", name: "Fat", unit: "g", defaultGoal: 70, minGoal: 10, maxGoal: 250, step: 5),
        "g_saturated_fat": NutrientDefinition(key: "g_saturated_fat", name: "Saturated Fat", unit: "g", defaultGoal: 20, minGoal: 0, maxGoal: 120, step: 1),
        "g_trans_fat": NutrientDefinition(key: "g_trans_fat", name: "Trans Fat", unit: "g", defaultGoal: 2, minGoal: 0, maxGoal: 30, step: 1),
        "g_fiber": NutrientDefinition(key: "g_fiber", name: "Fiber", unit: "g", defaultGoal: 30, minGoal: 0, maxGoal: 120, step: 1),
        "g_sugar": NutrientDefinition(key: "g_sugar", name: "Sugar", unit: "g", defaultGoal: 50, minGoal: 0, maxGoal: 250, step: 1),
        "g_added_sugar": NutrientDefinition(key: "g_added_sugar", name: "Added Sugar", unit: "g", defaultGoal: 30, minGoal: 0, maxGoal: 150, step: 1),
        "mg_sodium": NutrientDefinition(key: "mg_sodium", name: "Sodium", unit: "mg", defaultGoal: 2300, minGoal: 100, maxGoal: 8000, step: 50),
        "mg_cholesterol": NutrientDefinition(key: "mg_cholesterol", name: "Cholesterol", unit: "mg", defaultGoal: 300, minGoal: 0, maxGoal: 2000, step: 10),
        "mg_potassium": NutrientDefinition(key: "mg_potassium", name: "Potassium", unit: "mg", defaultGoal: 3500, minGoal: 100, maxGoal: 10000, step: 50),
        "mg_calcium": NutrientDefinition(key: "mg_calcium", name: "Calcium", unit: "mg", defaultGoal: 1000, minGoal: 100, maxGoal: 5000, step: 25),
        "mg_iron": NutrientDefinition(key: "mg_iron", name: "Iron", unit: "mg", defaultGoal: 18, minGoal: 0, maxGoal: 200, step: 1),
        "mg_vitamin_c": NutrientDefinition(key: "mg_vitamin_c", name: "Vitamin C", unit: "mg", defaultGoal: 90, minGoal: 0, maxGoal: 2000, step: 5),
        "iu_vitamin_a": NutrientDefinition(key: "iu_vitamin_a", name: "Vitamin A", unit: "IU", defaultGoal: 3000, minGoal: 0, maxGoal: 12000, step: 100),
        "mcg_vitamin_a": NutrientDefinition(key: "mcg_vitamin_a", name: "Vitamin A", unit: "mcg", defaultGoal: 900, minGoal: 0, maxGoal: 5000, step: 25),
        "mcg_vitamin_d": NutrientDefinition(key: "mcg_vitamin_d", name: "Vitamin D", unit: "mcg", defaultGoal: 20, minGoal: 0, maxGoal: 200, step: 1)
    ]

    static let preferredOrder: [String] = [
        "g_protein", "g_carbs", "g_fat", "g_fiber", "g_sugar", "mg_sodium"
    ]
    static let nonTrackableKeys: Set<String> = ["calories", "re_vitamin_a"]
    static let defaultExcludedBecauseConsistentlyNull: Set<String> = [
        "mg_potassium",
        "g_added_sugar",
        "g_trans_fat",
        "mg_vitamin_c",
        "iu_vitamin_a",
        "mcg_vitamin_a",
        "mcg_vitamin_d",
        "mg_vitamin_d",
        "re_vitamin_a"
    ]

    static var knownKeys: [String] {
        Array(known.keys)
    }

    static var importableKeySet: Set<String> {
        Set(known.keys)
    }

    static func acceptedImportedNutrientValues(_ nutrientValues: [String: Int]) -> [String: Int] {
        nutrientValues.reduce(into: [:]) { result, pair in
            let normalized = pair.key.lowercased()
            guard importableKeySet.contains(normalized) else { return }
            result[normalized] = max(0, pair.value)
        }
    }

    static func definition(for key: String) -> NutrientDefinition {
        let normalizedKey = key.lowercased()
        if let knownDefinition = known[normalizedKey] {
            return knownDefinition
        }

        let parts = normalizedKey.split(separator: "_")
        let unitToken = parts.first.map(String.init) ?? "g"
        let remainder = parts.dropFirst().map(String.init).joined(separator: "_")
        let name = prettyName(from: remainder.isEmpty ? normalizedKey : remainder)
        let unit = prettyUnit(unitToken)
        let range = rangeFor(unitToken: unitToken)
        return NutrientDefinition(
            key: normalizedKey,
            name: name,
            unit: unit,
            defaultGoal: range.defaultGoal,
            minGoal: range.minGoal,
            maxGoal: range.maxGoal,
            step: range.step
        )
    }

    private static func prettyName(from raw: String) -> String {
        raw.split(separator: "_")
            .map { token in
                let word = String(token)
                if word.count <= 3 {
                    return word.uppercased()
                }
                return word.prefix(1).uppercased() + word.dropFirst()
            }
            .joined(separator: " ")
    }

    private static func prettyUnit(_ token: String) -> String {
        switch token {
        case "iu":
            return "IU"
        case "mcg":
            return "mcg"
        case "mg":
            return "mg"
        case "g":
            return "g"
        default:
            return token.uppercased()
        }
    }

    private static func rangeFor(unitToken: String) -> (defaultGoal: Int, minGoal: Int, maxGoal: Int, step: Int) {
        switch unitToken {
        case "mg":
            return (100, 0, 10000, 10)
        case "mcg":
            return (100, 0, 100000, 10)
        case "iu":
            return (1000, 0, 50000, 100)
        default:
            return (50, 0, 1000, 1)
        }
    }
}
