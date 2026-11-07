import Foundation

enum MoneyParseError: Error, Equatable {
    case invalid, negative, tooManyDecimals, tooLarge
}

/// An integer amount in a currency's minor units. No floating point takes part in money.
struct Money: Hashable, Codable, Sendable {
    let minorUnits: Int64
    let currencyCode: String

    /// ISO minor digits for a currency (USD 2, JPY 0, KWD 3).
    static func minorDigits(for currencyCode: String) -> Int {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = currencyCode
        return formatter.maximumFractionDigits
    }

    private var decimalValue: Decimal {
        Decimal(sign: minorUnits < 0 ? .minus : .plus,
                exponent: -Self.minorDigits(for: currencyCode),
                significand: Decimal(minorUnits.magnitude))
    }

    func formatted(locale: Locale = .autoupdatingCurrent) -> String {
        decimalValue.formatted(.currency(code: currencyCode).locale(locale))
    }

    /// Plain locale-aware text for an amount field: no symbol or grouping, and parseable by `parse`.
    func editingText(locale: Locale = .autoupdatingCurrent) -> String {
        let digits = Self.minorDigits(for: currencyCode)
        guard digits > 0 else { return String(minorUnits) }
        let divisor = (0..<digits).reduce(Int64(1)) { value, _ in value * 10 }
        let whole = minorUnits / divisor
        let fraction = String(minorUnits % divisor)
        let padded = String(repeating: "0", count: digits - fraction.count) + fraction
        return "\(whole)\(locale.decimalSeparator ?? ".")\(padded)"
    }

    /// Strict locale-aware parser. Prefers rejecting ambiguous input over storing a wrong amount.
    static func parse(_ text: String, currencyCode: String, locale: Locale = .autoupdatingCurrent) throws -> Money {
        var input = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let isNegative = input.hasPrefix("-")
        if isNegative { input.removeFirst() }
        guard !input.isEmpty else { throw MoneyParseError.invalid }

        // Normalize non-ASCII digits, such as those from an Arabic decimal keypad.
        input = String(input.map { character in
            character.wholeNumberValue.flatMap { Character("\($0)") } ?? character
        })

        let decimalSeparator = locale.decimalSeparator ?? "."
        let groupingSeparator = locale.groupingSeparator ?? ","
        let (whole, fraction) = try split(input, decimal: decimalSeparator, grouping: groupingSeparator)

        guard !whole.isEmpty || !fraction.isEmpty,
              (whole + fraction).allSatisfy({ $0.isASCII && $0.isNumber }) else {
            throw MoneyParseError.invalid
        }

        let digits = minorDigits(for: currencyCode)
        let significantFraction = fraction.reversed().drop { $0 == "0" }.count
        guard significantFraction <= digits else { throw MoneyParseError.tooManyDecimals }
        let paddedFraction = String(fraction.prefix(digits)).padding(toLength: digits, withPad: "0", startingAt: 0)

        var total: Int64 = 0
        for character in whole + paddedFraction {
            let (scaled, overflowed) = total.multipliedReportingOverflow(by: 10)
            let (sum, added) = scaled.addingReportingOverflow(Int64(character.wholeNumberValue!))
            guard !overflowed, !added else { throw MoneyParseError.tooLarge }
            total = sum
        }
        if isNegative { throw MoneyParseError.negative }
        return Money(minorUnits: total, currencyCode: currencyCode)
    }

    private static func split(_ input: String, decimal: String, grouping: String) throws -> (whole: String, fraction: String) {
        let parts = input.components(separatedBy: decimal)
        guard parts.count <= 2 else { throw MoneyParseError.invalid }
        let groups = parts[0].components(separatedBy: grouping)
        let hasDecimalPart = parts.count == 2

        guard groups.count > 1 else { return (parts[0], hasDecimalPart ? parts[1] : "") }

        // One separator without three digits after it can't be grouping, so it's a decimal point
        // typed with the other convention ("12.50" under a German locale).
        if !hasDecimalPart, groups.count == 2, groups[1].count != 3 {
            return (groups[0], groups[1])
        }

        // 1,234,567 and Indian 1,00,000 are valid; 12,34 and 1,2,345 are not.
        guard (1...3).contains(groups[0].count),
              groups[groups.count - 1].count == 3,
              groups.dropFirst().dropLast().allSatisfy({ $0.count == 2 || $0.count == 3 }) else {
            throw MoneyParseError.invalid
        }
        return (groups.joined(), hasDecimalPart ? parts[1] : "")
    }
}
