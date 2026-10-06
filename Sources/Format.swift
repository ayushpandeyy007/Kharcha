import Foundation

enum Money {
    static let symbolKey = "currencySymbol"

    static var symbol: String {
        let s = UserDefaults.standard.string(forKey: symbolKey)?.trimmingCharacters(in: .whitespaces) ?? ""
        return s.isEmpty ? "Rs" : s
    }

    // en_IN gives lakh/crore grouping (1,00,000), which is what Nepal uses too.
    private static let grouped: NumberFormatter = {
        let f = NumberFormatter()
        f.locale = Locale(identifier: "en_IN")
        f.numberStyle = .decimal
        f.minimumFractionDigits = 0
        f.maximumFractionDigits = 2
        return f
    }()

    /// "Rs 12,34,567" / "−Rs 500"
    static func string(_ value: Double) -> String {
        let digits = grouped.string(from: NSNumber(value: abs(value))) ?? "0"
        return (value < 0 ? "−" : "") + symbol + " " + digits
    }

    static func string(_ value: Decimal) -> String {
        string(NSDecimalNumber(decimal: value).doubleValue)
    }

    /// Short form for axes and tight spots: 950, 12.5K, 1.2L, 3.4Cr
    static func compact(_ value: Double) -> String {
        let a = abs(value)
        let (divisor, suffix): (Double, String) =
            a >= 1e7 ? (1e7, "Cr") : a >= 1e5 ? (1e5, "L") : a >= 1e3 ? (1e3, "K") : (1, "")
        let n = a / divisor
        var number = String(format: divisor == 1 || n >= 100 ? "%.0f" : "%.1f", n)
        if number.hasSuffix(".0") { number.removeLast(2) }
        return (value < 0 ? "−" : "") + number + suffix
    }

    static func compactWithSymbol(_ value: Double) -> String {
        symbol + " " + compact(value)
    }

    /// Accepts "1,250", "Rs 300" and quick sums like "120+80-20".
    static func parse(_ text: String, allowZero: Bool = false) -> Decimal? {
        let cleaned = text
            .replacingOccurrences(of: "rs.", with: "", options: .caseInsensitive)
            .filter { "0123456789.+-".contains($0) }
        guard !cleaned.isEmpty else { return nil }
        var total = Decimal.zero
        var number = ""
        var sign: Decimal = 1
        for ch in cleaned + "+" {
            if ch == "+" || ch == "-" {
                if !number.isEmpty {
                    guard number.filter({ $0 == "." }).count <= 1,
                          let d = Decimal(string: number, locale: Locale(identifier: "en_US_POSIX")) else { return nil }
                    total += sign * d
                }
                number = ""
                sign = ch == "-" ? -1 : 1
            } else {
                number.append(ch)
            }
        }
        guard total > 0 || (allowZero && total == 0) else { return nil }
        var rounded = Decimal()
        NSDecimalRound(&rounded, &total, 2, .plain)
        return rounded
    }

    static func isExpression(_ text: String) -> Bool {
        text.dropFirst().contains { $0 == "+" || $0 == "-" }
    }
}

func percent(_ fraction: Double, decimals: Int = 0) -> String {
    fraction.formatted(.percent.precision(.fractionLength(decimals)))
}

extension Calendar {
    func days(from a: Date, to b: Date) -> Int {
        dateComponents([.day], from: startOfDay(for: a), to: startOfDay(for: b)).day ?? 0
    }

    func monthStart(_ date: Date) -> Date {
        dateInterval(of: .month, for: date)!.start
    }

    func adding(days: Int, to date: Date) -> Date {
        self.date(byAdding: .day, value: days, to: date)!
    }

    /// Weekday indices (1 = Sunday) in the user's display order.
    var orderedWeekdays: [Int] {
        (0..<7).map { (firstWeekday - 1 + $0) % 7 + 1 }
    }
}

extension DateInterval {
    /// Half-open containment: start ≤ date < end.
    func holds(_ date: Date) -> Bool { date >= start && date < end }
}

extension Date {
    func dayTitle(calendar cal: Calendar = .current) -> String {
        if cal.isDateInToday(self) { return "Today" }
        if cal.isDateInYesterday(self) { return "Yesterday" }
        if cal.isDate(self, equalTo: .now, toGranularity: .year) {
            return formatted(.dateTime.weekday(.wide).month(.abbreviated).day())
        }
        return formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day().year())
    }
}
