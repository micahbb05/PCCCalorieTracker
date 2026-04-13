import Foundation
import CreateML
import CoreML

struct Sample {
    let text: String
    let label: String
}

struct RuleParseResult {
    let samples: [Sample]
    let duplicatesDropped: Int
}

enum RetrainFoodIconClassifier {
    static func run(repoRoot: URL) throws {
        let mapperPath = repoRoot.appendingPathComponent("Calorie Tracker/FoodSymbolMapper.swift")
        let modelPath = repoRoot.appendingPathComponent("Calorie Tracker/FoodIconClassifier.mlmodel")
        let backupPath = repoRoot.appendingPathComponent("Calorie Tracker/FoodIconClassifier.pre-retrain.backup.mlmodel")
        let reportPath = repoRoot.appendingPathComponent("output/food_icon_retrain_report.txt")

        let parsed = try parseSamples(from: mapperPath)
        let expanded = augment(samples: parsed.samples)
        let split = stratifiedSplit(samples: expanded, trainFraction: 0.8)

        let trainTable = try makeTable(from: split.train)
        let testTable = try makeTable(from: split.test)

        let parameters = MLTextClassifier.ModelParameters(
            validationData: testTable,
            algorithm: .maxEnt(revision: 1),
            language: .english
        )

        let classifier = try MLTextClassifier(
            trainingData: trainTable,
            textColumn: "text",
            labelColumn: "label",
            parameters: parameters
        )

        let eval = classifier.evaluation(on: testTable, textColumn: "text", labelColumn: "label")
        let holdoutAccuracy = (1.0 - eval.classificationError) * 100.0

        if !FileManager.default.fileExists(atPath: backupPath.path) {
            try? FileManager.default.copyItem(at: modelPath, to: backupPath)
        }

        try classifier.write(to: modelPath)

        let labels = Set(expanded.map(\.label))
        let report = [
            "Food Icon Retrain Report",
            "Generated: \(ISO8601DateFormatter().string(from: Date()))",
            "Model output: \(modelPath.path)",
            "Model backup: \(backupPath.path)",
            "",
            "Raw samples from assetBackedRules: \(parsed.samples.count)",
            "Duplicates dropped during parse: \(parsed.duplicatesDropped)",
            "Augmented samples total: \(expanded.count)",
            "Distinct labels: \(labels.count)",
            "Training samples: \(split.train.count)",
            "Holdout samples: \(split.test.count)",
            String(format: "Holdout top-1 accuracy: %.2f%%", holdoutAccuracy),
        ].joined(separator: "\n") + "\n"

        try FileManager.default.createDirectory(at: reportPath.deletingLastPathComponent(), withIntermediateDirectories: true)
        try report.write(to: reportPath, atomically: true, encoding: String.Encoding.utf8)

        print(String(format: "Holdout top-1 accuracy: %.2f%%", holdoutAccuracy))
        print("Labels: \(labels.count), train: \(split.train.count), holdout: \(split.test.count)")
        print("Wrote model: \(modelPath.path)")
        print("Report: \(reportPath.path)")
    }

