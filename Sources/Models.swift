import Foundation

enum Kind: String, Codable, CaseIterable, Identifiable {
    case expense, income

    var id: Self { self }
    var title: String { self == .expense ? "Expense" : "Income" }
}

struct Category: Identifiable, Codable, Hashable {
    var id: UUID
    var name: String
    var icon: String   // SF Symbol name
    var color: Int     // index into Palette.slots, -1 = neutral gray
    var kind: Kind

    // The two "Other" categories always exist: deleted categories hand their transactions to them.
    static let otherExpenseID = fixedID(0xE000)
    static let otherIncomeID = fixedID(0xF000)

    static func fallbackID(for kind: Kind) -> UUID { kind == .expense ? otherExpenseID : otherIncomeID }
    var isFallback: Bool { id == Self.otherExpenseID || id == Self.otherIncomeID }

    private static func fixedID(_ n: Int) -> UUID {
        UUID(uuidString: String(format: "00000000-0000-0000-0000-%012X", n))!
    }

    static let defaults: [Category] = [
        Category(id: fixedID(1), name: "Food & Dining", icon: "fork.knife", color: 1, kind: .expense),
        Category(id: fixedID(2), name: "Groceries", icon: "cart", color: 5, kind: .expense),
        Category(id: fixedID(3), name: "Transport", icon: "car", color: 0, kind: .expense),
        Category(id: fixedID(4), name: "Rent & Home", icon: "house", color: 6, kind: .expense),
        Category(id: fixedID(5), name: "Bills", icon: "bolt", color: 3, kind: .expense),
        Category(id: fixedID(6), name: "Shopping", icon: "bag", color: 4, kind: .expense),
        Category(id: fixedID(7), name: "Health", icon: "cross.case", color: 7, kind: .expense),
        Category(id: fixedID(8), name: "Fun", icon: "popcorn", color: 2, kind: .expense),
        Category(id: fixedID(9), name: "Education", icon: "book", color: 6, kind: .expense),
        Category(id: fixedID(10), name: "Travel", icon: "airplane", color: 0, kind: .expense),
        Category(id: otherExpenseID, name: "Other", icon: "ellipsis.circle", color: -1, kind: .expense),
        Category(id: fixedID(11), name: "Salary", icon: "briefcase", color: 5, kind: .income),
        Category(id: fixedID(12), name: "Freelance", icon: "laptopcomputer", color: 0, kind: .income),
        Category(id: fixedID(13), name: "Gifts", icon: "gift", color: 4, kind: .income),
        Category(id: fixedID(14), name: "Investments", icon: "chart.line.uptrend.xyaxis", color: 6, kind: .income),
        Category(id: otherIncomeID, name: "Other", icon: "plus.circle", color: -1, kind: .income),
    ]
}

struct Transaction: Identifiable, Codable, Hashable {
    var id = UUID()
    var kind: Kind
    var amount: Decimal
    var categoryID: UUID
    var note: String = ""
    var date: Date
    var walletID: UUID?

    var value: Double { NSDecimalNumber(decimal: amount).doubleValue }
}

/// Money lent to or borrowed from a person, paid back in one or more repayments.
/// Kept separate from transactions: lending isn't spending, and getting it back isn't income.
struct Loan: Identifiable, Codable, Hashable {
    enum Direction: String, Codable, CaseIterable, Identifiable {
        case lent, borrowed
        var id: Self { self }
        var title: String { self == .lent ? "I lent" : "I borrowed" }
    }

    var id = UUID()
    var direction: Direction
    var person: String
    var amount: Decimal
    var date: Date
    var dueDate: Date?
    var note: String = ""
    var repayments: [Repayment] = []
    var walletID: UUID?

    var repaid: Decimal { repayments.reduce(0) { $0 + $1.amount } }
    var remaining: Decimal { max(0, amount - repaid) }
    var isSettled: Bool { remaining <= 0 }
    var progress: Double { amount > 0 ? min(1, NSDecimalNumber(decimal: repaid / amount).doubleValue) : 0 }

    func isOverdue(now: Date = .now) -> Bool {
        guard !isSettled, let dueDate else { return false }
        let cal = Calendar.current
        return cal.startOfDay(for: dueDate) < cal.startOfDay(for: now)
    }
}

struct Repayment: Identifiable, Codable, Hashable {
    var id = UUID()
    var amount: Decimal
    var date: Date
    var walletID: UUID?   // nil = same wallet as the loan
}

/// A place money sits: bank account, cash in hand, eSewa…
/// Its balance is `opening` (what you said it held at `openingDate`) plus everything recorded since.
struct Wallet: Identifiable, Codable, Hashable {
    enum Kind: String, Codable, CaseIterable, Identifiable {
        case bank, cash, digital, other
        var id: Self { self }
        var title: String {
            switch self {
            case .bank: "Bank account"
            case .cash: "Cash"
            case .digital: "Digital wallet"
            case .other: "Other"
            }
        }
        var icon: String {
            switch self {
            case .bank: "building.columns"
            case .cash: "banknote"
            case .digital: "iphone"
            case .other: "wallet.pass"
            }
        }
    }

    var id = UUID()
    var name: String
    var kind: Kind
    var color: Int
    var opening: Decimal = 0
    var openingDate: Date = .now

    /// Fixed IDs so the starter wallets are stable before anything is saved.
    static let bankID = UUID(uuidString: "00000000-0000-0000-0000-00000000B001")!

