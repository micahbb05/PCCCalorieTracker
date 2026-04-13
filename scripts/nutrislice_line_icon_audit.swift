import Foundation
import CoreML
import NaturalLanguage

struct Venue {
    let key: String
    let title: String
    let schoolSlug: String
    let menuTypes: [MenuType]
}

enum MenuType: String, CaseIterable {
    case breakfast
    case lunch
    case dinner

    var title: String { rawValue.capitalized }

    func pathComponent(for venueKey: String) -> String {
        venueKey == "grabNGo" ? "gng-\(rawValue)" : rawValue
    }
}

struct WeekResponse: Decodable {
    struct Day: Decodable {
        let date: String?
        let menuItems: [MenuItemPayload]

        enum CodingKeys: String, CodingKey {
            case date
            case menuItems = "menu_items"
        }
    }

    let days: [Day]
}

struct MenuItemPayload: Decodable {
    struct Food: Decodable {
        let name: String?
    }

    let isStationHeader: Bool
    let text: String?
    let food: Food?

    enum CodingKeys: String, CodingKey {
        case isStationHeader = "is_station_header"
        case text
        case food
    }
}

struct ParsedLine {
    let name: String
    var items: [String]
}

struct Prediction {
    let label: String?
    let confidence: Double
}

struct FlaggedLine {
    let venue: String
    let menuType: String
    let date: String
    let lineName: String
    let lineLabel: String?
    let lineConfidence: Double
    let dominantItemLabel: String?
    let dominantItemShare: Double
    let classifiedItems: Int
    let totalItems: Int
    let reason: String
    let sampleItems: [String]
}

enum NutrisliceLineIconAudit {
    static let confidenceThreshold: Double = 0.45

    static let venues: [Venue] = [
        Venue(key: "fourWinds", title: "Four Winds", schoolSlug: "four-winds", menuTypes: [.lunch, .dinner]),
        Venue(key: "varsity", title: "Varsity", schoolSlug: "varsity", menuTypes: [.breakfast, .lunch, .dinner]),
        Venue(key: "grabNGo", title: "Grab N Go", schoolSlug: "grab-n-go", menuTypes: [.breakfast, .lunch, .dinner])
    ]

