import Foundation

enum DiningVenue: String, CaseIterable, Identifiable {
    case fourWinds
    case varsity
    case grabNGo

    var id: String { rawValue }

    var title: String {
        switch self {
        case .fourWinds:
            return "Four Winds"
        case .varsity:
            return "Varsity"
        case .grabNGo:
            return "Grab N Go"
        }
    }

    var schoolSlug: String {
        switch self {
        case .fourWinds:
            return "four-winds"
        case .varsity:
            return "varsity"
        case .grabNGo:
            return "grab-n-go"
        }
    }

    var supportedMenuTypes: Set<NutrisliceMenuService.MenuType> {
        switch self {
        case .fourWinds:
            return [.lunch, .dinner]
        case .varsity, .grabNGo:
            return [.breakfast, .lunch, .dinner]
        }
    }
}

struct MenuItem: Identifiable, Hashable {
    let id: String
    let name: String
    let calories: Int
    let nutrientValues: [String: Int]
    let servingAmount: Double
    let servingUnit: String

    var protein: Int {
        nutrientValues["g_protein"] ?? 0
    }
}

struct MenuLine: Identifiable, Hashable {
    let id: String
    let name: String
    let items: [MenuItem]
}

struct NutrisliceMenu: Hashable {
    let lines: [MenuLine]
    let nutrientNullRateByKey: [String: Double]

    static let empty = NutrisliceMenu(lines: [], nutrientNullRateByKey: [:])
}

enum NutrisliceMenuError: LocalizedError {
    case badURL
    case fetchFailed(statusCode: Int)
    case networkFailure
    case invalidPayload
    case noMenuAvailable
    case unavailableAtThisTime(venue: DiningVenue, menuType: NutrisliceMenuService.MenuType)

    var errorDescription: String? {
        switch self {
        case .badURL:
            return "Failed to build the menu URL."
        case let .fetchFailed(statusCode):
            return "Could not load menu data (HTTP \(statusCode))."
        case .networkFailure:
            return "Could not load menu data. Check your internet connection."
        case .invalidPayload:
            return "Menu response is malformed."
        case .noMenuAvailable:
            return "No menu items are currently available."
        case let .unavailableAtThisTime(venue, menuType):
            return "\(venue.title) \(menuType.title.lowercased()) is not available at this time."
        }
    }
}

final class NutrisliceMenuService {
    enum MenuType: String {
        case breakfast
        case lunch
        case dinner

        var title: String {
            switch self {
            case .breakfast:
                return "Breakfast"
            case .lunch:
                return "Lunch"
            case .dinner:
                return "Dinner"
            }
        }
    }

    private struct NutrisliceWeekResponse: Decodable {
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

    private struct MenuItemPayload: Decodable {
        struct Food: Decodable {
            struct ServingSizeInfo: Decodable {
                let servingSizeAmount: String?
                let servingSizeUnit: String?

                enum CodingKeys: String, CodingKey {
                    case servingSizeAmount = "serving_size_amount"
                    case servingSizeUnit = "serving_size_unit"
                }
            }

            struct RoundedNutritionInfo: Decodable {
                struct DynamicKey: CodingKey {
                    let stringValue: String
                    init?(stringValue: String) { self.stringValue = stringValue }
                    let intValue: Int? = nil
                    init?(intValue: Int) { return nil }
                }

                let values: [String: Double?]

                init(from decoder: Decoder) throws {
                    let container = try decoder.container(keyedBy: DynamicKey.self)
                    var result: [String: Double?] = [:]
                    for key in container.allKeys {
                        if try container.decodeNil(forKey: key) {
                            result[key.stringValue] = nil
                        } else {
                            let numeric = try container.decodeIfPresent(Double.self, forKey: key)
                            result[key.stringValue] = numeric
                        }
                    }
                    values = result
                }
            }

