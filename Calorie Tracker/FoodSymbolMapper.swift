import Foundation

/// Food log pictograms: SF Symbols and bundled **`FoodIcon*`** vectors in `Assets.xcassets`.
/// Every `FoodIcon*.svg` is sourced from **Lucide** (ISC, https://github.com/lucide-icons/lucide) via
/// `scripts/sync_lucide_food_icons.py` (stroke icons normalized to `#000` template SVGs). Mappings for
/// foods Lucide does not name (e.g. taco → `sandwich`, burrito → `cylinder`) live in that script.
/// Pure SF Symbol rows (e.g. condiment `sparkles`) are not `FoodIcon*` assets.

/// Resolved icon for a food log row: system SF Symbol or monochrome template asset (`FoodIcon*` in Assets).
enum FoodLogIconToken: Equatable {
    case sf(String)
    case asset(name: String, fallback: String)
}

/// Maps free-text food descriptions to SF Symbols or bundled template assets (SF-style weight at draw time).
enum FoodSymbolMapper {

    /// Names of single-color template vectors in `Calorie Tracker/Assets.xcassets` (`FoodIcon*.imageset`), same pipeline as `FoodIconBurrito`, `FoodIconPizza`, etc.
    private enum BundledFoodIconAsset {
        static let burrito = "FoodIconBurrito"
        static let burritoSFFallback = "takeoutbag.and.cup.and.straw"
    }

    static func icon(for raw: String) -> FoodLogIconToken {
        let haystack = normalizedHaystack(raw)
        let trimmed = haystack.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return .sf("fork.knife")
        }

        if let exact = exactMatchIcon(for: trimmed) {
            return exact
        }

        // Unknown text: platter icon reads like “empty tray” in lists; fork reads more like “food”.
        var best: FoodLogIconToken = .sf("fork.knife")
        var bestScore = 0
        var bestIndex = Int.max

        for (index, rule) in rules.enumerated() {
            // Phrase keywords like “po boy” bypass single-token deli guards; never use deli-wrap pictograms for burrito-style names.
            if case .asset(let assetName, _) = rule.token, haystackMentionsBurrito(haystack) {
                if assetName == "FoodIconSandwich" || assetName == "FoodIconWrap" {
                    continue
                }
            }
            var score = 0
            for keyword in rule.keywords where matches(haystack: haystack, keyword: keyword) {
                score += matchWeight(keyword: keyword)
            }
            guard score > 0 else { continue }
            if score > bestScore || (score == bestScore && index < bestIndex) {
                bestScore = score
                best = rule.token
                bestIndex = index
            }
        }

