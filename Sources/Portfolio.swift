import Foundation

// MARK: - Holdings

/// Shares you still own in one company, worked out from its trades (weighted average cost).
struct Holding: Identifiable {
    let symbol: String
    var shares: Double = 0
    var cost: Double = 0          // cost basis of the shares still held
    var realised: Double = 0      // gain from shares already sold
    var quote: Quote?

    var id: String { symbol }
    var avgCost: Double { shares > 0 ? cost / shares : 0 }
    var close: Double? { quote.map { NSDecimalNumber(decimal: $0.close).doubleValue } }
    var previousClose: Double? { quote.map { NSDecimalNumber(decimal: $0.previousClose).doubleValue } }
    /// Without a price yet, value it at cost so totals still make sense.
    var marketValue: Double { close.map { shares * $0 } ?? cost }
    var unrealised: Double { marketValue - cost }
    var unrealisedPercent: Double? { cost > 0 ? unrealised / cost : nil }
    var dayGain: Double {
        guard let close, let previousClose else { return 0 }
        return shares * (close - previousClose)
    }
    var dayPercent: Double? {
        guard let close, let previousClose, previousClose > 0 else { return nil }
        return (close - previousClose) / previousClose
    }
}

struct PortfolioSummary {
    let holdings: [Holding]      // shares still held, biggest first
    let realised: Double         // from sales recorded in Kharcha plus earlier realised gain

    var marketValue: Double { holdings.map(\.marketValue).reduce(0, +) }
    var cost: Double { holdings.map(\.cost).reduce(0, +) }
    var unrealised: Double { marketValue - cost }
    var unrealisedPercent: Double? { cost > 0 ? unrealised / cost : nil }
    var dayGain: Double { holdings.map(\.dayGain).reduce(0, +) }
    var dayPercent: Double? {
        let before = marketValue - dayGain
        return before > 0 ? dayGain / before : nil
    }
    var overall: Double { unrealised + realised }
    var isEmpty: Bool { holdings.isEmpty }

    init(trades: [Trade], quotes: [String: Quote], realisedBefore: Decimal) {
        var bySymbol: [String: Holding] = [:]
        // Oldest first; on the same moment, buys before sells.
        let ordered = trades.sorted { ($0.date, $0.side == .buy ? 0 : 1) < ($1.date, $1.side == .buy ? 0 : 1) }
        for t in ordered {
            var h = bySymbol[t.symbol] ?? Holding(symbol: t.symbol)
            let shares = NSDecimalNumber(decimal: t.shares).doubleValue
            let price = NSDecimalNumber(decimal: t.price).doubleValue
            switch t.side {
            case .buy:
                h.shares += shares
                h.cost += shares * price
            case .sell:
                let sold = min(shares, h.shares)
                let avg = h.avgCost
                h.realised += sold * (price - avg)
                h.cost -= sold * avg
                h.shares -= sold
                if h.shares < 0.000001 { h.shares = 0; h.cost = 0 }
            }
            bySymbol[t.symbol] = h
        }
        realised = NSDecimalNumber(decimal: realisedBefore).doubleValue + bySymbol.values.map(\.realised).reduce(0, +)
        holdings = bySymbol.values
            .filter { $0.shares > 0 }
            .map { h in var h = h; h.quote = quotes[h.symbol]; return h }
            .sorted { $0.marketValue > $1.marketValue }
    }
}

enum PriceStatus: Equatable {
    case idle, updating
    case failed(String)
}

// MARK: - Price feed

/// Reads NEPSE end-of-day prices from Sharesansar's public "Today's Share Price" page.
/// The whole market is downloaded and your symbols are picked out locally, so nothing about
/// what you own leaves your Mac.
enum PriceFeed {
    static let source = URL(string: "https://www.sharesansar.com/today-share-price")!
    static let sourceName = "sharesansar.com"
    static let nepal = TimeZone(identifier: "Asia/Kathmandu")!

    enum FeedError: LocalizedError {
        case http(Int), unreadable
        var errorDescription: String? {
            switch self {
            case .http(let code): "The price page answered with an error (\(code))."
            case .unreadable: "The price page has changed and couldn't be read."
            }
        }
    }