            let id: Int?
            let name: String?
            let roundedNutritionInfo: RoundedNutritionInfo?
            let servingSizeInfo: ServingSizeInfo?

            enum CodingKeys: String, CodingKey {
                case id
                case name
                case roundedNutritionInfo = "rounded_nutrition_info"
                case servingSizeInfo = "serving_size_info"
            }
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

    private let centralTimeZone = TimeZone(identifier: "America/Chicago") ?? .current

    func currentMenuSignature(for venue: DiningVenue, now: Date = Date()) -> String {
        "\(venue.rawValue)-\(currentMenuType(now: now).rawValue)-\(currentISODate(now: now))"
    }

    func currentCentralDayIdentifier(now: Date = Date()) -> String {
        currentISODate(now: now)
    }

    func currentMenuType(now: Date = Date()) -> MenuType {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = centralTimeZone
        let components = calendar.dateComponents([.hour, .minute], from: now)
        let hour = components.hour ?? 0
        let minute = components.minute ?? 0

        if hour < 10 || (hour == 10 && minute < 45) {
            return .breakfast
        }
        if hour < 16 || (hour == 16 && minute < 45) {
            return .lunch
        }
        return .dinner
    }

    func fetchTodayMenu(for venue: DiningVenue) async throws -> NutrisliceMenu {
        let menuType = currentMenuType()
        guard venue.supportedMenuTypes.contains(menuType) else {
            throw NutrisliceMenuError.unavailableAtThisTime(venue: venue, menuType: menuType)
        }

        let menuTypeSlug = menuTypePathComponent(for: venue, menuType: menuType)
        let sourceURLString = "https://pccdining.api.nutrislice.com/menu/api/weeks/school/\(venue.schoolSlug)/menu-type/\(menuTypeSlug)/\(currentPathDate())/"
        guard let url = URL(string: sourceURLString) else {
            throw NutrisliceMenuError.badURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("CalorieTracker/1.0 (iOS)", forHTTPHeaderField: "User-Agent")

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw NutrisliceMenuError.networkFailure
        }

        guard let http = response as? HTTPURLResponse else {
            throw NutrisliceMenuError.invalidPayload
        }
        guard (200...299).contains(http.statusCode) else {
            throw NutrisliceMenuError.fetchFailed(statusCode: http.statusCode)
        }

        let decoded: NutrisliceWeekResponse
        do {
            decoded = try JSONDecoder().decode(NutrisliceWeekResponse.self, from: data)
        } catch {
            throw NutrisliceMenuError.invalidPayload
        }

        let todayISO = currentISODate()
        guard let today = decoded.days.first(where: { $0.date == todayISO }) else {
            throw NutrisliceMenuError.noMenuAvailable
        }

        let parsedLines = parseLines(from: today.menuItems)
        let nullRates = nutrientNullRates(from: decoded.days)

        guard !parsedLines.isEmpty else {
            throw NutrisliceMenuError.noMenuAvailable
        }

        return NutrisliceMenu(lines: parsedLines, nutrientNullRateByKey: nullRates)
    }

    private func menuTypePathComponent(for venue: DiningVenue, menuType: MenuType) -> String {
        switch venue {
        case .grabNGo:
            return "gng-\(menuType.rawValue)"
        case .fourWinds, .varsity:
            return menuType.rawValue
        }
    }

    private func currentPathDate(now: Date = Date()) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = centralTimeZone
        let components = calendar.dateComponents([.year, .month, .day], from: now)
        let year = components.year ?? 1970
        let month = components.month ?? 1
        let day = components.day ?? 1
        return String(format: "%04d/%02d/%02d", year, month, day)
    }

    private func currentISODate(now: Date = Date()) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = centralTimeZone
        let components = calendar.dateComponents([.year, .month, .day], from: now)
        let year = components.year ?? 1970
        let month = components.month ?? 1
        let day = components.day ?? 1
        return String(format: "%04d-%02d-%02d", year, month, day)
    }

