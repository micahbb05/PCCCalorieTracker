import Foundation
import CoreML
import NaturalLanguage

struct Sample {
    let text: String
    let expectedLabel: String
}

struct RuleParseResult {
    let samples: [Sample]
    let duplicateDropped: Int
}

struct EvalResult {
    let total: Int
    let correct: Int
    let thresholdFallbacks: Int
    let missingPredictions: Int
    let perLabelTotal: [String: Int]
    let perLabelCorrect: [String: Int]
    let topMistakes: [(expected: String, predicted: String, count: Int)]
}

enum FoodIconAccuracyEval {
    static let confidenceThreshold: Double = 0.45

    static func run(repoRoot: URL) throws {
        let mapperPath = repoRoot.appendingPathComponent("Calorie Tracker/FoodSymbolMapper.swift")
        let modelPath: URL
        if CommandLine.arguments.count > 1 {
            modelPath = URL(fileURLWithPath: CommandLine.arguments[1], relativeTo: repoRoot).standardizedFileURL
        } else {
            modelPath = repoRoot.appendingPathComponent("Calorie Tracker/FoodIconClassifier.mlmodel")
        }
        let outputPath = repoRoot.appendingPathComponent("output/food_icon_model_accuracy_report.txt")

        let parse = try parseSamples(from: mapperPath)
        let model = try loadNLModel(from: modelPath)
        let result = evaluate(samples: parse.samples, model: model)

        let accuracy = result.total == 0 ? 0.0 : (Double(result.correct) / Double(result.total))
        let pct = String(format: "%.2f", accuracy * 100.0)

        var lines: [String] = []
        lines.append("Food Icon ML Model Accuracy Report")
        lines.append("Generated: \(ISO8601DateFormatter().string(from: Date()))")
        lines.append("Model: \(modelPath.path)")
        lines.append("Source labels: Calorie Tracker/FoodSymbolMapper.swift assetBackedRules keywords")
        lines.append("Confidence threshold: \(confidenceThreshold)")
        lines.append("")
        lines.append("Samples: \(result.total)")
        lines.append("Correct: \(result.correct)")
        lines.append("Top-1 Accuracy: \(pct)%")
        lines.append("Threshold fallbacks (predictions below threshold): \(result.thresholdFallbacks)")
        lines.append("Missing predictions: \(result.missingPredictions)")
        lines.append("Duplicate (label,text) samples dropped: \(parse.duplicateDropped)")
        lines.append("")
        lines.append("Per-label accuracy (top 20 by volume):")

        let sortedLabels = result.perLabelTotal
            .sorted { lhs, rhs in
                if lhs.value != rhs.value { return lhs.value > rhs.value }
                return lhs.key < rhs.key
            }
            .map { $0.key }

        for label in sortedLabels.prefix(20) {
            let total = result.perLabelTotal[label] ?? 0
            let correct = result.perLabelCorrect[label] ?? 0
            let p = total == 0 ? 0.0 : Double(correct) / Double(total) * 100.0
            lines.append("- \(label): \(correct)/\(total) (\(String(format: "%.1f", p))%)")
        }

        lines.append("")
        lines.append("Top misclassifications (up to 25):")
        if result.topMistakes.isEmpty {
            lines.append("- none")
        } else {
            for m in result.topMistakes.prefix(25) {
                lines.append("- \(m.expected) -> \(m.predicted): \(m.count)")
            }
        }

        try FileManager.default.createDirectory(at: outputPath.deletingLastPathComponent(), withIntermediateDirectories: true)
        try lines.joined(separator: "\n").write(to: outputPath, atomically: true, encoding: .utf8)

        print("Top-1 accuracy: \(pct)% (\(result.correct)/\(result.total))")
        print("Samples: \(result.total), threshold fallbacks: \(result.thresholdFallbacks), missing: \(result.missingPredictions)")
        print("Dropped duplicates: \(parse.duplicateDropped)")
        print("Report: \(outputPath.path)")
    }

