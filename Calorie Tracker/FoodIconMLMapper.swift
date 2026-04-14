// Calorie Tracker 2026
// FoodIconMLMapper.swift
// CoreML-based food icon classifier.  Replaces FoodSymbolMapper.
// Requires iOS 17+.  Model: FoodIconClassifier.mlmodel (add to target in Xcode).

import CoreML
import NaturalLanguage
import Foundation

enum FoodIconMLMapper {

    // MARK: - SF Symbol fallbacks per class (shown when asset is unavailable)

    private static let sfFallback: [String: String] = [
        "FoodIconApple":            "leaf.fill",
        "FoodIconBanana":           "leaf.fill",
        "FoodIconBean":             "leaf.fill",
        "FoodIconBeef":             "fork.knife",
        "FoodIconBeer":             "cup.and.saucer.fill",
        "FoodIconBottleWine":       "wineglass",
        "FoodIconBread":            "bag.fill",
        "FoodIconBurger":           "takeoutbag.and.cup.and.straw",
        "FoodIconBurrito":          "takeoutbag.and.cup.and.straw",
        "FoodIconBowlChopsticks":   "bowl.fill",
        "FoodIconCake":             "birthday.cake.fill",
        "FoodIconCakeSlice":        "birthday.cake.fill",
        "FoodIconCandy":            "birthday.cake.fill",
        "FoodIconCandyCane":        "birthday.cake.fill",
        "FoodIconCarrot":           "leaf.fill",
        "FoodIconChefHat":          "fork.knife",
        "FoodIconCherry":           "leaf.fill",
        "FoodIconChicken":          "flame.fill",
        "FoodIconCitrus":           "leaf.fill",
        "FoodIconCoffee":           "cup.and.saucer.fill",
        "FoodIconCookie":           "birthday.cake.fill",
        "FoodIconCookingPot":       "fork.knife",
        "FoodIconCroissant":        "bag.fill",
        "FoodIconCupSoda":          "cup.and.saucer.fill",
        "FoodIconDessert":          "birthday.cake.fill",
        "FoodIconDonut":            "birthday.cake.fill",
        "FoodIconDrumstick":        "flame.fill",
        "FoodIconEgg":              "frying.pan.fill",
        "FoodIconEggFried":         "frying.pan.fill",
        "FoodIconFish":             "fish.fill",
        "FoodIconFries":            "takeoutbag.and.cup.and.straw",
        "FoodIconGlassWater":       "drop.fill",
        "FoodIconGrape":            "leaf.fill",
        "FoodIconHam":              "fork.knife",
        "FoodIconHotDog":           "takeoutbag.and.cup.and.straw",
        "FoodIconIceCream":         "birthday.cake.fill",
        "FoodIconIceCreamBowl":     "bowl.fill",
        "FoodIconIceCreamSandwich": "snowflake",
        "FoodIconLollipop":         "birthday.cake.fill",
        "FoodIconMartini":          "wineglass",
        "FoodIconMicrowave":        "fork.knife",
        "FoodIconMilk":             "cup.and.saucer.fill",
        "FoodIconNut":              "leaf.fill",
        "FoodIconPasta":            "takeoutbag.and.cup.and.straw",
        "FoodIconPizza":            "takeoutbag.and.cup.and.straw",
        "FoodIconPopcorn":          "bag.fill",
        "FoodIconPopsicle":         "snowflake",
        "FoodIconPork":             "fork.knife",
        "FoodIconProtein":          "figure.strengthtraining.traditional",
        "FoodIconRamen":            "mug.fill",
        "FoodIconRefrigerator":     "fork.knife",
        "FoodIconRiceBowl":         "bowl.fill",
        "FoodIconSalad":            "leaf.fill",
        "FoodIconSandwich":         "takeoutbag.and.cup.and.straw",
        "FoodIconShoppingBasket":   "basket.fill",
        "FoodIconShrimp":           "fish.fill",
        "FoodIconSnail":            "fork.knife",
        "FoodIconSoup":             "bowl.fill",
        "FoodIconSushi":            "fish.fill",
        "FoodIconTaco":             "takeoutbag.and.cup.and.straw",
        "FoodIconUtensils":         "fork.knife",
        "FoodIconUtensilsCrossed":  "fork.knife",
        "FoodIconVegan":            "leaf.fill",
        "FoodIconWheat":            "bowl.fill",
        "FoodIconWine":             "wineglass",
        "FoodIconWrap":             "takeoutbag.and.cup.and.straw",
    ]

    // MARK: - Confidence threshold

