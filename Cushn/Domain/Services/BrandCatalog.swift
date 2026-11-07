import Foundation

/// One recognizable service. `key` is a stable identifier and `name` the canonical display name.
/// `qualifiers` are the words that can sit beside an alias without making it a different thing, such as "Sapphire"
/// for Chase. `icon` names bundled artwork (`brand-<icon>`). With no artwork, `symbol` names a neutral SF Symbol,
/// and with neither the row shows a letter.
struct Brand: Sendable {
    let key: String
    let name: String
    let category: SeedCategory
    let aliases: [String]
    let qualifiers: Set<String>
    let icon: String?
    let symbol: String?

    init(_ key: String, _ name: String, _ category: SeedCategory, _ aliases: [String], _ qualifiers: [String], _ icon: String?, _ symbol: String?) {
        self.key = key
        self.name = name
        self.category = category
        self.aliases = aliases
        self.qualifiers = Set(qualifiers)
        self.icon = icon
        self.symbol = symbol
    }
}

/// The curated list lives in `scripts/brand_icons/catalog.json` and is generated into `BrandCatalogData.swift`.
/// Sources and licenses for each icon are recorded in `design/BRAND_ASSETS_MANIFEST.md`.
enum BrandCatalog {}