    static func starters(bankOpening: BalanceAnchor? = nil, now: Date = .now) -> [Wallet] {
        func id(_ n: Int) -> UUID { UUID(uuidString: String(format: "00000000-0000-0000-0000-00000000B%03d", n))! }
        return [
            Wallet(id: bankID, name: "Bank account", kind: .bank, color: 0,
                   opening: bankOpening?.amount ?? 0, openingDate: bankOpening?.date ?? now),
            Wallet(id: id(2), name: "Cash in hand", kind: .cash, color: 5, openingDate: now),
            Wallet(id: id(3), name: "eSewa", kind: .digital, color: 2, openingDate: now),
            Wallet(id: id(4), name: "Khalti", kind: .digital, color: 6, openingDate: now),
        ]
    }
}

/// Money moved between your own wallets (ATM withdrawal, topping up eSewa). Not spending, not income.
struct Transfer: Identifiable, Codable, Hashable {
    var id = UUID()
    var fromWalletID: UUID
    var toWalletID: UUID
    var amount: Decimal
    var date: Date
    var note: String = ""
}

/// One buy or sell of NEPSE shares. Holdings, average cost and realised gain are worked out from these.
struct Trade: Identifiable, Codable, Hashable {
    enum Side: String, Codable, CaseIterable, Identifiable {
        case buy, sell
        var id: Self { self }
        var title: String { self == .buy ? "Buy" : "Sell" }
    }

    var id = UUID()
    var symbol: String          // uppercased NEPSE symbol, e.g. "NABIL"
    var side: Side
    var shares: Decimal
    var price: Decimal          // per share; buys include charges, sells are after charges
    var date: Date
    var walletID: UUID?         // nil = no wallet involved (e.g. shares you already owned)
    var note: String = ""
}

/// End-of-day price for one symbol, plus the longer-range figures shown on the analysis board.
struct Quote: Codable, Hashable {
    var close: Decimal
    var previousClose: Decimal
    var asOf: Date              // trading day the prices are for
    var high52: Decimal?        // 52-week high / low
    var low52: Decimal?
    var avg120: Decimal?        // average price over 120 / 180 days
    var avg180: Decimal?
    var open: Decimal?          // the trading day's open, high, low and volume
    var high: Decimal?
    var low: Decimal?
    var volume: Decimal?
}

/// What your portfolio looked like at the close of one trading day, saved each time you fetch prices.
struct DayRecord: Codable, Hashable, Identifiable {
    struct Position: Codable, Hashable {
        var symbol: String
        var shares: Decimal
        var cost: Decimal
        var close: Decimal
        var previousClose: Decimal
    }

    var date: Date              // the trading day (prices' "as of")
    var positions: [Position]
    var id: Date { date }

    private func sum(_ f: (Position) -> Decimal) -> Double {
        NSDecimalNumber(decimal: positions.reduce(Decimal.zero) { $0 + f($1) }).doubleValue
    }
    var value: Double { sum { $0.shares * $0.close } }
    var previousValue: Double { sum { $0.shares * $0.previousClose } }
    var cost: Double { sum { $0.cost } }
    var dayGain: Double { value - previousValue }
    var dayPercent: Double? { previousValue > 0 ? dayGain / previousValue : nil }
}

/// v3 stored a single account balance; v4 moves it into the "Bank account" wallet.
struct BalanceAnchor: Codable, Hashable {
    var amount: Decimal
    var date: Date
}

struct Snapshot: Codable {
    var version = 6
    var categories: [Category]
    var transactions: [Transaction]
    var loans: [Loan] = []
    var wallets: [Wallet]?          // nil only in files from before wallets existed
    var transfers: [Transfer] = []
    var trades: [Trade] = []
    var quotes: [String: Quote] = [:]
    var quotesCheckedAt: Date?
    var realisedBefore: Decimal = 0 // realised gain from sales made before using Kharcha
    var days: [DayRecord] = []      // portfolio at each fetched close, oldest first
    var balance: BalanceAnchor?     // legacy (v3), read for migration only

    init(categories: [Category], transactions: [Transaction], loans: [Loan] = [],
         wallets: [Wallet]? = nil, transfers: [Transfer] = [], trades: [Trade] = [],
         quotes: [String: Quote] = [:], quotesCheckedAt: Date? = nil, realisedBefore: Decimal = 0,
         days: [DayRecord] = []) {
        self.categories = categories
        self.transactions = transactions
        self.loans = loans
        self.wallets = wallets
        self.transfers = transfers
        self.trades = trades
        self.quotes = quotes
        self.quotesCheckedAt = quotesCheckedAt
        self.realisedBefore = realisedBefore
        self.days = days
    }

    // Older files lack "loans" (v1), "balance" (v1–2), "wallets"/"transfers" (v1–3), stocks (v1–4), days (v1–5).
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        version = try c.decodeIfPresent(Int.self, forKey: .version) ?? 1
        categories = try c.decode([Category].self, forKey: .categories)
        transactions = try c.decode([Transaction].self, forKey: .transactions)
        loans = try c.decodeIfPresent([Loan].self, forKey: .loans) ?? []
        wallets = try c.decodeIfPresent([Wallet].self, forKey: .wallets)
        transfers = try c.decodeIfPresent([Transfer].self, forKey: .transfers) ?? []
        trades = try c.decodeIfPresent([Trade].self, forKey: .trades) ?? []
        quotes = try c.decodeIfPresent([String: Quote].self, forKey: .quotes) ?? [:]
        quotesCheckedAt = try c.decodeIfPresent(Date.self, forKey: .quotesCheckedAt)
        realisedBefore = try c.decodeIfPresent(Decimal.self, forKey: .realisedBefore) ?? 0
        days = try c.decodeIfPresent([DayRecord].self, forKey: .days) ?? []
        balance = try c.decodeIfPresent(BalanceAnchor.self, forKey: .balance)
    }
}