        let remapped = remapDeliSandwichIfBurritoInName(best, haystack: haystack)
        return preferBurritoIconWhenNamed(remapped, haystack: haystack)
    }

    /// If the name is clearly burrito / chimichanga / quesadilla context, always show the burrito pictogram (avoids any other rule out-scoring and picking a sandwich-like glyph).
    private static func preferBurritoIconWhenNamed(_ token: FoodLogIconToken, haystack: String) -> FoodLogIconToken {
        guard haystackMentionsBurrito(haystack) else { return token }
        if case .asset(let name, _) = token, name == BundledFoodIconAsset.burrito { return token }
        return .asset(name: BundledFoodIconAsset.burrito, fallback: BundledFoodIconAsset.burritoSFFallback)
    }

    /// Last-resort guard: if scoring still picked a deli sandwich–style pictogram, swap to burrito whenever the name clearly says burrito (substring catches odd tokenization / typos).
    private static func remapDeliSandwichIfBurritoInName(_ token: FoodLogIconToken, haystack: String) -> FoodLogIconToken {
        guard haystackMentionsBurrito(haystack) else { return token }
        if case .asset(let name, _) = token, name == "FoodIconSandwich" || name == "FoodIconWrap" {
            return .asset(name: BundledFoodIconAsset.burrito, fallback: BundledFoodIconAsset.burritoSFFallback)
        }
        return token
    }

    private static func normalizedHaystack(_ raw: String) -> String {
        var h = raw
            .lowercased()
            .folding(options: .diacriticInsensitive, locale: .current)
            .replacingOccurrences(of: "'", with: "")
        // PCC / Nutrislice station titles often use en dash or missing dash: "Line 5 – Hot Dogs", "Line 6 Taqueria".
        for dash in ["\u{2013}", "\u{2014}", "\u{2015}", "\u{2212}"] {
            h = h.replacingOccurrences(of: dash, with: " ")
        }
        h = h.replacingOccurrences(of: "&", with: " and ")
        h = h.replacingOccurrences(of: "/", with: " ")
        h = h.replacingOccurrences(of: "-", with: " ")
        while h.contains("  ") {
            h = h.replacingOccurrences(of: "  ", with: " ")
        }
        h = stripLeadingMenuLineLabel(h)
        while h.contains("  ") {
            h = h.replacingOccurrences(of: "  ", with: " ")
        }
        return h
    }

    /// Strips Nutrislice-style prefixes so keywords match the food name ("Line 5 - Hot Dogs" → "Hot Dogs").
    private static func stripLeadingMenuLineLabel(_ s: String) -> String {
        let pattern = #"^(?i)line\s+\d+\s+"#
        guard let re = try? NSRegularExpression(pattern: pattern, options: []) else { return s }
        let range = NSRange(s.startIndex..., in: s)
        return re.stringByReplacingMatches(in: s, options: [], range: range, withTemplate: "")
    }

    private static func exactMatchIcon(for trimmed: String) -> FoodLogIconToken? {
        let tokens = trimmed.split { !$0.isLetter && !$0.isNumber }.map(String.init).filter { !$0.isEmpty }
        if tokens == ["seasoned", "rice", "pilaf"] {
            return .asset(name: "FoodIconRiceBowl", fallback: "bowl.fill")
        }
        guard tokens.count <= 2 else { return nil }

        switch tokens {
        case ["egg"], ["eggs"]:
            return .asset(name: "FoodIconEgg", fallback: "frying.pan.fill")
        case ["bread"], ["toast"]:
            return .asset(name: "FoodIconBread", fallback: "bag.fill")
        case ["fried", "rice"], ["rice", "fried"]:
            return .asset(name: "FoodIconRiceBowl", fallback: "bowl.fill")
        case ["pork"]:
            return .asset(name: "FoodIconPork", fallback: "fork.knife")
        case ["rice"], ["pilaf"]:
            return .sf("bowl.fill")
        default:
            return nil
        }
    }

    private static func matchWeight(keyword: String) -> Int {
        let k = normalizedMatchKey(keyword)
        let isPhrase = k.contains(where: { $0.isWhitespace }) || keyword.contains("-")
        let base = k.count + 2
        return isPhrase ? base * 5 : base
    }

    private static func normalizedMatchKey(_ keyword: String) -> String {
        var k = keyword.replacingOccurrences(of: "'", with: "")
        k = k.replacingOccurrences(of: "-", with: " ")
        while k.contains("  ") {
            k = k.replacingOccurrences(of: "  ", with: " ")
        }
        return k.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func haystackTokens(_ haystack: String) -> [String] {
        haystack.split { !$0.isLetter && !$0.isNumber }.map(String.init).filter { !$0.isEmpty }
    }

    /// Whole-token match with cheap English plural agreement (`burrito` ↔ `burritos`, `potato` ↔ `potatoes`).
    private static func tokenMatchesWord(_ token: String, _ word: String) -> Bool {
        if token == word { return true }
        if token == word + "s" || token == word + "es" { return true }
        if word == token + "s" || word == token + "es" { return true }
        if word.hasSuffix("y"), !word.hasSuffix("ey"), token == String(word.dropLast()) + "ies" { return true }
        if token.hasSuffix("y"), !token.hasSuffix("ey"), word == String(token.dropLast()) + "ies" { return true }
        return false
    }

    /// Phrases must match as consecutive whole words (substring `contains` caused false positives, e.g. “sweet potato” in “…potatoes”).
    private static func phraseMatchesAdjacent(haystack: String, phrase: String) -> Bool {
        let k = normalizedMatchKey(phrase)
        guard !k.isEmpty else { return false }
        let words = haystackTokens(k)
        let tokens = haystackTokens(haystack)
        guard !words.isEmpty, !tokens.isEmpty else { return false }
        if words.count == 1 {
            return tokens.contains { tokenMatchesWord($0, words[0]) }
        }
        guard words.count <= tokens.count else { return false }
        for i in 0...(tokens.count - words.count) {
            var all = true
            for j in 0..<words.count {
                if !tokenMatchesWord(tokens[i + j], words[j]) {
                    all = false
                    break
                }
            }
            if all { return true }
        }
        return false
    }

    /// True when the name is clearly Mexican-wrap context (burrito / chimichanga / quesadilla), including odd tokenization.
    private static func haystackMentionsBurrito(_ haystack: String) -> Bool {
        if haystack.contains("burrit") { return true }
        if haystack.contains("chimichang") { return true }
        if haystack.contains("quesadill") { return true }
        return haystackTokens(haystack).contains { token in
            let t = token.lowercased()
            if t.hasPrefix("burrit") { return true }
            return tokenMatchesWord(t, "chimichanga") || tokenMatchesWord(t, "quesadilla")
        }
    }

    /// Deli-style sandwich keywords must not win over burrito / quesadilla names (e.g. “submarine” stacking with other tokens).
    private static let deliSandwichSingleTokens: Set<String> = [
        "sandwich", "blt", "panini", "reuben", "hoagie", "submarine", "grinder",
    ]

    private static func matches(haystack: String, keyword: String) -> Bool {
        let k = normalizedMatchKey(keyword)
        guard !k.isEmpty else { return false }
        if deliSandwichSingleTokens.contains(k), haystackMentionsBurrito(haystack) {
            return false
        }
        // “Ice cream sandwich” is not a deli sandwich — don’t let the lone token `sandwich` steal the match.
        if k == "sandwich", phraseMatchesAdjacent(haystack: haystack, phrase: "ice cream") {
            return false
        }
        // Breaded / fried prep keywords stack heavily on “chicken strips” and beat the chicken pictogram.
        if ["lightly breaded", "breaded", "deep fried", "deep-fried", "air fried", "air-fried"].contains(k),
           haystack.contains("chicken strip") || haystack.contains("chicken tender") || haystack.contains("chicken finger") {
            return false
        }
        let isPhrase = k.contains(where: { $0.isWhitespace }) || keyword.contains("-")
        if isPhrase {
            return phraseMatchesAdjacent(haystack: haystack, phrase: k)
        }
        let tokens = haystackTokens(haystack)
        return tokens.contains { tokenMatchesWord($0, k) }
    }

    private struct Rule {
        let token: FoodLogIconToken
        let keywords: [String]
    }

    /// Asset-backed rules first (ties prefer a specific pictogram), then all SF-only rules.
    private static let rules: [Rule] = assetBackedRules + sfSymbolRules

    private static let assetBackedRules: [Rule] = [
        Rule(token: .sf("sparkles"), keywords: [
            "condiment", "condiments", "topping", "toppings", "fixings", "dressing", "dressings",
            "sauce bar", "sauce station", "topping bar", "garnish", "garnishes", "extras bar",
        ]),
        Rule(token: .asset(name: "FoodIconCookingPot", fallback: "fork.knife"), keywords: [
            "mashed potato", "mashed potatoes", "instant mashed", "instant mashed potatoes",
            "original mashed", "potato flakes", "dehydrated potato",
        ]),
        Rule(token: .asset(name: BundledFoodIconAsset.burrito, fallback: BundledFoodIconAsset.burritoSFFallback), keywords: [
            "burrito", "burritos", "bean burrito", "bean burritos", "beef burrito", "beef burritos",
            "beef and bean burrito", "beef and bean burritos", "bean and cheese burrito", "bean and cheese burritos",
            "breakfast burrito", "breakfast burritos", "wet burrito", "smothered burrito",
            "chimichanga", "quesadilla", "quesadillas",
            "taco", "tacos", "taqueria", "cantina", "birria", "street taco", "street tacos",
            "nachos", "tamale", "enchilada",
            "carne asada burrito", "california burrito", "mission burrito",
            "fish taco", "al pastor taco", "barbacoa taco", "taco plate", "taco bar",
            "chipotle burrito", "qdoba burrito", "moes burrito", "taco bell burrito", "taco bell crunchwrap",
        ]),
        Rule(token: .asset(name: "FoodIconIceCreamSandwich", fallback: "snowflake"), keywords: [
            "ice cream sandwich", "ice cream sandwiches", "mini vanilla ice cream", "ice cream cookie",
        ]),
        Rule(token: .asset(name: "FoodIconCookie", fallback: "birthday.cake.fill"), keywords: [
            "cookies and cream", "cookie thins", "sandwich cookie", "famous amos",
            "oreo", "fig newton",
            "drizzilicious", "drizzilicious cookies and cream", "cookies and cream drizzilicious",
            "drizzilicious cookie thins", "drizzilicious snack",
        ]),
        Rule(token: .asset(name: "FoodIconChicken", fallback: "flame.fill"), keywords: [
            "lightly breaded chicken breast strips", "chicken breast strips", "breast strips",
            "chicken strips", "chicken strip", "chicken tender", "chicken tenders", "chicken finger",
            "popcorn chicken", "chicken nuggets", "chicken nugget", "breaded chicken", "fried chicken",
            "chicken wing", "buffalo wing", "cutlet", "katsu", "schnitzel", "tonkatsu",
            "sweet chili chicken", "orange chicken", "sesame chicken", "general tso", "teriyaki chicken",
            "rotisserie chicken", "roasted chicken", "chicken plate", "chicken bowl",
            "chicken sandwich", "spicy chicken sandwich", "grilled chicken sandwich", "crispy chicken sandwich",
            "boneless wings", "nashville hot chicken", "chicken parmesan",
            "chick fil a nuggets", "mcnuggets", "kfc fried chicken", "popeyes chicken", "raising canes chicken",
        ]),
        Rule(token: .asset(name: "FoodIconPork", fallback: "fork.knife"), keywords: [
            "pork loin", "pork chop", "pork tenderloin", "pulled pork", "pork roast", "pork belly", "pork shoulder",
            "pork ribs", "pork steak", "pork carnitas", "porchetta", "porketta", "pork tender",
            "baby back", "spare ribs", "carnitas", "al pastor",
            "roast pork", "smoked pork", "ground pork", "pulled pork sandwich", "pork and",
            "pork",
        ]),
        Rule(token: .asset(name: "FoodIconRiceBowl", fallback: "bowl.fill"), keywords: [
            "seasoned rice pilaf", "rice pilaf", "seasoned rice", "fried rice", "yangzhou", "kimchi fried",
            "chahan", "chaufan", "rice bowl", "dirty rice", "yellow rice", "spanish rice", "cilantro lime rice",
            "bibimbap", "donburi", "gyudon", "oyakodon", "katsudon", "jasmine rice", "basmati rice",
            "rice cake", "rice cakes", "rice crisp", "rice crisps", "puffed rice", "rice thin", "rice thins",
            "lundberg rice", "quaker rice crisps", "caramel rice crisps",
            "chipotle bowl", "chipotle burrito bowl", "qdoba bowl", "moes bowl", "cava bowl", "sweetgreen bowl",
            "teriyaki chicken rice bowl", "beef rice bowl", "poke rice bowl",
        ]),
        Rule(token: .asset(name: "FoodIconPizza", fallback: "takeoutbag.and.cup.and.straw"), keywords: [
            "cheese flatbread", "flatbread pizza", "pizza", "calzone", "stromboli", "flatbread", "margherita",
            "pepperoni pizza", "cheese pizza", "supreme pizza", "veggie pizza", "deep dish pizza",
            "detroit style pizza", "sicilian pizza", "stuffed crust pizza", "pizza by the slice",
            "dominos pizza", "pizza hut pizza", "papa johns pizza", "little caesars pizza", "mod pizza",
        ]),
        Rule(token: .asset(name: "FoodIconBurger", fallback: "takeoutbag.and.cup.and.straw"), keywords: [
            "burger", "cheeseburger", "sliders", "whopper", "big mac", "impossible burger",
            "all american grill", "all-american grill", "american grill",
            "double cheeseburger", "bacon cheeseburger", "smash burger", "hamburger slider", "patty melt",
            "quarter pounder", "daves single", "baconator", "double double", "butterburger", "shackburger",
            "five guys burger", "shake shack burger", "whataburger",
        ]),
        Rule(token: .asset(name: "FoodIconSushi", fallback: "fish.fill"), keywords: [
            "sushi", "sashimi", "maki", "nigiri",
            "seaweed", "seaweed snack", "roasted seaweed", "seaweed sheet", "seaweed sheets",
            "nori", "nori snack", "kelp snack", "wakame", "sea vegetable", "sesame seaweed", "ginger sesame",
        ]),
        Rule(token: .asset(name: "FoodIconSalad", fallback: "leaf.fill"), keywords: [
            "salad", "salad bar", "caesar", "cobb salad", "greek salad", "garden salad", "spring mix",
            "kale salad", "southwest salad", "chopped salad", "spinach salad", "chef salad", "taco salad",
            "grain salad", "quinoa salad", "caesar salad with chicken",
        ]),
        Rule(token: .asset(name: "FoodIconCoffee", fallback: "cup.and.saucer.fill"), keywords: [
            "coffee", "espresso", "latte", "cappuccino", "americano", "macchiato",
            "mocha", "frappuccino", "cold brew", "cortado", "flat white", "ristretto", "lungo",
            "starbucks", "dunkin", "peets", "dutch bros",
            "nitro cold brew", "iced latte", "caramel macchiato", "starbucks latte", "dunkin coffee",
        ]),
        Rule(token: .asset(name: "FoodIconIceCream", fallback: "birthday.cake.fill"), keywords: [
            "gelato", "sundae", "soft serve", "milkshake", "malt",
            "ice cream cone", "ice cream", "icecream",
            "caramel ice cream", "caramel pretzel",
        ]),
        Rule(token: .asset(name: "FoodIconSandwich", fallback: "takeoutbag.and.cup.and.straw"), keywords: [
            "sandwich", "blt", "panini", "reuben", "hoagie", "submarine", "grinder", "po boy",
            "turkey sandwich", "ham and swiss", "club sandwich", "philly cheesesteak", "french dip", "tuna melt",
            "chicken salad sandwich", "sub sandwich", "subway footlong", "jersey mikes sub",
            "jimmy johns sandwich", "firehouse sub", "potbelly sandwich", "panera sandwich",
        ]),
        Rule(token: .asset(name: "FoodIconDonut", fallback: "birthday.cake.fill"), keywords: [
            "donut", "doughnut", "cronut",
        ]),
        Rule(token: .asset(name: "FoodIconFries", fallback: "takeoutbag.and.cup.and.straw"), keywords: [
            "french fries", "fries", "tater tot", "poutine",
            "potato bar", "baked potato bar", "ultimate potato bar", "loaded potato bar", "spud bar",
            "baked potato", "loaded baked potato", "potato station", "potato toppings bar",
            "hash browns", "home fries", "waffle fries", "curly fries", "steak fries", "sweet potato fries",
            "cheese fries", "chili cheese fries", "potato wedges",
        ]),
        Rule(token: .asset(name: "FoodIconPopcorn", fallback: "bag.fill"), keywords: [
            "popcorn", "movie popcorn", "buttered popcorn", "kettle corn", "caramel corn",
            "smartfood popcorn", "smartfood", "smart pop", "skinny pop", "boom chicka pop",
            "popcorners", "pop corners",
            "pirates booty", "veggie straws", "hippeas", "bare snacks",
            "rice chip", "rice chips", "corn chip", "corn chips", "tortilla chip", "tortilla chips",
            "potato chip", "potato chips", "kettle chip", "kettle chips",
            "good thins", "wheat thins", "snack thins", "cracker thins", "rice cracker", "rice crackers",
        ]),
        Rule(token: .asset(name: "FoodIconPasta", fallback: "takeoutbag.and.cup.and.straw"), keywords: [
            "spaghetti", "penne", "fusilli", "fettuccine", "linguine", "rigatoni", "ravioli",
            "tortellini", "gnocchi", "lasagna", "lasagne", "macaroni", "mac and cheese", "pasta",
            "spaghetti with meat sauce", "spaghetti and meat sauce", "meat sauce spaghetti",
            "alfredo pasta", "pasta alfredo", "bolognese", "spaghetti marinara", "cavatappi mac",
        ]),
        Rule(token: .asset(name: "FoodIconRamen", fallback: "mug.fill"), keywords: [
            "ramen", "pho", "udon", "lo mein", "pad thai", "chow mein", "yakisoba", "soba", "laksa",
            "dan dan", "dan dan mian", "drunken noodle", "pad see ew", "noodle bowl", "noodle soup",
            "ramen bowl", "pho noodle soup", "beef ramen", "chicken ramen",
        ]),
        Rule(token: .asset(name: "FoodIconWrap", fallback: "takeoutbag.and.cup.and.straw"), keywords: [
            "wrap", "gyro", "shawarma", "falafel", "kebab", "kabob",
            "chicken caesar wrap", "buffalo chicken wrap", "turkey wrap", "veggie wrap", "hummus wrap",
            "shawarma wrap", "falafel wrap", "lettuce wrap", "spinach wrap",
        ]),
        Rule(token: .asset(name: "FoodIconBread", fallback: "bag.fill"), keywords: [
            "bagel", "baguette", "brioche", "croissant", "sourdough", "ciabatta", "focaccia",
            "english muffin", "scone",
        ]),
        Rule(token: .asset(name: "FoodIconProtein", fallback: "figure.strengthtraining.traditional"), keywords: [
            "protein bar peanut butter", "protein bar chocolate", "protein bar",
            "protein shake", "protein powder", "whey", "casein", "mass gainer",
            "granola bar", "energy bar", "breakfast bar", "nutrition bar",
            "snack bar", "fig bar", "larabar", "clif bar", "rxbar", "quest bar",
            "meal replacement", "bcaa", "eaa", "creatine",
            "fairlife protein shake", "premier protein", "muscle milk", "core power",
            "ensure max protein", "boost high protein", "one bar", "barebells", "pure protein bar", "kind protein bar",
        ]),
        // Lucide Lab (ISC) additions for food categories not covered in the core set.
        Rule(token: .asset(name: "FoodIconBarbecue", fallback: "fork.knife"), keywords: [
            "barbecue", "bbq", "bbq platter", "barbecue platter", "smoker plate", "smoked meats platter",
        ]),
        Rule(token: .asset(name: "FoodIconBacon", fallback: "fork.knife"), keywords: [
            "bacon", "turkey bacon", "candied bacon", "bacon strips", "crispy bacon",
        ]),
        Rule(token: .asset(name: "FoodIconSausage", fallback: "fork.knife"), keywords: [
            "sausage", "breakfast sausage", "italian sausage", "chicken sausage", "andouille", "kielbasa",
            "hot dog", "hot dogs", "hotdog", "corn dog", "corndog", "frankfurter", "franks", "coney", "coneys", "coney dog",
            "bratwurst", "brat", "brats", "sausage link", "breakfast links", "smoked sausage", "polish sausage",
            "all beef hot dog", "ballpark hot dog", "footlong hot dog", "chili dog", "chicago dog", "new york dog",
            "johnsonville brat", "costco hot dog",
        ]),
        Rule(token: .asset(name: "FoodIconKebab", fallback: "fork.knife"), keywords: [
            "kebab", "kabob", "skewer", "meat skewer", "chicken skewer", "beef skewer",
        ]),
        Rule(token: .asset(name: "FoodIconCheese", fallback: "fork.knife"), keywords: [
            "cheese plate", "cheese board", "cheddar", "mozzarella", "gouda", "brie", "parmesan",
        ]),
        Rule(token: .asset(name: "FoodIconAvocado", fallback: "leaf.fill"), keywords: [
            "avocado", "avocados", "guacamole", "avocado toast", "avocado spread",
        ]),
        Rule(token: .asset(name: "FoodIconCoconut", fallback: "leaf.fill"), keywords: [
            "coconut", "coconuts", "coconut flakes", "coconut chips", "coconut water",
        ]),
        Rule(token: .asset(name: "FoodIconLemon", fallback: "leaf.fill"), keywords: [
            "lemon", "lemons", "lemon wedge", "lemon slices", "lemon zest",
        ]),
        Rule(token: .asset(name: "FoodIconOlive", fallback: "leaf.fill"), keywords: [
            "olive", "olives", "green olives", "kalamata olives", "olive tapenade",
        ]),
        Rule(token: .asset(name: "FoodIconOnion", fallback: "leaf.fill"), keywords: [
            "onion", "onions", "red onion", "yellow onion", "caramelized onion", "pickled onion",
        ]),
        Rule(token: .asset(name: "FoodIconPineapple", fallback: "leaf.fill"), keywords: [
            "pineapple", "pineapples", "pineapple ring", "pineapple chunks", "grilled pineapple",
        ]),
        Rule(token: .asset(name: "FoodIconFruit", fallback: "leaf.fill"), keywords: [
            "fruit cup", "fruit bowl", "mixed fruit", "seasonal fruit", "fruit medley",
        ]),
        Rule(token: .asset(name: "FoodIconPancakes", fallback: "birthday.cake.fill"), keywords: [
            "pancakes", "pancake stack", "buttermilk pancakes", "silver dollar pancakes", "hotcakes",
            "waffle", "waffles", "waffle bar",
            "french toast", "crepes", "breakfast platter",
        ]),
        Rule(token: .asset(name: "FoodIconPie", fallback: "birthday.cake.fill"), keywords: [
            "pie", "apple pie", "pumpkin pie", "pecan pie", "cherry pie", "key lime pie",
        ]),
        Rule(token: .asset(name: "FoodIconChiliPepper", fallback: "flame.fill"), keywords: [
            "chili pepper", "chile pepper", "jalapeño", "jalapeno", "serrano pepper", "habanero", "ghost pepper",
        ]),
        Rule(token: .asset(name: "FoodIconBowlChopsticks", fallback: "bowl.fill"), keywords: [
            "rice bowl with chopsticks", "noodle bowl with chopsticks", "poke bowl", "donburi bowl", "asian bowl",
        ]),
        Rule(token: .asset(name: "FoodIconCupToGo", fallback: "cup.and.saucer.fill"), keywords: [
            "coffee to go", "to go coffee", "takeout coffee", "iced coffee cup", "paper cup coffee",
        ]),
        Rule(token: .asset(name: "FoodIconMugTeabag", fallback: "cup.and.saucer.fill"), keywords: [
            "tea", "hot tea", "black tea", "green tea", "herbal tea", "chai tea", "tea bag",
        ]),
        Rule(token: .asset(name: "FoodIconCoffeeBean", fallback: "cup.and.saucer.fill"), keywords: [
            "coffee beans", "espresso beans", "whole bean coffee", "ground coffee", "roasted coffee beans",
        ]),
        Rule(token: .asset(name: "FoodIconCoffeeMaker", fallback: "cup.and.saucer.fill"), keywords: [
            "brew coffee", "fresh brewed coffee", "drip coffee", "coffee station", "coffee urn",
        ]),
        Rule(token: .asset(name: "FoodIconMealBox", fallback: "takeoutbag.and.cup.and.straw"), keywords: [
            "meal box", "bento", "bento box", "boxed meal", "takeout box", "lunch box",
        ]),
        Rule(token: .asset(name: "FoodIconEgg", fallback: "frying.pan.fill"), keywords: [
            "egg", "eggs", "omelet", "omelets", "omelette", "omelettes", "cheese omelet", "cheese omelette",
            "scrambled eggs", "egg scramble", "breakfast casserole", "farmers breakfast casserole", "farmer breakfast casserole",
            "breakfast eggs", "egg station", "omelet station",
            "egg white scramble", "egg white omelet", "western omelet", "denver omelet", "veggie omelet",
            "ham and cheese omelet", "country breakfast skillet", "egg bake", "sausage egg casserole", "bacon egg casserole",
            "frittata", "quiche", "shakshuka", "breakfast bowl eggs",
        ]),
        Rule(token: .asset(name: "FoodIconEggCup", fallback: "frying.pan.fill"), keywords: [
            "boiled egg", "soft boiled egg", "hard boiled egg", "egg cup", "jammy egg",
        ]),
        // Lucide (ISC) stroke icons — template assets for foods not covered above.
        Rule(token: .asset(name: "FoodIconCandyCane", fallback: "birthday.cake.fill"), keywords: [
            "candy cane", "candy canes", "peppermint stick",
        ]),
        Rule(token: .asset(name: "FoodIconPopsicle", fallback: "snowflake"), keywords: [
            "popsicle", "popsicles", "ice pop", "ice pops", "fudgsicle", "otter pop", "freezer pop",
            "fudge pop", "fudge pops", "creamsicle", "creamsicles", "dreamsicle", "ice cream bar", "ice cream bars",
        ]),
        Rule(token: .asset(name: "FoodIconCakeSlice", fallback: "birthday.cake.fill"), keywords: [
            "cake slice", "slice of cake", "sheet cake", "layer cake", "bundt cake", "pound cake", "sponge cake",
            "chiffon cake", "angel food", "coffee cake", "crumb cake",
        ]),
        Rule(token: .asset(name: "FoodIconCake", fallback: "birthday.cake.fill"), keywords: [
            "cake", "cupcake", "cupcakes", "birthday cake", "wedding cake", "cheesecake slice", "cheesecake",
        ]),
        Rule(token: .asset(name: "FoodIconLollipop", fallback: "birthday.cake.fill"), keywords: [
            "lollipop", "lollipops", "sucker", "tootsie pop", "dum dum",
        ]),
        Rule(token: .asset(name: "FoodIconCandy", fallback: "birthday.cake.fill"), keywords: [
            "hard candy", "jolly rancher", "life savers", "lifesavers", "skittles", "jawbreaker",
        ]),
        Rule(token: .asset(name: "FoodIconApple", fallback: "leaf.fill"), keywords: [
            "apple", "apples", "applesauce", "apple pie", "apple crisp", "apple butter", "cider",
            "fresh fruit",
        ]),
        Rule(token: .asset(name: "FoodIconBanana", fallback: "leaf.fill"), keywords: [
            "banana", "bananas", "banana bread", "plantain", "plantains",
        ]),
        Rule(token: .asset(name: "FoodIconGrape", fallback: "leaf.fill"), keywords: [
            "grape", "grapes", "raisin", "raisins", "wine grape",
        ]),
        Rule(token: .asset(name: "FoodIconCherry", fallback: "birthday.cake.fill"), keywords: [
            "cherry", "cherries", "maraschino",
        ]),
        Rule(token: .asset(name: "FoodIconCitrus", fallback: "leaf.fill"), keywords: [
            "grapefruit", "clementine", "clementines", "mandarin", "tangerine", "tangerines",
            "lime", "limes", "key lime", "pomelo", "kumquat", "yuzu",
        ]),
        Rule(token: .asset(name: "FoodIconCarrot", fallback: "carrot.fill"), keywords: [
            "carrot", "carrots", "baby carrots", "carrot cake",
        ]),
        Rule(token: .asset(name: "FoodIconBean", fallback: "leaf.fill"), keywords: [
            "black bean", "black beans", "kidney bean", "kidney beans", "pinto bean", "pinto beans",
            "navy bean", "cannellini", "garbanzo", "chickpea", "chickpeas", "baked beans",
            "refried beans", "bean dip", "lima bean", "lima beans", "fava bean", "edamame bowl",
        ]),
        Rule(token: .asset(name: "FoodIconWheat", fallback: "leaf.fill"), keywords: [
            "wheat", "wheat bread", "bulgur", "farro", "freekeh", "semolina", "durum", "seitan",
            "cereal", "cereal bar", "granola cereal",
        ]),
        Rule(token: .asset(name: "FoodIconVegan", fallback: "leaf.fill"), keywords: [
            "vegan", "plant based meat", "plant-based meat", "beyond meat", "impossible meat",
        ]),
        Rule(token: .asset(name: "FoodIconHam", fallback: "fork.knife"), keywords: [
            "ham", "spiral ham", "glazed ham", "ham steak", "country ham", "black forest ham", "honey ham",
            "prosciutto", "serrano ham", "jamón", "jamon",
        ]),
        Rule(token: .asset(name: "FoodIconShrimp", fallback: "fish.fill"), keywords: [
            "shrimp", "prawn", "prawns", "scampi", "cocktail shrimp",
        ]),
        Rule(token: .asset(name: "FoodIconSnail", fallback: "fish.fill"), keywords: [
            "escargot", "snail", "snails",
        ]),
        Rule(token: .asset(name: "FoodIconFish", fallback: "fish.fill"), keywords: [
            "fish", "fish fillet", "fish stick", "fish sticks", "fried fish", "cod", "tilapia", "halibut",
            "trout", "mackerel", "swordfish", "branzino", "sea bass", "walleye", "perch", "pollock",
            "salmon", "tuna", "ahi", "yellowfin", "albacore",
        ]),
        Rule(token: .asset(name: "FoodIconSoup", fallback: "mug.fill"), keywords: [
            "soup", "bisque", "chowder", "gazpacho", "borscht", "pho bowl",
            "tomato soup", "chicken noodle soup", "broccoli cheddar soup", "panera soup",
        ]),
        Rule(token: .asset(name: "FoodIconCookingPot", fallback: "mug.fill"), keywords: [
            "stew", "braised", "pot roast", "slow cooker", "crockpot", "crock pot", "dutch oven",
            "one pot", "hot pot", "shabu", "fondue", "goulash", "ragu", "ragù",
            "biscuits and gravy", "biscuits gravy", "biscuit and gravy",
        ]),
        Rule(token: .asset(name: "FoodIconEggFried", fallback: "frying.pan.fill"), keywords: [
            "fried egg", "fried eggs", "sunny side", "over easy", "over medium", "over hard",
        ]),
        Rule(token: .asset(name: "FoodIconMicrowave", fallback: "shippingbox.fill"), keywords: [
            "microwave meal", "microwave dinner", "heat and eat", "steamable",
        ]),
        Rule(token: .asset(name: "FoodIconRefrigerator", fallback: "shippingbox.fill"), keywords: [
            "meal prep", "prepped meals", "leftovers container",
        ]),
        Rule(token: .asset(name: "FoodIconShoppingBasket", fallback: "shippingbox.fill"), keywords: [
            "groceries", "grocery haul", "farmers market", "produce haul",
        ]),
        Rule(token: .asset(name: "FoodIconChefHat", fallback: "fork.knife"), keywords: [
            "chef special", "chef salad", "tasting menu", "catered",
        ]),
        Rule(token: .asset(name: "FoodIconUtensilsCrossed", fallback: "fork.knife"), keywords: [
            "silverware", "cutlery", "knife and fork",
        ]),
        Rule(token: .asset(name: "FoodIconUtensils", fallback: "fork.knife"), keywords: [
            "fork and spoon", "spork",
        ]),
        Rule(token: .asset(name: "FoodIconGlassWater", fallback: "drop.fill"), keywords: [
            "water bottle", "still water", "mineral water", "sparkling water", "seltzer water", "club soda",
        ]),
        Rule(token: .asset(name: "FoodIconCupSoda", fallback: "drop.fill"), keywords: [
            "soda", "soft drink", "cola", "pop", "sprite", "fanta", "mountain dew", "pepsi", "coca cola",
            "coke", "dr pepper", "root beer", "ginger ale", "cream soda",
            "beverage", "beverage option", "beverage station", "drink station",
            "fountain drink", "fountain soda", "slush", "slurpee", "fast food drink",
        ]),
        Rule(token: .asset(name: "FoodIconMilk", fallback: "drop.fill"), keywords: [
            "almond milk", "oat milk", "soy milk", "coconut milk", "cashew milk", "rice milk", "lactose free milk",
            "milk", "chocolate milk", "strawberry milk", "whole milk", "skim milk", "2 percent milk",
            "buttermilk", "half and half", "heavy cream", "whipping cream",
            "yogurt", "yoghurt", "greek yogurt", "greek yoghurt", "skyr",
            "vanilla yogurt", "strawberry yogurt", "blueberry yogurt", "plain yogurt",
            "yogurt cup", "yogurt parfait", "drinkable yogurt", "probiotic yogurt",
            "salted caramel yogurt", "remix yogurt",
        ]),
        Rule(token: .asset(name: "FoodIconNut", fallback: "leaf.fill"), keywords: [
            "almond", "almonds", "walnut", "walnuts", "pecan", "pecans", "cashew", "cashews",
            "pistachio", "pistachios", "macadamia", "hazelnut", "hazelnuts", "mixed nuts", "trail mix",
        ]),
        Rule(token: .asset(name: "FoodIconBeer", fallback: "wineglass.fill"), keywords: [
            "beer", "ipa", "lager", "stout", "porter", "pilsner", "ale", "draft beer", "craft beer",
        ]),
        Rule(token: .asset(name: "FoodIconWine", fallback: "wineglass.fill"), keywords: [
            "wine", "red wine", "white wine", "rosé", "rose wine", "chardonnay", "cabernet", "merlot",
            "pinot", "riesling", "sauvignon", "malbec", "shiraz",
        ]),
        Rule(token: .asset(name: "FoodIconBottleWine", fallback: "wineglass.fill"), keywords: [
            "bottle of wine", "wine bottle",
        ]),
        Rule(token: .asset(name: "FoodIconMartini", fallback: "wineglass.fill"), keywords: [
            "martini", "cosmopolitan", "manhattan", "negroni", "daiquiri", "margarita", "mojito", "old fashioned",
        ]),
    ]

    private static let sfSymbolRules: [Rule] = [
        Rule(token: .sf("snowflake"), keywords: [
            "ice cream sandwich", "ice cream sandwiches", "ice cream sammie", "its it",
            "frozen sandwich", "novelty ice cream", "klondike bar", "fat boy",
        ]),
        Rule(token: .sf("popcorn.fill"), keywords: [
            "drizzilicious",
            "pirates booty", "veggie straws", "hippeas", "bare snacks",
            "rice chip", "rice chips", "corn chip", "tortilla chip", "potato chip", "kettle chip",
            "good thins", "wheat thins", "snack thins", "cracker thins", "rice cracker", "rice crackers",
        ]),
        // Frozen treats / soft serve are covered by `FoodIconIceCream` / `FoodIconPopsicle` / `snowflake` assets — do not duplicate here or their scores stack and beat the template icons.
        Rule(token: .sf("birthday.cake.fill"), keywords: [
            "carrot cake", "cheesecake", "red velvet", "brownie", "blondie",
            "cupcake", "blueberry muffin", "corn muffin", "chocolate muffin", "bran muffin", "donut", "doughnut", "cronut", "eclair", "macaron", "macaroon",
            "strawberry shortcake",
            "cookie", "cookies", "cookies and cream", "oreo", "fig newton",
            "candy", "gummy", "licorice", "chocolate bar", "truffle", "fudge",
            "dessert", "pastry", "tiramisu", "pudding", "flan", "custard",
            "pie", "cobbler", "crumble", "crisp", "turnover", "strudel",
            "parfait", "banana split", "whipped cream", "frosting",
            "little bites", "hostess", "twinkie", "ding dong",
            "rice krispie", "rice crispy", "marshmallow", "smores", "s mores",
            "honey bun", "cinnamon roll", "sticky bun", "danish", "bear claw",
        ]),
        Rule(token: .sf("fork.knife"), keywords: [
            "beef ribs", "short rib", "prime rib", "brisket", "pot roast",
            "rack of lamb", "lamb chop", "veal chop", "turkey breast", "turkey leg", "roast turkey",
            "chicken breast", "chicken thigh", "chicken wing", "chicken drumstick", "chicken leg", "rotisserie chicken",
            "steak", "filet mignon", "sirloin", "ribeye", "flank steak", "skirt steak", "meatloaf", "meatballs",
            "charcuterie", "deli meat", "lunch meat", "cold cut", "kebab", "kofta",
            "chicken", "turkey", "duck", "goose", "quail", "poultry", "hen", "cornish hen",
            "rotisserie", "drumstick", "thigh", "leg quarter",
            "beef", "bacon", "ham", "prosciutto", "pancetta", "sausage", "chorizo", "andouille",
            "lamb", "veal", "venison", "bison", "elk",
            "bratwurst", "hotdog", "hot dog", "frank", "kielbasa", "salami", "pepperoni",
            "kabob", "kabab",
        ]),
        Rule(token: .sf("flame.fill"), keywords: [
            "lightly breaded", "breaded", "deep fried", "deep-fried", "air fried", "air-fried",
            "fried chicken", "chicken fried", "chicken strip", "chicken strips", "chicken tender", "chicken tenders",
            "breast strips", "chicken breast strips", "chicken finger", "hot wing", "buffalo wing",
            "nugget", "nuggets", "popcorn chicken", "katsu", "cutlet", "schnitzel",
            "crispy", "crunchy", "tempura", "karaage", "kara-age", "tonkatsu",
            "bbq ribs", "bbq chicken", "bbq pork", "bbq beef", "bbq plate", "korean bbq",
            "barbecue ribs", "barbecue chicken",
            "grilled chicken", "grilled shrimp", "grilled fish", "grilled salmon", "grilled steak",
            "grilled cheese", "grilled vegetables", "grilled corn", "grilled onion",
            "smoked brisket", "smoked ribs", "smoked chicken", "smoked sausage",
            "blackened chicken", "blackened fish", "blackened salmon",
            "seared tuna", "seared scallop",
            "spicy", "buffalo", "jerk", "sriracha", "habanero",
            "jalapeno", "jalapeño", "ghost pepper", "chili pepper", "hot sauce",
            "cajun", "tandoori", "gochujang",
        ]),
        Rule(token: .sf("mug.fill"), keywords: [
            "chili con carne", "turkey chili", "beef chili", "vegetarian chili", "veggie chili",
            "chili bowl", "chili mac", "gumbo", "jambalaya", "étouffée", "etouffee",
            "curry", "curry bowl", "curry rice", "dal", "daal", "dahl", "lentil soup",
            "minestrone", "miso soup", "tom yum", "wonton soup", "matzo ball", "chowder", "bisque", "gazpacho",
            "tea", "chai", "matcha", "hot chocolate", "cocoa",
            "soup", "broth", "stock", "bouillon", "stew", "braised",
        ]),
        Rule(token: .sf("fish.fill"), keywords: [
            "poke bowl", "ceviche",
            "salmon", "tuna", "trout", "cod", "halibut", "mackerel", "tilapia",
            "swordfish", "anchovy", "sardine", "sea bass", "branzino", "seafood", "fish",
            "fish stick", "fish fillet", "fish taco",
            "shrimp", "prawn", "crab", "lobster", "oyster", "clam", "mussel",
            "scallop", "calamari", "squid", "octopus", "crawfish", "crayfish",
            "poke",
        ]),
        Rule(token: .sf("bowl.fill"), keywords: [
            "fried rice", "yangzhou", "kimchi fried", "chahan", "chaufan",
            "rice pilaf", "rice bowl", "seasoned rice", "wild rice", "jasmine rice", "brown rice", "white rice",
            "biryani", "jollof", "paella", "risotto", "congee", "jook",
            "couscous", "quinoa", "farro", "barley", "bulgur", "millet",
            "rice", "pilaf",
            "oatmeal", "porridge", "oat", "grits", "polenta",
            "bibimbap", "donburi", "gyudon", "oyakodon", "katsudon",
            "buddha bowl", "grain bowl", "power bowl",
        ]),
        Rule(token: .sf("takeoutbag.and.cup.and.straw"), keywords: [
            "stir fry", "stir-fry", "pad kee mao",
            "fried noodle", "teriyaki bowl", "hibachi",
            "pizza", "calzone", "stromboli", "flatbread",
            "burger", "cheeseburger", "sliders", "fries", "french fries", "tater tot", "poutine",
            "taco", "tacos", "burrito", "burritos", "quesadilla", "quesadillas", "nachos", "enchilada", "tamale", "empanada",
            "sandwich", "submarine", "hoagie", "grinder", "po boy", "reuben", "blt", "panini",
            "wrap", "gyro", "kebab", "shawarma", "falafel",
            "egg roll", "spring roll", "summer roll", "lumpia",
            "fast food", "takeout", "take-out", "delivery", "doordash", "uber eats", "grubhub",
            "mcdonalds", "wendys", "burger king", "kfc", "subway", "chipotle", "taco bell",
            "five guys", "shake shack", "popeyes", "chick-fil-a", "chick fil a", "in-n-out",
            "dairy queen", "sonic", "panda express", "wingstop", "dominos", "papa johns",
            "little caesars", "whataburger", "culvers", "arbys", "arby s",
            "hot dog", "corn dog", "cornbread", "nashville chicken", "mozzarella sticks", "onion rings",
            "jalapeno poppers", "jalapeño poppers", "loaded fries",
            "chow mein", "lo mein", "pad thai", "pad see ew",
            "drunken noodle", "yakisoba", "dan dan", "dan dan mian",
            "fried noodle", "noodle bowl", "pasta", "spaghetti", "penne", "fusilli", "fettuccine", "linguine", "rigatoni",
            "mac and cheese", "macaroni", "lasagna", "lasagne", "ravioli", "tortellini", "gnocchi",
        ]),
        Rule(token: .sf("shippingbox.fill"), keywords: [
            "peanut butter", "almond butter", "sunflower butter", "nutella", "nut butter",
            "jam", "jelly", "preserves", "marmalade", "hummus", "guacamole", "salsa jar",
            "packaged", "microwave meal", "tv dinner", "frozen box", "frozen entree",
            "instant noodle", "instant ramen", "cup noodle", "maruchan", "top ramen",
            "canned", "can of", "costco", "kirkland", "trader joe", "whole foods", "great value",
        ]),
        Rule(token: .sf("drop.fill"), keywords: [
            "water", "sparkling water", "seltzer", "club soda", "tonic",
            "juice", "orange juice", "apple juice", "cranberry juice", "grape juice",
            "smoothie", "meal shake", "ensure", "boost",
            "milk", "chocolate milk", "strawberry milk", "almond milk", "oat milk", "soy milk",
            "coconut milk", "cashew milk", "half and half", "creamer",
            "lemonade", "limeade", "iced tea", "sweet tea",
            "soda", "pop", "cola", "sprite", "ginger ale", "root beer", "dr pepper",
            "gatorade", "powerade", "bodyarmor", "electrolyte", "hydration",
            "kombucha", "bubble tea", "boba", "milk tea",
        ]),
        Rule(token: .sf("cup.and.saucer.fill"), keywords: [
            "coffee", "espresso", "latte", "cappuccino", "americano", "macchiato",
            "mocha", "frappuccino", "cold brew", "cortado", "flat white", "ristretto", "lungo",
            "starbucks", "dunkin", "peets", "dutch bros",
        ]),
        Rule(token: .sf("wineglass.fill"), keywords: [
            "wine", "champagne", "prosecco", "cocktail", "margarita", "martini",
            "mojito", "daiquiri", "manhattan", "negroni", "spritz", "sangria", "mimosa",
            "beer", "ale", "lager", "ipa", "stout", "porter", "pilsner", "cider", "hard seltzer",
            "whiskey", "whisky", "vodka", "rum", "tequila", "gin", "bourbon", "scotch", "liqueur",
        ]),
        Rule(token: .sf("bolt.fill"), keywords: [
            "energy drink", "red bull", "monster", "celsius", "bang", "rockstar", "nos",
            "preworkout", "pre-workout", "electrolyte powder",
        ]),
        Rule(token: .sf("leaf.fill"), keywords: [
            "salad", "caesar", "cobb", "greek salad", "garden salad", "spring mix",
            "lettuce", "spinach", "kale", "arugula", "rocket", "mesclun", "chard",
            "broccoli", "cauliflower", "brussels", "cabbage", "coleslaw", "bok choy",
            "green bean", "green beans", "string bean", "string beans", "haricot verts",
            "snap pea", "snap peas", "snow pea", "snow peas", "sugar snap",
            "asparagus", "zucchini", "yellow squash", "summer squash", "acorn squash",
            "butternut", "spaghetti squash", "eggplant", "aubergine", "okra", "artichoke",
            "leek", "leeks", "scallion", "scallions", "green onion", "shallot", "fennel",
            "celery", "green pepper", "bell pepper", "sweet pepper", "poblano", "anaheim", "pepperoncini",
            "snap bean", "wax bean", "lima bean", "lima beans", "black eyed peas", "field peas",
            "peas", "petit pois", "shelled peas", "snow pea shoots",
            "sweet corn", "corn on the cob", "elote", "creamed corn",
            "potato", "potatoes", "baked potato", "roasted potato",
            "fingerling", "russet", "yukon", "sweet potato", "yam", "yams",
            "mushroom", "mushrooms", "shiitake", "portobello", "cremini", "truffle",
            "vegan", "vegetarian", "veggie", "veggies", "vegetable", "vegetables", "greens", "slaw",
            "cucumber", "tomato", "cherry tomato", "avocado", "guac", "edamame", "sprout",
            "tofu", "tempeh", "seitan", "plant based", "plant-based",
            "apple", "banana", "orange", "grape", "berry", "berries", "strawberry", "blueberry",
            "raspberry", "blackberry", "mango", "pineapple", "melon", "watermelon", "cantaloupe",
            "peach", "pear", "plum", "cherry", "kiwi", "citrus", "fruit", "fruit cup",
        ]),
        Rule(token: .sf("carrot.fill"), keywords: [
            "carrot", "parsnip", "beet", "radish", "turnip", "rutabaga", "jicama",
        ]),
        Rule(token: .sf("bag.fill"), keywords: [
            "bread", "bagel", "baguette", "roll", "bun", "brioche", "hoagie roll",
            "focaccia", "pita", "naan", "chapati", "roti", "paratha", "tortilla", "arepa",
            "croissant", "biscuit", "scone", "english muffin",
            "cracker", "crackers", "ritz", "triscuit", "wheat thin", "pretzel", "breadstick",
            "quiche", "pot pie crust", "pie crust", "toast", "sourdough", "ciabatta", "loaf",
        ]),
        Rule(token: .sf("tray.full"), keywords: [
            "buffet", "platter", "combo plate", "combo", "bento", "tv tray", "potluck", "catering",
            "casserole", "shepherds pie", "shepherd s pie", "cottage pie", "lasagna", "lasagne",
            "rice plate", "plate lunch", "meat and two", "soul food", "sheet pan", "sheet pan meal",
            "frozen meal", "frozen dinner", "family meal", "leftovers", "leftover",
            "stuffed pepper", "stuffed mushroom", "stuffed zucchini", "enchilada bake",
        ]),
        Rule(token: .sf("barcode.viewfinder"), keywords: [
            "barcode", "upc", "scan", "nutrition label",
        ]),
        Rule(token: .sf("sun.horizon.fill"), keywords: [
            "breakfast", "brunch", "pancake", "waffle", "waffles", "chicken and waffles", "french toast", "crepe", "blintz",
            "cereal", "cheerios", "special k", "granola", "muesli",
            "yogurt", "greek yogurt", "skyr", "parfait breakfast",
            "benedict",
            "hash brown", "home fries", "breakfast burrito", "breakfast sandwich",
        ]),
        Rule(token: .sf("frying.pan.fill"), keywords: [
            "egg", "eggs", "omelet", "omelette", "scramble", "scrambled eggs",
            "fried egg", "sunny side", "over easy", "over medium", "over hard",
            "frittata", "shakshuka", "huevos",
        ]),
        Rule(token: .sf("moon.stars.fill"), keywords: [
            "dinner", "supper", "late night", "midnight snack",
        ]),
    ]
}