    static func run() async {
        do {
            let cwd = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            let modelPath: URL
            if CommandLine.arguments.count > 1 {
                modelPath = URL(fileURLWithPath: CommandLine.arguments[1], relativeTo: cwd).standardizedFileURL
            } else {
                modelPath = cwd.appendingPathComponent("Calorie Tracker/FoodIconClassifier.mlmodel")
            }

            let nlModel = try loadModel(at: modelPath)
            let chicago = TimeZone(identifier: "America/Chicago") ?? .current
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = chicago

            let now = Date()
            let start = calendar.startOfDay(for: now)
            let dates: [Date] = (0..<14).compactMap { calendar.date(byAdding: .day, value: $0, to: start) }
            let dateSet = Set(dates.map { isoDate($0, calendar: calendar) })
            let anchors: [Date] = [start, calendar.date(byAdding: .day, value: 7, to: start)!]

            var weekCache: [String: WeekResponse.Day] = [:]
            var fetchFailures: [String] = []

            for venue in venues {
                for menuType in venue.menuTypes {
                    for anchor in anchors {
                        do {
                            let response = try await fetchWeek(venue: venue, menuType: menuType, anchorDate: anchor, calendar: calendar)
                            for day in response.days {
                                guard let date = day.date, dateSet.contains(date) else { continue }
                                let key = cacheKey(venue: venue.key, menuType: menuType.rawValue, date: date)
                                weekCache[key] = day
                            }
                        } catch {
                            let anchorDate = isoDate(anchor, calendar: calendar)
                            fetchFailures.append("\(venue.title) \(menuType.title) @ \(anchorDate): \(error.localizedDescription)")
                        }
                    }
                }
            }

            var flagged: [FlaggedLine] = []
            var totalLinesByVenue: [String: Int] = [:]
            var fallbackLinesByVenue: [String: Int] = [:]
            var mismatchLinesByVenue: [String: Int] = [:]
            var lineCoverageByVenue: [String: Set<String>] = [:]
            var mealCoverageByVenue: [String: Int] = [:]

            for venue in venues {
                for menuType in venue.menuTypes {
                    for day in dates {
                        let date = isoDate(day, calendar: calendar)
                        let key = cacheKey(venue: venue.key, menuType: menuType.rawValue, date: date)
                        guard let payloadDay = weekCache[key] else { continue }

                        let lines = parseLines(payloadDay.menuItems)
                        guard !lines.isEmpty else { continue }

                        mealCoverageByVenue[venue.title, default: 0] += 1
                        lineCoverageByVenue[venue.title, default: []].insert(date)

                        for line in lines {
                            totalLinesByVenue[venue.title, default: 0] += 1

                            let linePred = predict(line.name, model: nlModel)
                            let itemPreds = line.items.map { predict($0, model: nlModel) }
                            let itemLabels = itemPreds.compactMap { $0.label }

                            var dominantLabel: String?
                            var dominantCount = 0
                            if !itemLabels.isEmpty {
                                var counts: [String: Int] = [:]
                                for label in itemLabels { counts[label, default: 0] += 1 }
                                if let best = counts.max(by: { lhs, rhs in
                                    if lhs.value != rhs.value { return lhs.value < rhs.value }
                                    return lhs.key > rhs.key
                                }) {
                                    dominantLabel = best.key
                                    dominantCount = best.value
                                }
                            }

                            let dominantShare = itemLabels.isEmpty ? 0.0 : (Double(dominantCount) / Double(itemLabels.count))

                            if linePred.label == nil {
                                fallbackLinesByVenue[venue.title, default: 0] += 1
                                flagged.append(
                                    FlaggedLine(
                                        venue: venue.title,
                                        menuType: menuType.title,
                                        date: date,
                                        lineName: line.name,
                                        lineLabel: nil,
                                        lineConfidence: linePred.confidence,
                                        dominantItemLabel: dominantLabel,
                                        dominantItemShare: dominantShare,
                                        classifiedItems: itemLabels.count,
                                        totalItems: line.items.count,
                                        reason: "fallback",
                                        sampleItems: Array(line.items.prefix(3))
                                    )
                                )
                                continue
                            }

                            if let dominantLabel,
                               itemLabels.count >= 2,
                               dominantShare >= 0.60,
                               linePred.label != dominantLabel {
                                mismatchLinesByVenue[venue.title, default: 0] += 1
                                flagged.append(
                                    FlaggedLine(
                                        venue: venue.title,
                                        menuType: menuType.title,
                                        date: date,
                                        lineName: line.name,
                                        lineLabel: linePred.label,
                                        lineConfidence: linePred.confidence,
                                        dominantItemLabel: dominantLabel,
                                        dominantItemShare: dominantShare,
                                        classifiedItems: itemLabels.count,
                                        totalItems: line.items.count,
                                        reason: "line-vs-items-mismatch",
                                        sampleItems: Array(line.items.prefix(3))
                                    )
                                )
                            }
                        }
                    }
                }
            }

            let formatter = DateFormatter()
            formatter.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
            formatter.timeZone = TimeZone(secondsFromGMT: 0)
            let stamp = formatter.string(from: Date())

            let outDir = cwd.appendingPathComponent("output")
            try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

            let textPath = outDir.appendingPathComponent("nutrislice_line_icon_audit_\(stamp).txt")
            let jsonPath = outDir.appendingPathComponent("nutrislice_line_icon_audit_\(stamp).json")

            var lines: [String] = []
            lines.append("Nutrislice Line Name -> FoodIcon ML Audit")
            lines.append("Generated: \(ISO8601DateFormatter().string(from: Date()))")
            lines.append("Model: \(modelPath.path)")
            lines.append("Confidence threshold: \(confidenceThreshold)")
            lines.append("Date window (America/Chicago): \(isoDate(dates.first!, calendar: calendar)) to \(isoDate(dates.last!, calendar: calendar))")
            lines.append("")
            lines.append("Venue summary:")

            for venue in venues {
                let v = venue.title
                let total = totalLinesByVenue[v, default: 0]
                let fallback = fallbackLinesByVenue[v, default: 0]
                let mismatch = mismatchLinesByVenue[v, default: 0]
                let meals = mealCoverageByVenue[v, default: 0]
                let daysCovered = lineCoverageByVenue[v, default: []].count
                lines.append("- \(v): lines=\(total), flagged=\(fallback + mismatch) (fallback=\(fallback), mismatch=\(mismatch)), menu-days-with-lines=\(daysCovered), meal-fetches-with-lines=\(meals)")
            }

            lines.append("")
            lines.append("Flagged lines (all):")
            if flagged.isEmpty {
                lines.append("- none")
            } else {
                for f in flagged.sorted(by: sortFlags) {
                    let lineLabel = f.lineLabel ?? "<fallback>"
                    let dom = f.dominantItemLabel ?? "<none>"
                    let sharePct = String(format: "%.0f%%", f.dominantItemShare * 100.0)
                    lines.append("- [\(f.venue)] \(f.date) \(f.menuType) | \(f.lineName) | line=\(lineLabel) (\(String(format: "%.2f", f.lineConfidence))) | dominant-items=\(dom) (\(sharePct), \(f.classifiedItems)/\(f.totalItems)) | reason=\(f.reason) | items=\(f.sampleItems.joined(separator: " ; "))")
                }
            }

            if !fetchFailures.isEmpty {
                lines.append("")
                lines.append("Fetch failures:")
                for f in fetchFailures.sorted() { lines.append("- \(f)") }
            }

            try lines.joined(separator: "\n").write(to: textPath, atomically: true, encoding: .utf8)

            let json: [String: Any] = [
                "generatedAt": ISO8601DateFormatter().string(from: Date()),
                "model": modelPath.path,
                "confidenceThreshold": confidenceThreshold,
                "dateWindow": [
                    "start": isoDate(dates.first!, calendar: calendar),
                    "end": isoDate(dates.last!, calendar: calendar)
                ],
                "summaryByVenue": Dictionary(uniqueKeysWithValues: venues.map { venue in
                    let v = venue.title
                    return (v, [
                        "totalLines": totalLinesByVenue[v, default: 0],
                        "flaggedLines": fallbackLinesByVenue[v, default: 0] + mismatchLinesByVenue[v, default: 0],
                        "fallbackLines": fallbackLinesByVenue[v, default: 0],
                        "mismatchLines": mismatchLinesByVenue[v, default: 0],
                        "menuDaysWithLines": lineCoverageByVenue[v, default: []].count,
                        "mealFetchesWithLines": mealCoverageByVenue[v, default: 0]
                    ] as [String : Any])
                }),
                "flaggedLines": flagged.map { f in
                    [
                        "venue": f.venue,
                        "menuType": f.menuType,
                        "date": f.date,
                        "lineName": f.lineName,
                        "lineLabel": f.lineLabel as Any,
                        "lineConfidence": f.lineConfidence,
                        "dominantItemLabel": f.dominantItemLabel as Any,
                        "dominantItemShare": f.dominantItemShare,
                        "classifiedItems": f.classifiedItems,
                        "totalItems": f.totalItems,
                        "reason": f.reason,
                        "sampleItems": f.sampleItems
                    ]
                },
                "fetchFailures": fetchFailures
            ]

            let jsonData = try JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys])
            try jsonData.write(to: jsonPath)