    static func fetch() async throws -> [String: Quote] {
        var request = URLRequest(url: source, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 30)
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15",
                         forHTTPHeaderField: "User-Agent")
        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, http.statusCode != 200 { throw FeedError.http(http.statusCode) }
        return try parse(String(decoding: data, as: UTF8.self))
    }

    static func parse(_ html: String) throws -> [String: Quote] {
        let asOf = firstMatch(#"As of\s*:\s*<span[^>]*>\s*(\d{4}-\d{2}-\d{2})"#, in: html).flatMap(day) ?? .now
        guard let table = firstMatch(#"(<table[^>]*>.*?</table>)"#, in: html, requiring: "Prev. Close") else {
            throw FeedError.unreadable
        }
        let headers = allMatches(#"<th[^>]*>(.*?)</th>"#, in: table).map(text)
        guard let iSymbol = headers.firstIndex(of: "Symbol"),
              let iClose = headers.firstIndex(of: "Close"),
              let iPrev = headers.firstIndex(of: "Prev. Close") else { throw FeedError.unreadable }
        // Optional extras; missing columns just leave the analysis board with less to show.
        let iHigh = headers.firstIndex(of: "52 Weeks High"), iLow = headers.firstIndex(of: "52 Weeks Low")
        let i120 = headers.firstIndex(of: "120 Days"), i180 = headers.firstIndex(of: "180 Days")
        let iOpen = headers.firstIndex(of: "Open"), iHighToday = headers.firstIndex(of: "High")
        let iLowToday = headers.firstIndex(of: "Low"), iVol = headers.firstIndex(of: "Vol")

        var quotes: [String: Quote] = [:]
        for row in allMatches(#"<tr[^>]*>(.*?)</tr>"#, in: table) {
            let cells = allMatches(#"<td[^>]*>(.*?)</td>"#, in: row).map(text)
            guard cells.count > max(iSymbol, iClose, iPrev),
                  let close = number(cells[iClose]), close > 0 else { continue }
            func extra(_ i: Int?) -> Decimal? {
                guard let i, i < cells.count, let v = number(cells[i]), v > 0 else { return nil }
                return v
            }
            let symbol = cells[iSymbol].uppercased()
            quotes[symbol] = Quote(close: close, previousClose: number(cells[iPrev]) ?? close, asOf: asOf,
                                   high52: extra(iHigh), low52: extra(iLow), avg120: extra(i120), avg180: extra(i180),
                                   open: extra(iOpen), high: extra(iHighToday), low: extra(iLowToday), volume: extra(iVol))
        }
        guard !quotes.isEmpty else { throw FeedError.unreadable }
        return quotes
    }

    // MARK: Helpers

    private static func allMatches(_ pattern: String, in text: String) -> [String] {
        let regex = try! NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators, .caseInsensitive])
        let ns = text as NSString
        return regex.matches(in: text, range: NSRange(location: 0, length: ns.length)).map { ns.substring(with: $0.range(at: 1)) }
    }

    private static func firstMatch(_ pattern: String, in text: String, requiring needle: String? = nil) -> String? {
        allMatches(pattern, in: text).first { needle == nil || $0.contains(needle!) }
    }

    private static func text(_ cell: String) -> String {
        cell.replacingOccurrences(of: #"<[^>]+>"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "&amp;", with: "&")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func number(_ s: String) -> Decimal? {
        Decimal(string: s.replacingOccurrences(of: ",", with: ""), locale: Locale(identifier: "en_US_POSIX"))
    }

    private static func day(_ ymd: String) -> Date? {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = nepal
        f.dateFormat = "yyyy-MM-dd HH:mm"
        return f.date(from: ymd + " 15:00")
    }
}

// MARK: - Updating

extension Store {
    var portfolio: PortfolioSummary {
        PortfolioSummary(trades: trades, quotes: quotes, realisedBefore: realisedBefore)
    }

    /// Symbols you've ever traded, for picking in forms.
    var knownSymbols: [String] { Array(Set(trades.map(\.symbol))).sorted() }

    /// Only runs when you click Fetch Prices: Kharcha never goes online on its own.
    func refreshPrices() async {
        guard priceStatus != .updating else { return }
        priceStatus = .updating
        do {
            let fresh = try await PriceFeed.fetch()
            applyQuotes(fresh, checkedAt: .now)
            priceStatus = .idle
        } catch {
            priceStatus = .failed(error.localizedDescription)
        }
    }
}
