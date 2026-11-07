import Foundation
import Testing
@testable import Cushn

@Suite struct MoneyParsingTests {
    let us = Locale(identifier: "en_US")
    let de = Locale(identifier: "de_DE")
    let india = Locale(identifier: "en_IN")

    @Test func parsesPlainAmounts() throws {
        #expect(try Money.parse("30", currencyCode: "USD", locale: us).minorUnits == 3000)
        #expect(try Money.parse("12.5", currencyCode: "USD", locale: us).minorUnits == 1250)
        #expect(try Money.parse("0.07", currencyCode: "USD", locale: us).minorUnits == 7)
        #expect(try Money.parse(" 19.99 ", currencyCode: "USD", locale: us).minorUnits == 1999)
    }
    @Test func avoidsFloatingPointError() throws {
        #expect(try Money.parse("1.15", currencyCode: "USD", locale: us).minorUnits == 115)
        #expect(try Money.parse("4.35", currencyCode: "USD", locale: us).minorUnits == 435)
    }
    @Test func respectsLocaleSeparators() throws {
        #expect(try Money.parse("1,234.50", currencyCode: "USD", locale: us).minorUnits == 123450)
        #expect(try Money.parse("1.234,50", currencyCode: "EUR", locale: de).minorUnits == 123450)
        #expect(try Money.parse("12,50", currencyCode: "EUR", locale: de).minorUnits == 1250)
        #expect(try Money.parse("1,00,000", currencyCode: "INR", locale: india).minorUnits == 10000000)
    }
    @Test func treatsForeignDecimalPointAsDecimalWhenUnambiguous() throws {
        #expect(try Money.parse("12.50", currencyCode: "EUR", locale: de).minorUnits == 1250)
    }
    @Test func honoursCurrencyMinorDigits() throws {
        #expect(try Money.parse("500", currencyCode: "JPY", locale: us).minorUnits == 500)
        #expect(try Money.parse("1.234", currencyCode: "KWD", locale: us).minorUnits == 1234)
        #expect(throws: MoneyParseError.tooManyDecimals) { try Money.parse("5.5", currencyCode: "JPY", locale: us) }
        #expect(throws: MoneyParseError.tooManyDecimals) { try Money.parse("1.999", currencyCode: "USD", locale: us) }
    }
    @Test func rejectsInvalidInput() {
        for bad in ["", "   ", "abc", "1.2.3", "12a", "--4"] {
            #expect(throws: MoneyParseError.self) { try Money.parse(bad, currencyCode: "USD", locale: us) }
        }
        #expect(throws: MoneyParseError.negative) { try Money.parse("-4", currencyCode: "USD", locale: us) }
        #expect(throws: MoneyParseError.tooLarge) { try Money.parse("99999999999999999999", currencyCode: "USD", locale: us) }
    }
    @Test func roundTripsEditText() throws {
        let text = usd(123450).editingText(locale: us)
        #expect(text == "1234.50")
        #expect(try Money.parse(text, currencyCode: "USD", locale: us).minorUnits == 123450)
        let german = Money(minorUnits: 123450, currencyCode: "EUR").editingText(locale: de)
        #expect(german == "1234,50")
        #expect(Money(minorUnits: 500, currencyCode: "JPY").editingText(locale: us) == "500")
    }
    @Test func formatsWithLocale() {
        #expect(usd(3000).formatted(locale: us) == "$30.00")
        #expect(Money(minorUnits: 500, currencyCode: "JPY").formatted(locale: us) == "¥500")
    }
}