    private func parseLines(from items: [MenuItemPayload]) -> [MenuLine] {
        var lines: [MenuLine] = []

        for item in items {
            let header = trimmed(item.text)
            if item.isStationHeader, !header.isEmpty {
                let lineID = slug(from: header).isEmpty ? "line-\(lines.count + 1)" : slug(from: header)
                lines.append(MenuLine(id: lineID, name: header, items: []))
                continue
            }

            guard let food = item.food else { continue }
            let itemName = trimmed(food.name)
            guard !itemName.isEmpty else { continue }

            let roundedInfo = food.roundedNutritionInfo?.values ?? [:]
            var nutrients: [String: Int] = [:]
            for (key, value) in roundedInfo {
                if let value, value >= 0 {
                    nutrients[key] = Int(value.rounded())
                }
            }

            let calories = nutrients["calories"] ?? 0
            if lines.isEmpty {
                lines.append(MenuLine(id: "menu", name: "Menu", items: []))
            }

            let lastIndex = lines.index(before: lines.endIndex)
            let fallbackID = "\(lines[lastIndex].id)-item-\(lines[lastIndex].items.count + 1)"
            let itemID = food.id.map(String.init) ?? fallbackID
            let servingAmount = parseServingAmount(food.servingSizeInfo?.servingSizeAmount)
            let servingUnit = parseServingUnit(food.servingSizeInfo?.servingSizeUnit)
            var updatedItems = lines[lastIndex].items
            updatedItems.append(
                MenuItem(
                    id: itemID,
                    name: itemName,
                    calories: calories,
                    nutrientValues: nutrients,
                    servingAmount: servingAmount,
                    servingUnit: servingUnit
                )
            )
            lines[lastIndex] = MenuLine(id: lines[lastIndex].id, name: lines[lastIndex].name, items: updatedItems)
        }

        return lines.filter { !$0.items.isEmpty }
    }

    private func nutrientNullRates(from days: [NutrisliceWeekResponse.Day]) -> [String: Double] {
        var nullCounts: [String: Int] = [:]
        var totalCounts: [String: Int] = [:]

        for day in days {
            for payload in day.menuItems {
                guard let rounded = payload.food?.roundedNutritionInfo?.values else { continue }
                for (key, value) in rounded {
                    let normalized = key.lowercased()
                    totalCounts[normalized, default: 0] += 1
                    if value == nil {
                        nullCounts[normalized, default: 0] += 1
                    }
                }
            }
        }

        var result: [String: Double] = [:]
        for (key, total) in totalCounts where total > 0 {
            let nulls = nullCounts[key, default: 0]
            result[key] = Double(nulls) / Double(total)
        }
        return result
    }

    private func extractLineNumber(from title: String) -> Int? {
        let pattern = #"(?i)line\s*(\d+)"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return nil
        }
        let range = NSRange(title.startIndex..<title.endIndex, in: title)
        guard let match = regex.firstMatch(in: title, range: range),
              match.numberOfRanges > 1,
              let numberRange = Range(match.range(at: 1), in: title)
        else {
            return nil
        }
        return Int(title[numberRange])
    }

    private func trimmed(_ input: String?) -> String {
        (input ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func slug(from input: String) -> String {
        let lowered = input.lowercased()
        let hyphenated = lowered.replacingOccurrences(of: "[^a-z0-9]+", with: "-", options: .regularExpression)
        return hyphenated.replacingOccurrences(of: "^-+|-+$", with: "", options: .regularExpression)
    }

    private func parseServingAmount(_ input: String?) -> Double {
        let trimmed = (input ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return 1.0 }
        let normalized = trimmed.replacingOccurrences(of: ",", with: ".")
        return Double(normalized).flatMap { $0 > 0 ? $0 : nil } ?? 1.0
    }

    private func parseServingUnit(_ input: String?) -> String {
        let trimmed = (input ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "serving" : trimmed
    }
}
