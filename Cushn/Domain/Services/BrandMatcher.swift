import Foundation

struct BrandMatch: Equatable, Sendable {
    let key: String
    let name: String
    let category: SeedCategory
    /// Bundled artwork for this brand, or nil when the row should use a neutral fallback.
    let icon: String?
    let symbol: String?
}

/// What a payment shows in its icon tile.
enum PaymentIconContent: Equatable, Sendable {
    case artwork(String)
    case symbol(String)
    case monogram(String)
}

/// Local name matching with no network or AI. A match suggests a section and selects a bundled icon, and
/// `correctedName` can fix how the brand is written as someone types. It isn't a financial classification.
///
/// A name matches when it contains an approved alias and every other word looks like a plan, card or note.
/// "Chase Sapphire" and "Netflix Premium" match. "Chase Bakery" and "Netflix Camera Repair" don't,
/// because a neutral fallback is better than the wrong company's logo.
enum BrandMatcher {
    /// Keyed by spelling with spaces and punctuation removed, so "T Mobile", "T-Mobile" and "tmobile" are one alias.
    /// Precomputed because rows match their names on every render.
    private static let aliases: [String: Brand] = BrandCatalog.all.reduce(into: [:]) { index, brand in
        for alias in brand.aliases { index[tokenize(alias).joined()] = brand }
    }
    private static let longestAlias = BrandCatalog.all.flatMap(\.aliases).map { tokenize($0).count }.max() ?? 1

    /// Common words that suggest a section but identify no brand.
    private static let categoryWords: [(SeedCategory, Set<String>)] = [
        (.housing, ["rent", "mortgage", "hoa"]),
        (.utilities, ["electric", "electricity", "water", "gas", "internet", "wifi", "phone", "trash", "garbage", "sewer", "sewage", "power"]),
        (.insurance, ["insurance"]),
        (.creditCards, ["card"]),
        (.subscriptions, ["subscription", "membership", "gym"]),
        (.investments, ["investment", "investments", "401k", "ira"]),
        (.transfers, ["transfer", "savings"]),
    ]

    /// Neutral symbols for everyday bills with no recognizable provider.
    private static let symbolWords: [String: String] = [
        "rent": "house", "mortgage": "house", "hoa": "house", "housing": "house",
        "electric": "bolt", "electricity": "bolt", "power": "bolt", "energy": "bolt",
        "water": "drop", "sewer": "water.waves", "sewage": "water.waves",
        "gas": "flame",
        "trash": "trash", "garbage": "trash", "waste": "trash", "recycling": "trash",
        "internet": "wifi", "wifi": "wifi", "broadband": "wifi",
        "phone": "phone", "cell": "phone",
        "insurance": "shield",
        "car": "car", "card": "creditcard", "loan": "banknote",
    ]

    static func match(_ name: String) -> BrandMatch? {
        let tokens = tokenize(name)
        guard !tokens.isEmpty else { return nil }

        // Longest alias first, then earliest in the name, so the result never depends on catalog order.
        for width in stride(from: min(longestAlias, tokens.count), through: 1, by: -1) {
            for start in 0...(tokens.count - width) {
                let end = start + width
                guard let brand = aliases[tokens[start..<end].joined()] else { continue }
                let others = tokens[..<start] + tokens[end...]
                if others.allSatisfy({ qualifies($0, for: brand) }) {
                    return BrandMatch(key: brand.key, name: brand.name, category: brand.category, icon: brand.icon, symbol: brand.symbol)
                }
            }
        }
        return nil
    }

    /// Writes a recognized brand the way the company does: "netflix" is "Netflix", "chatgpt" is "ChatGPT" and
    /// "tmobile bill" is "T-Mobile bill". Only the brand's own words change, and only when they're the brand's name
    /// in another spelling, so a short form like "Amex" stays. Anything unrecognized comes back as it was.
    static func correctedName(_ name: String) -> String {
        guard let brand = match(name) else { return name }
        let key = tokenize(brand.name).joined()
        let words = name.split(whereSeparator: \.isWhitespace).map(String.init)
        for start in words.indices {
            for end in start..<words.count where words[start...end].flatMap(tokenize).joined() == key {
                let corrected = (words[..<start] + [brand.name] + words[(end + 1)...]).joined(separator: " ")
                return name.last?.isWhitespace == true ? corrected + " " : corrected
            }
        }
        return name
    }

    static func suggestedCategory(for name: String) -> SeedCategory {
        if let brand = match(name) { return brand.category }
        let tokens = Set(tokenize(name))
        return categoryWords.first { !$0.1.isDisjoint(with: tokens) }?.0 ?? .other
    }

    /// Artwork when a brand has it, then a neutral symbol, then the name's first letter.
    static func iconContent(for name: String) -> PaymentIconContent {
        let brand = match(name)
        if let icon = brand?.icon { return .artwork(icon) }
        if let symbol = brand?.symbol ?? genericSymbol(for: name) { return .symbol(symbol) }
        let letter = name.trimmingCharacters(in: .whitespacesAndNewlines).first.map { String($0).uppercased() }
        return .monogram(letter ?? "•")
    }

    /// The last meaningful word decides, since English puts the thing last: "City Water" and "Water Bill"
    /// get a drop, while "Water Polo Dues" and "Power Yoga" stay on their letter.
    private static func genericSymbol(for name: String) -> String? {
        tokenize(name).last { !BrandCatalog.sharedQualifiers.contains($0) }.flatMap { symbolWords[$0] }
    }

    /// Bare numbers count, because people add a card's last four digits.
    private static func qualifies(_ token: String, for brand: Brand) -> Bool {
        BrandCatalog.sharedQualifiers.contains(token) || brand.qualifiers.contains(token) || token.allSatisfy(\.isNumber)
    }

    /// Lowercased, accent-free words. Apostrophes (straight or curly) and ampersands join; pluses become a word;
    /// other punctuation separates.
    private static func tokenize(_ text: String) -> [String] {
        text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "en_US"))
            .lowercased()
            .replacingOccurrences(of: "&", with: "")
            .replacingOccurrences(of: "'", with: "")
            .replacingOccurrences(of: "\u{2019}", with: "")
            .replacingOccurrences(of: "+", with: " plus")
            .split { !$0.isLetter && !$0.isNumber }
            .map(String.init)
    }
}