            print("Audit complete")
            print("Report TXT: \(textPath.path)")
            print("Report JSON: \(jsonPath.path)")
            for venue in venues {
                let v = venue.title
                let total = totalLinesByVenue[v, default: 0]
                let flaggedCount = fallbackLinesByVenue[v, default: 0] + mismatchLinesByVenue[v, default: 0]
                print("\(v): \(flaggedCount)/\(total) flagged")
            }
            if !fetchFailures.isEmpty {
                print("Fetch failures: \(fetchFailures.count)")
            }
        } catch {
            fputs("Audit failed: \(error)\n", stderr)
            exit(1)
        }
    }

    static func sortFlags(_ lhs: FlaggedLine, _ rhs: FlaggedLine) -> Bool {
        if lhs.venue != rhs.venue { return lhs.venue < rhs.venue }
        if lhs.date != rhs.date { return lhs.date < rhs.date }
        if lhs.menuType != rhs.menuType { return lhs.menuType < rhs.menuType }
        return lhs.lineName < rhs.lineName
    }

    static func cacheKey(venue: String, menuType: String, date: String) -> String {
        "\(venue)|\(menuType)|\(date)"
    }

    static func loadModel(at modelPath: URL) throws -> NLModel {
        let compiled = try MLModel.compileModel(at: modelPath)
        return try NLModel(contentsOf: compiled)
    }

    static func fetchWeek(venue: Venue, menuType: MenuType, anchorDate: Date, calendar: Calendar) async throws -> WeekResponse {
        let datePath = pathDate(anchorDate, calendar: calendar)
        let menuPath = menuType.pathComponent(for: venue.key)
        let urlString = "https://pccdining.api.nutrislice.com/menu/api/weeks/school/\(venue.schoolSlug)/menu-type/\(menuPath)/\(datePath)/"
        guard let url = URL(string: urlString) else {
            throw NSError(domain: "NutrisliceLineAudit", code: 1, userInfo: [NSLocalizedDescriptionKey: "Bad URL: \(urlString)"])
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("CalorieTrackerAudit/1.0", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? -1
            throw NSError(domain: "NutrisliceLineAudit", code: 2, userInfo: [NSLocalizedDescriptionKey: "HTTP \(code)"])
        }

        return try JSONDecoder().decode(WeekResponse.self, from: data)
    }

    static func parseLines(_ items: [MenuItemPayload]) -> [ParsedLine] {
        var lines: [ParsedLine] = []

        for item in items {
            let header = trimmed(item.text)
            if item.isStationHeader, !header.isEmpty {
                lines.append(ParsedLine(name: header, items: []))
                continue
            }

            let itemName = trimmed(item.food?.name)
            guard !itemName.isEmpty else { continue }

            if lines.isEmpty {
                lines.append(ParsedLine(name: "Menu", items: []))
            }

            lines[lines.count - 1].items.append(itemName)
        }

        return lines.filter { !$0.items.isEmpty }
    }

    static func predict(_ text: String, model: NLModel) -> Prediction {
        let normalized = normalize(text)
        guard !normalized.isEmpty else {
            return Prediction(label: nil, confidence: 0)
        }

        guard let (label, confidence) = model.predictedLabelHypotheses(for: normalized, maximumCount: 1).first else {
            return Prediction(label: nil, confidence: 0)
        }

        if confidence >= confidenceThreshold {
            return Prediction(label: label, confidence: confidence)
        }
        return Prediction(label: nil, confidence: confidence)
    }

    static let linePrefixRegex = try? NSRegularExpression(pattern: #"^line\s+\d+\s+"#, options: .caseInsensitive)

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

        if let re = linePrefixRegex {
            let ns = s as NSString
            let range = NSRange(location: 0, length: ns.length)
            s = re.stringByReplacingMatches(in: s, range: range, withTemplate: "")
        }

        while s.contains("  ") {
            s = s.replacingOccurrences(of: "  ", with: " ")
        }

        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func isoDate(_ date: Date, calendar: Calendar) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 1970, c.month ?? 1, c.day ?? 1)
    }

    static func pathDate(_ date: Date, calendar: Calendar) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d/%02d/%02d", c.year ?? 1970, c.month ?? 1, c.day ?? 1)
    }

    static func trimmed(_ s: String?) -> String {
        (s ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

let semaphore = DispatchSemaphore(value: 0)
Task {
    await NutrisliceLineIconAudit.run()
    semaphore.signal()
}
semaphore.wait()
