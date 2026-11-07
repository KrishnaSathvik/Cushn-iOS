import Testing
import UIKit
@testable import Cushn

@Suite struct BrandMatcherTests {
    @Test func matchesAliasesRegardlessOfCaseAndPunctuation() {
        #expect(BrandMatcher.match("NETFLIX")?.key == "netflix")
        #expect(BrandMatcher.match("  netflix ")?.key == "netflix")
        #expect(BrandMatcher.match("AmEx")?.key == "amex")
        #expect(BrandMatcher.match("American Express")?.key == "amex")
        #expect(BrandMatcher.match("T-Mobile")?.key == "t-mobile")
        #expect(BrandMatcher.match("AT&T")?.key == "att")
    }
    @Test func matchesCommonVariations() {
        #expect(BrandMatcher.match("Chat GPT")?.key == "openai")
        #expect(BrandMatcher.match("ChatGPT Plus")?.key == "openai")
        #expect(BrandMatcher.match("OpenAI")?.key == "openai")
        #expect(BrandMatcher.match("Capital One Venture")?.key == "capital-one")
        #expect(BrandMatcher.match("CapitalOne")?.key == "capital-one")
        #expect(BrandMatcher.match("Citi Double Cash")?.key == "citi")
        #expect(BrandMatcher.match("Adobe Creative Cloud")?.key == "adobe")
        #expect(BrandMatcher.match("Disney+")?.key == "disney-plus")
        #expect(BrandMatcher.match("Nétflix")?.key == "netflix")
    }
    @Test func plansAndNotesKeepTheMatch() {
        #expect(BrandMatcher.match("Netflix Premium")?.key == "netflix")
        #expect(BrandMatcher.match("Amex Platinum")?.key == "amex")
        #expect(BrandMatcher.match("Family Spotify plan")?.key == "spotify")
        #expect(BrandMatcher.match("My Robinhood Gold")?.key == "robinhood")
        #expect(BrandMatcher.match("Chase 4521")?.key == "chase")
        #expect(BrandMatcher.match("Verizon Fios Internet")?.key == "verizon")
    }
    /// The owner's M5.5 table, row for row.
    @Test func theOwnersExamplesMatch() {
        let expected = [
            "Chat GPT": "openai", "ChatGPT Plus": "openai", "Claude Pro": "claude", "Cursor Pro+": "cursor",
            "Netflix Premium": "netflix", "Amex Gold": "amex", "Amazon Prime": "amazon",
            "Google Drive Storage": "google-drive", "Spotify Premium": "spotify", "T Mobile": "t-mobile",
            "Adobe Creative Cloud": "adobe", "Apple Card": "apple-card",
        ]
        for (name, key) in expected {
            #expect(BrandMatcher.match(name)?.key == key, "\(name)")
        }
    }
    @Test func spacingAndPunctuationAreOneAlias() {
        for name in ["T-Mobile", "T Mobile", "tmobile", "TMOBILE"] { #expect(BrandMatcher.match(name)?.key == "t-mobile") }
        for name in ["DoorDash", "Door Dash", "door-dash"] { #expect(BrandMatcher.match(name)?.key == "doordash") }
        #expect(BrandMatcher.match("Sam's Club")?.key == "sams-club")
        #expect(BrandMatcher.match("Sam\u{2019}s Club")?.key == "sams-club")
        #expect(BrandMatcher.match("U.S. Bank")?.key == "us-bank")
        #expect(BrandMatcher.match("Battle.net")?.key == "battle-net")
    }
    @Test func theMoreSpecificAliasWins() {
        #expect(BrandMatcher.match("Apple Card")?.key == "apple-card")
        #expect(BrandMatcher.match("Apple Music")?.key == "apple-music")
        #expect(BrandMatcher.match("Apple")?.key == "apple")
        #expect(BrandMatcher.match("Apple Card")?.icon == "apple")
    }
    @Test func everydayWordsNeedTheWholeNameToLookLikeTheBrand() {
        #expect(BrandMatcher.match("Medium")?.key == "medium")
        #expect(BrandMatcher.match("Medium Membership")?.key == "medium")
        #expect(BrandMatcher.match("Claude")?.key == "claude")
        #expect(BrandMatcher.match("Claude Pro")?.key == "claude")
        #expect(BrandMatcher.match("Cursor")?.key == "cursor")
        #expect(BrandMatcher.match("Chase Sapphire")?.key == "chase")
        #expect(BrandMatcher.match("Apple Orchard CSA") == nil)
        #expect(BrandMatcher.match("Claude's lawn care") == nil)
        #expect(BrandMatcher.match("Medium coffee club") == nil)
        #expect(BrandMatcher.match("Target practice range") == nil)
        #expect(BrandMatcher.match("Chase Bakery") == nil)
        #expect(BrandMatcher.match("Apple Orchard Rent") == nil)
        #expect(BrandMatcher.match("Netflix Camera Repair") == nil)
        #expect(BrandMatcher.match("Capital Bank") == nil)
        #expect(BrandMatcher.match("Capital City Dentist") == nil)
        #expect(BrandMatcher.match("Railway") == nil)
        #expect(BrandMatcher.match("Things") == nil)
    }
    @Test func theLongestAliasDecides() {
        #expect(BrandMatcher.match("Uber Eats")?.key == "uber-eats")
        #expect(BrandMatcher.match("Uber One")?.key == "uber")
        #expect(BrandMatcher.match("Google Fi")?.key == "google-fi")
        #expect(BrandMatcher.match("Claude Max")?.key == "claude")
        #expect(BrandMatcher.match("HBO Max")?.key == "hbo-max")
        #expect(BrandMatcher.match("Amex Delta")?.key == "amex")
        #expect(BrandMatcher.match("Amazon Prime Video")?.key == "amazon")
    }
    @Test func doesNotMatchInsideOtherWords() {
        #expect(BrandMatcher.match("Chaser") == nil)
        #expect(BrandMatcher.match("Pineapple") == nil)
        #expect(BrandMatcher.match("Citizen dues") == nil)
    }
    @Test func unknownNamesHaveNoMatch() {
        #expect(BrandMatcher.match("Mom's Piano Lessons") == nil)
        #expect(BrandMatcher.match("") == nil)
    }
    @Test func suggestsCategoryFromBrandOrCommonWords() {
        #expect(BrandMatcher.suggestedCategory(for: "Netflix") == .subscriptions)
        #expect(BrandMatcher.suggestedCategory(for: "Amex Platinum") == .creditCards)
        #expect(BrandMatcher.suggestedCategory(for: "Robinhood") == .investments)
        #expect(BrandMatcher.suggestedCategory(for: "Rent") == .housing)
        #expect(BrandMatcher.suggestedCategory(for: "Car insurance") == .insurance)
        #expect(BrandMatcher.suggestedCategory(for: "Electricity") == .utilities)
        #expect(BrandMatcher.suggestedCategory(for: "Mom's Piano Lessons") == .other)
    }
    @Test func iconFallsBackFromArtworkToSymbolToLetter() {
        #expect(BrandMatcher.iconContent(for: "Netflix") == .artwork("netflix"))
        #expect(BrandMatcher.iconContent(for: "Capital One") == .artwork("capital-one"))
        #expect(BrandMatcher.iconContent(for: "Store Card") == .symbol("creditcard"))
        #expect(BrandMatcher.iconContent(for: "Insurance") == .symbol("shield"))
        #expect(BrandMatcher.iconContent(for: "Internet") == .symbol("wifi"))
        #expect(BrandMatcher.iconContent(for: "piano lessons") == .monogram("P"))
        #expect(BrandMatcher.iconContent(for: "   ") == .monogram("•"))
    }
    @Test func everydayBillsGetASymbolOnlyWhenTheBillIsTheSubject() {
        for name in ["Rent", "Apartment Rent", "Apple Orchard Rent"] { #expect(BrandMatcher.iconContent(for: name) == .symbol("house")) }
        for name in ["Electric", "Electric Bill", "Duke Energy"] { #expect(BrandMatcher.iconContent(for: name) == .symbol("bolt")) }
        #expect(BrandMatcher.iconContent(for: "City Water") == .symbol("drop"))
        #expect(BrandMatcher.iconContent(for: "Gas bill") == .symbol("flame"))
        #expect(BrandMatcher.iconContent(for: "Trash") == .symbol("trash"))
        #expect(BrandMatcher.iconContent(for: "Sewer") == .symbol("water.waves"))
        #expect(BrandMatcher.iconContent(for: "Water Polo Dues") == .monogram("W"))
        #expect(BrandMatcher.iconContent(for: "Power Yoga") == .monogram("P"))
    }
}

/// Ties the catalog to the artwork that actually ships, so a brand can't claim an icon it doesn't have.
@Suite struct BrandIconAssetTests {
    @Test func everyDeclaredIconIsBundled() {
        let missing = BrandCatalog.all.compactMap(\.icon).filter { UIImage(named: "brand-\($0)") == nil }
        #expect(missing.isEmpty, "Missing artwork: \(missing)")
    }
    @Test func theRequestedBrandsHaveRealIcons() {
        for name in ["Apple", "American Express", "Netflix", "Spotify", "ChatGPT", "Claude", "Cursor", "Medium", "Adobe", "Robinhood"] {
            let icon = BrandMatcher.match(name)?.icon
            #expect(icon != nil, "\(name) has no icon")
            #expect(icon.flatMap { UIImage(named: "brand-\($0)") } != nil, "\(name) has no artwork")
        }
    }
    /// Every recognized brand now has a logo, and the downloaded ones fill the tile.
    @Test func recognizedBrandsAllHaveArtwork() {
        let missing = BrandCatalog.all.filter { $0.icon == nil }.map(\.name)
        #expect(missing.isEmpty, "No artwork: \(missing)")
        for name in ["Capital One", "Citi", "GEICO", "Disney+"] {
            let icon = BrandMatcher.match(name)?.icon
            #expect(icon.map(BrandCatalog.fullBleedIcons.contains) == true, "\(name)")
            #expect(icon.flatMap { UIImage(named: "brand-\($0)") } != nil, "\(name)")
        }
        #expect(!BrandCatalog.fullBleedIcons.contains("netflix"))
    }
    @Test func keysAreUnique() {
        let keys = BrandCatalog.all.map(\.key)
        #expect(Set(keys).count == keys.count)
    }
    /// Each brand's own first alias must find it, which also catches two brands claiming one spelling.
    @Test func everyAliasFindsItsOwnBrand() {
        for brand in BrandCatalog.all {
            for alias in brand.aliases { #expect(BrandMatcher.match(alias)?.key == brand.key, "\(alias)") }
            // These names are ordinary words on their own, so they need a telling alias like "Railway App".
            if !["EA", "Render", "Railway", "Sketch", "Unity", "Ghost", "Things"].contains(brand.name) {
                #expect(BrandMatcher.match(brand.name)?.key == brand.key, "\(brand.name)")
            }
        }
    }
    @Test func everyFallbackSymbolExists() {
        let symbols = Set(BrandCatalog.all.compactMap(\.symbol))
        #expect(symbols.allSatisfy { UIImage(systemName: $0) != nil })
        for name in ["Rent", "Electric", "Water", "Sewer", "Gas", "Trash", "Internet", "Phone", "Insurance", "Car Payment", "Store Card", "Loan"] {
            guard case .symbol(let symbol) = BrandMatcher.iconContent(for: name) else {
                Issue.record("\(name) has no symbol")
                continue
            }
            #expect(UIImage(systemName: symbol) != nil, "\(name)")
        }
    }
    /// A slug can share a name with an unrelated company. This one shipped showing Spectrum Chat's logo for the internet provider.
    /// It now uses the provider's own App Store icon, never the same-named slug.
    @Test func spectrumUsesTheProvidersOwnIcon() {
        #expect(BrandMatcher.match("Spectrum")?.icon == "spectrum")
        #expect(BrandCatalog.fullBleedIcons.contains("spectrum"))
        #expect(UIImage(named: "brand-spectrum") != nil)
    }
}