    static func parseSamples(from mapperPath: URL) throws -> RuleParseResult {
        let src = try String(contentsOf: mapperPath, encoding: .utf8)

        guard let startRange = src.range(of: "private static let assetBackedRules: [Rule] = [") else {
            throw NSError(domain: "FoodIconAccuracyEval", code: 1, userInfo: [NSLocalizedDescriptionKey: "assetBackedRules start not found"]) 
        }
        guard let endRange = src.range(of: "private static let sfSymbolRules:", options: [], range: startRange.upperBound..<src.endIndex) else {
            throw NSError(domain: "FoodIconAccuracyEval", code: 2, userInfo: [NSLocalizedDescriptionKey: "assetBackedRules end not found"]) 
        }

        let block = String(src[startRange.upperBound..<endRange.lowerBound])
        let lines = block.components(separatedBy: .newlines)

        var samples: [Sample] = []
        var seen = Set<String>()
        var duplicateDropped = 0

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
                    samples.append(Sample(text: phrase, expectedLabel: label))
                } else {
                    duplicateDropped += 1
                }
            }

            if line.hasPrefix("]),") || line == "])" {
                inKeywords = false
                currentLabel = nil
            }
        }

        return RuleParseResult(samples: samples, duplicateDropped: duplicateDropped)
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

    static func loadNLModel(from modelPath: URL) throws -> NLModel {
        let compiled = try MLModel.compileModel(at: modelPath)
        return try NLModel(contentsOf: compiled)
    }

    static func evaluate(samples: [Sample], model: NLModel) -> EvalResult {
        var correct = 0
        var thresholdFallbacks = 0
        var missingPredictions = 0
        var perLabelTotal: [String: Int] = [:]
        var perLabelCorrect: [String: Int] = [:]
        var mistakes: [String: Int] = [:]

        for s in samples {
            perLabelTotal[s.expectedLabel, default: 0] += 1

            let normalized = normalize(s.text)
            let predicted: String?
            let hypotheses = model.predictedLabelHypotheses(for: normalized, maximumCount: 1)
            if let (label, conf) = hypotheses.first {
                if conf >= confidenceThreshold {
                    predicted = label
                } else {
                    predicted = nil
                    thresholdFallbacks += 1
                }
            } else {
                predicted = nil
                missingPredictions += 1
            }

            if let predicted, predicted == s.expectedLabel {
                correct += 1
                perLabelCorrect[s.expectedLabel, default: 0] += 1
            } else {
                let p = predicted ?? "<fallback>"
                let key = "\(s.expectedLabel)->\(p)"
                mistakes[key, default: 0] += 1
            }
        }

        let topMistakes = mistakes
            .map { (k, v) -> (expected: String, predicted: String, count: Int) in
                let parts = k.components(separatedBy: "->")
                let expected = parts.first ?? "?"
                let predicted = parts.count > 1 ? parts[1] : "?"
                return (expected: expected, predicted: predicted, count: v)
            }
            .sorted {
                if $0.count != $1.count { return $0.count > $1.count }
                if $0.expected != $1.expected { return $0.expected < $1.expected }
                return $0.predicted < $1.predicted
            }

        return EvalResult(
            total: samples.count,
            correct: correct,
            thresholdFallbacks: thresholdFallbacks,
            missingPredictions: missingPredictions,
            perLabelTotal: perLabelTotal,
            perLabelCorrect: perLabelCorrect,
            topMistakes: topMistakes
        )
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
            s = re.stringByReplacingMatches(in: s, range: NSRange(location: 0, length: ns.length), withTemplate: "")
        }

        while s.contains("  ") {
            s = s.replacingOccurrences(of: "  ", with: " ")
        }

        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }

}

let cwd = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
do {
    try FoodIconAccuracyEval.run(repoRoot: cwd)
} catch {
    fputs("Error: \(error)\n", stderr)
    exit(1)
}