    /// Predictions below this confidence fall back to the generic fork.knife icon.
    static let confidenceThreshold: Double = 0.45

    // MARK: - Cache

    private static let cacheLock = NSLock()
    private static var cachedTokensByKey: [String: FoodLogIconToken] = [:]
    private static var activeCacheSignature: String?

    // MARK: - Model (loaded once, lazily)

    private static let nlModel: NLModel? = {
        // Production path: Xcode-compiled .mlmodelc embedded in the bundle
        if let compiledURL = Bundle.main.url(forResource: "FoodIconClassifier", withExtension: "mlmodelc") {
            return try? NLModel(contentsOf: compiledURL)
        }
        // Development fallback: compile the raw .mlmodel on first launch
        if let sourceURL = Bundle.main.url(forResource: "FoodIconClassifier", withExtension: "mlmodel") {
            if let tempURL = try? MLModel.compileModel(at: sourceURL) {
                return try? NLModel(contentsOf: tempURL)
            }
        }
        return nil
    }()

    // MARK: - Public API (drop-in replacement for FoodSymbolMapper.icon(for:))

    static func icon(for raw: String) -> FoodLogIconToken {
        let text = normalize(raw)
        guard !text.isEmpty else { return .sf("fork.knife") }

        let signature = cacheSignature
        let cacheKey = "\(signature)|\(text)"

        cacheLock.lock()
        if activeCacheSignature != signature {
            cachedTokensByKey.removeAll(keepingCapacity: true)
            activeCacheSignature = signature
        }
        if let cached = cachedTokensByKey[cacheKey] {
            cacheLock.unlock()
            return cached
        }
        cacheLock.unlock()

        guard let model = nlModel else {
            return storeCached(.sf("fork.knife"), for: cacheKey)
        }

        let hypotheses = model.predictedLabelHypotheses(for: text, maximumCount: 1)
        guard
            let (label, confidence) = hypotheses.first,
            confidence >= confidenceThreshold
        else {
            return storeCached(.sf("fork.knife"), for: cacheKey)
        }

        let fallback = sfFallback[label] ?? "fork.knife"
        if label == "FoodIconVegan" {
            return storeCached(.sf("leaf.fill"), for: cacheKey)
        }

        return storeCached(.asset(name: label, fallback: fallback), for: cacheKey)
    }

    // MARK: - Normalisation (mirrors training-time preprocessing)

    private static let menuLinePrefixRegex: NSRegularExpression? =
        try? NSRegularExpression(pattern: #"^line\s+\d+\s+"#, options: .caseInsensitive)

    private static func normalize(_ raw: String) -> String {
        var s = raw
            .lowercased()
            .folding(options: .diacriticInsensitive, locale: .current)
            .replacingOccurrences(of: "'", with: "")
            .replacingOccurrences(of: "&", with: " and ")
            .replacingOccurrences(of: "/", with: " ")
            .replacingOccurrences(of: "-", with: " ")

        for dash in ["\u{2013}", "\u{2014}", "\u{2015}", "\u{2212}"] {
            s = s.replacingOccurrences(of: dash, with: " ")
        }

        if let re = menuLinePrefixRegex {
            let ns = s as NSString
            let range = NSRange(location: 0, length: ns.length)
            s = re.stringByReplacingMatches(in: s, range: range, withTemplate: "")
        }

        while s.contains("  ") {
            s = s.replacingOccurrences(of: "  ", with: " ")
        }

        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static var cacheSignature: String {
        "\(confidenceThreshold)|\(modelSignature)"
    }

    private static var modelSignature: String {
        if let compiledURL = Bundle.main.url(forResource: "FoodIconClassifier", withExtension: "mlmodelc"),
           let values = try? compiledURL.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey]) {
            let modifiedAt = values.contentModificationDate?.timeIntervalSince1970 ?? 0
            let size = values.fileSize ?? 0
            return "compiled:\(modifiedAt):\(size)"
        }
        if let sourceURL = Bundle.main.url(forResource: "FoodIconClassifier", withExtension: "mlmodel"),
           let values = try? sourceURL.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey]) {
            let modifiedAt = values.contentModificationDate?.timeIntervalSince1970 ?? 0
            let size = values.fileSize ?? 0
            return "source:\(modifiedAt):\(size)"
        }
        return "no-model"
    }

    @discardableResult
    private static func storeCached(_ token: FoodLogIconToken, for key: String) -> FoodLogIconToken {
        cacheLock.lock()
        cachedTokensByKey[key] = token
        cacheLock.unlock()
        return token
    }
}