    static func parseSamples(from mapperPath: URL) throws -> RuleParseResult {
        let src = try String(contentsOf: mapperPath, encoding: .utf8)
        guard let startRange = src.range(of: "private static let assetBackedRules: [Rule] = [") else {
            throw NSError(domain: "RetrainFoodIconClassifier", code: 1, userInfo: [NSLocalizedDescriptionKey: "assetBackedRules start not found"]) 
        }
        guard let endRange = src.range(of: "private static let sfSymbolRules:", options: [], range: startRange.upperBound..<src.endIndex) else {
            throw NSError(domain: "RetrainFoodIconClassifier", code: 2, userInfo: [NSLocalizedDescriptionKey: "assetBackedRules end not found"]) 
        }

        let block = String(src[startRange.upperBound..<endRange.lowerBound])
        let lines = block.components(separatedBy: .newlines)

        var samples: [Sample] = []
        var seen = Set<String>()
        var duplicatesDropped = 0

        var currentLabel: String?
        var inKeywords = false

        let quotedRegex = try NSRegularExpression(pattern: #"\"([^\"]+)\""#, options: [])

        for rawLine in lines {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("Rule(token:") {
                currentLabel = parseAssetLabel(line: line)
                inKeywords = line.contains("keywords:")
            } else if line.contains("keywords:") {
                inKeywords = true
            }

            guard inKeywords, let label = currentLabel else {
                if line.hasPrefix("]),") || line == "])" {
                    inKeywords = false
                    currentLabel = nil
                }
                continue
            }

            let ns = line as NSString
            let matches = quotedRegex.matches(in: line, options: [], range: NSRange(location: 0, length: ns.length))
            for match in matches {
                guard match.numberOfRanges > 1 else { continue }
                let phrase = ns.substring(with: match.range(at: 1)).trimmingCharacters(in: .whitespacesAndNewlines)
                guard !phrase.isEmpty else { continue }

                let key = "\(label)|\(phrase.lowercased())"
                if seen.insert(key).inserted {
                    samples.append(Sample(text: phrase, label: label))
                } else {
                    duplicatesDropped += 1
                }
            }

            if line.hasPrefix("]),") || line == "])" {
                inKeywords = false
                currentLabel = nil
            }
        }

        return RuleParseResult(samples: samples, duplicatesDropped: duplicatesDropped)
    }

    static func parseAssetLabel(line: String) -> String? {
        if line.contains("BundledFoodIconAsset.burrito") {
            return "FoodIconBurrito"
        }

        let pattern = #"\.asset\(name:\s*\"([^\"]+)\""#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let ns = line as NSString
        let matches = regex.matches(in: line, options: [], range: NSRange(location: 0, length: ns.length))
        guard let m = matches.first, m.numberOfRanges > 1 else { return nil }
        return ns.substring(with: m.range(at: 1))
    }

    static func augment(samples: [Sample]) -> [Sample] {
        var out: [Sample] = []
        var seen = Set<String>()

        func add(_ text: String, _ label: String) {
            let raw = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !raw.isEmpty else { return }
            let rawKey = "\(label)|raw|\(raw.lowercased())"
            if seen.insert(rawKey).inserted {
                out.append(Sample(text: raw, label: label))
            }

            let cleaned = normalize(text)
            guard !cleaned.isEmpty else { return }
            let key = "\(label)|norm|\(cleaned.lowercased())"
            if seen.insert(key).inserted {
                out.append(Sample(text: cleaned, label: label))
            }
        }

        for s in samples {
            add(s.text, s.label)
            add(s.text.capitalized, s.label)
            add("Line 5 \(s.text)", s.label)
            add("\(s.text) plate", s.label)
            add("\(s.text) bowl", s.label)
        }

        // Targeted weighting via additional normalized examples for known menu phrasing.
        for text in ["all american grill", "all-american grill", "line 3 all american grill"] {
            add(text, "FoodIconBurger")
            add(text + " station", "FoodIconBurger")
        }
        for text in [
            "fresh fruit",
            "line 3 fresh fruit",
            "fresh fruit option",
            "fresh fruit selection",
            "fresh fruit serving",
            "fresh fruit side",
            "fresh fruit plate",
            "fresh fruit bowl",
            "fresh fruit cup",
            "fresh fruit station",
            "fresh fruit bar",
            "daily fresh fruit",
            "fresh seasonal fruit",
            "assorted fresh fruit",
            "fresh cut fruit",
            "fresh sliced fruit",
            "fresh fruit medley",
            "fresh fruit mix",
            "fresh fruit item",
            "fresh fruit line",
        ] {
            add(text, "FoodIconApple")
        }

        // Nutrislice line-name fixes from live two-week audit.
        // Keep these broad enough to generalize, while anchoring exact recurring headers.
        for text in [
            "condiment options",
            "condiment option",
            "condiments",
            "sauce bar",
            "sauce station",
            "line 1 condiment options",
            "line 2 condiment options",
            "line 3 condiment options",
        ] {
            add(text, "FoodIconChefHat")
        }

        for text in [
            "dessert bar",
            "line 3 dessert bar",
            "line 2 dessert bar",
            "cookie bar",
            "dessert station",
            "desserts",
            "sweet treats",
            "baked desserts",
        ] {
            add(text, "FoodIconCookie")
        }

        for text in [
            "bbq chicken",
            "line 2 bbq chicken",
            "line 2 - bbq chicken",
            "barbecue chicken",
            "grilled bbq chicken",
            "smoky bbq chicken",
        ] {
            add(text, "FoodIconChicken")
        }

        for text in [
            "fried chicken",
            "line 2 fried chicken",
            "line 7 fried chicken",
            "crispy fried chicken",
            "southern fried chicken",
        ] {
            add(text, "FoodIconChicken")
        }

        for text in [
            "baked ziti",
            "line 2 baked ziti",
            "line 4 baked ziti",
            "line 6 baked ziti",
            "ziti bake",
            "ziti pasta",
            "spaghetti with meat sauce",
            "line 5 spaghetti with meat sauce",
            "italian sausage rigatoni",
            "line 5 italian sausage rigatoni",
            "indian red curry",
            "line 4 indian red curry",
        ] {
            add(text, "FoodIconPasta")
        }

        for text in [
            "stroganoff",
            "line 3 stroganoff",
            "beef stroganoff",
            "creamy beef stroganoff",
            "beef and noodles stroganoff",
            "mushroom stroganoff",
            "classic stroganoff",
        ] {
            add(text, "FoodIconBeef")
        }

        for text in [
            "continental breakfast",
            "breakfast line",
            "morning breakfast",
            "breakfast station",
            "line 1 continental breakfast",
            "brunch",
            "line 3 brunch",
        ] {
            add(text, "FoodIconPancakes")
        }

        for text in [
            "get well kit",
            "wellness kit",
            "recovery kit",
            "hydration kit",
        ] {
            add(text, "FoodIconGlassWater")
        }

        for text in [
            "italian sub",
            "line 1 italian sub",
        ] {
            add(text, "FoodIconSandwich")
        }

        for text in [
            "pepperoni hot pocket sticks",
            "hot pocket sticks",
            "pepperoni hot pockets sticks",
        ] {
            add(text, "FoodIconHotDog")
        }

        for text in [
            "chipotle chicken quesadilla",
            "quesadilla line",
            "chicken quesadilla",
        ] {
            add(text, "FoodIconBurrito")
        }

        for text in [
            "closed",
            "line 1 closed",
            "station closed",
        ] {
            add(text, "FoodIconUtensilsCrossed")
        }

        for text in [
            "yogurt",
            "yoghurt",
            "greek yogurt",
            "greek yoghurt",
            "skyr",
            "plain yogurt",
            "vanilla yogurt",
            "strawberry yogurt",
            "blueberry yogurt",
            "salted caramel yogurt",
            "salted caramel remix yogurt",
            "remix yogurt",
            "yogurt parfait",
            "probiotic yogurt",
            "drinkable yogurt",
            "chobani yogurt",
            "oikos yogurt",
            "ratio protein yogurt",
        ] {
            add(text, "FoodIconMilk")
        }

        for text in [
            "popcorn",
            "movie popcorn",
            "buttered popcorn",
            "kettle corn",
            "caramel corn",
            "smartfood popcorn",
            "popcorners",
            "pop corners",
        ] {
            add(text, "FoodIconPopcorn")
        }

        return out
    }

    static func normalize(_ raw: String) -> String {
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

        if let re = try? NSRegularExpression(pattern: #"^line\s+\d+\s+"#, options: .caseInsensitive) {
            let ns = s as NSString
            let range = NSRange(location: 0, length: ns.length)
            s = re.stringByReplacingMatches(in: s, range: range, withTemplate: "")
        }

        while s.contains("  ") {
            s = s.replacingOccurrences(of: "  ", with: " ")
        }
        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func stratifiedSplit(samples: [Sample], trainFraction: Double) -> (train: [Sample], test: [Sample]) {
        var byLabel: [String: [Sample]] = [:]
        for s in samples {
            byLabel[s.label, default: []].append(s)
        }

        var train: [Sample] = []
        var test: [Sample] = []

        for (label, group) in byLabel {
            let sorted = group.sorted { $0.text < $1.text }
            let count = sorted.count
            if count <= 1 {
                train.append(contentsOf: sorted)
                continue
            }

            var trainCount = Int(Double(count) * trainFraction)
            trainCount = max(1, min(count - 1, trainCount))

            train.append(contentsOf: sorted.prefix(trainCount))
            test.append(contentsOf: sorted.suffix(count - trainCount))

            if trainCount == 0 || trainCount == count {
                fputs("Warning: label \(label) had degenerate split\n", stderr)
            }
        }

        train.sort { (lhs, rhs) in
            if lhs.label != rhs.label { return lhs.label < rhs.label }
            return lhs.text < rhs.text
        }
        test.sort { (lhs, rhs) in
            if lhs.label != rhs.label { return lhs.label < rhs.label }
            return lhs.text < rhs.text
        }

        return (train, test)
    }

    static func makeTable(from samples: [Sample]) throws -> MLDataTable {
        let texts = samples.map(\.text)
        let labels = samples.map(\.label)
        return try MLDataTable(dictionary: [
            "text": texts,
            "label": labels,
        ])
    }
}

let cwd = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
do {
    try RetrainFoodIconClassifier.run(repoRoot: cwd)
} catch {
    fputs("Error: \(error)\n", stderr)
    exit(1)
}
