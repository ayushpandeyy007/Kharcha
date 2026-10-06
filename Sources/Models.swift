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

/// v3 stored a single account balance; v4 moves it into the "Bank account" wallet.
struct BalanceAnchor: Codable, Hashable {
    var amount: Decimal
    var date: Date
}

struct Snapshot: Codable {
    var version = 4
    var categories: [Category]
    var transactions: [Transaction]
    var loans: [Loan] = []
    var wallets: [Wallet]?          // nil only in files from before wallets existed
    var transfers: [Transfer] = []
    var balance: BalanceAnchor?     // legacy (v3), read for migration only

    init(categories: [Category], transactions: [Transaction], loans: [Loan] = [],
         wallets: [Wallet]? = nil, transfers: [Transfer] = []) {
        self.categories = categories
        self.transactions = transactions
        self.loans = loans
        self.wallets = wallets
        self.transfers = transfers
    }

    // Older files lack "loans" (v1), "balance" (v1–2), "wallets"/"transfers" (v1–3).
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        version = try c.decodeIfPresent(Int.self, forKey: .version) ?? 1
        categories = try c.decode([Category].self, forKey: .categories)
        transactions = try c.decode([Transaction].self, forKey: .transactions)
        loans = try c.decodeIfPresent([Loan].self, forKey: .loans) ?? []
        wallets = try c.decodeIfPresent([Wallet].self, forKey: .wallets)
        transfers = try c.decodeIfPresent([Transfer].self, forKey: .transfers) ?? []
        balance = try c.decodeIfPresent(BalanceAnchor.self, forKey: .balance)
    }
}
