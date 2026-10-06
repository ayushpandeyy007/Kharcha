import Foundation
import Observation
import SwiftUI   // Array.move(fromOffsets:toOffset:)

/// All app data, persisted as one JSON file in Application Support.
@MainActor @Observable
final class Store {
    private(set) var transactions: [Transaction] = []   // newest first
    private(set) var categories: [Category] = []
    private(set) var loans: [Loan] = []                 // newest first
    private(set) var wallets: [Wallet] = []
    private(set) var transfers: [Transfer] = []         // newest first
    private(set) var trades: [Trade] = []               // newest first
    private(set) var quotes: [String: Quote] = [:]
    private(set) var quotesCheckedAt: Date?
    private(set) var realisedBefore: Decimal = 0
    private(set) var days: [DayRecord] = []            // oldest first
    var priceStatus: PriceStatus = .idle
    private(set) var loadProblem: String?

    @ObservationIgnored let dataURL: URL

    init() {
        let dir: URL
        if let custom = ProcessInfo.processInfo.environment["KHARCHA_DATA_DIR"] {
            dir = URL(fileURLWithPath: custom, isDirectory: true)
        } else {
            dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("Kharcha", isDirectory: true)
        }
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        dataURL = dir.appendingPathComponent("data.json")
        load()
    }

    // MARK: Queries

    func category(_ id: UUID) -> Category {
        categories.first { $0.id == id }
            ?? categories.first { $0.id == Category.otherExpenseID }
            ?? Category.defaults.last!
    }

    func categories(of kind: Kind) -> [Category] {
        categories.filter { $0.kind == kind }
    }

    /// The category last used with this note, so "momo" keeps landing in Food.
    func suggestedCategory(forNote note: String, kind: Kind) -> UUID? {
        let key = note.trimmingCharacters(in: .whitespaces)
        guard !key.isEmpty else { return nil }
        return transactions.first {
            $0.kind == kind && $0.note.caseInsensitiveCompare(key) == .orderedSame
        }?.categoryID
    }

    // MARK: Transactions

    func add(_ transaction: Transaction) {
        transactions.append(transaction)
        sortAndSave()
    }

    func update(_ transaction: Transaction) {
        guard let i = transactions.firstIndex(where: { $0.id == transaction.id }) else { return }
        transactions[i] = transaction
        sortAndSave()
    }

    @discardableResult
    func delete(_ ids: Set<UUID>) -> [Transaction] {
        let removed = transactions.filter { ids.contains($0.id) }
        transactions.removeAll { ids.contains($0.id) }
        save()
        return removed
    }

    func restore(_ removed: [Transaction]) {
        transactions.append(contentsOf: removed)
        sortAndSave()
    }

    // MARK: Categories

    func upsert(_ category: Category) {
        if let i = categories.firstIndex(where: { $0.id == category.id }) {
            categories[i] = category
        } else if let i = categories.firstIndex(where: { $0.id == Category.fallbackID(for: category.kind) }) {
            categories.insert(category, at: i)   // keep "Other" last
        } else {
            categories.append(category)
        }
        save()
    }

    func usage(of categoryID: UUID) -> Int {
        transactions.reduce(0) { $0 + ($1.categoryID == categoryID ? 1 : 0) }
    }

    func deleteCategory(_ id: UUID) {
        guard let category = categories.first(where: { $0.id == id }), !category.isFallback else { return }
        let fallback = Category.fallbackID(for: category.kind)
        for i in transactions.indices where transactions[i].categoryID == id {
            transactions[i].categoryID = fallback
        }
        categories.removeAll { $0.id == id }
        save()
    }

    func moveCategories(of kind: Kind, from source: IndexSet, to destination: Int) {
        var subset = categories(of: kind)
        subset.move(fromOffsets: source, toOffset: destination)
        let others = categories.filter { $0.kind != kind }
        categories = kind == .expense ? subset + others : others + subset
        save()
    }

    // MARK: Loans

    func loan(_ id: UUID) -> Loan? { loans.first { $0.id == id } }

    /// Total still outstanding, e.g. everything people owe you.
    func outstanding(_ direction: Loan.Direction) -> Double {
        loans.filter { $0.direction == direction }
            .reduce(0) { $0 + NSDecimalNumber(decimal: $1.remaining).doubleValue }
    }

    /// Names used before, most recent first, for quick picking.
    var people: [String] {
        var seen = Set<String>()
        return loans.map(\.person).filter { seen.insert($0.lowercased()).inserted }
    }

    func addLoan(_ loan: Loan) {
        loans.append(loan)
        sortLoansAndSave()
    }

    func updateLoan(_ loan: Loan) {
        guard let i = loans.firstIndex(where: { $0.id == loan.id }) else { return }
        loans[i] = loan
        sortLoansAndSave()
    }

    @discardableResult
    func deleteLoan(_ id: UUID) -> Loan? {
        guard let i = loans.firstIndex(where: { $0.id == id }) else { return nil }
        let removed = loans.remove(at: i)
        save()
        return removed
    }

    func addRepayment(_ repayment: Repayment, to loanID: UUID) {
        guard let i = loans.firstIndex(where: { $0.id == loanID }) else { return }
        loans[i].repayments.append(repayment)
        loans[i].repayments.sort { $0.date < $1.date }
        save()
    }

    func deleteRepayment(_ repaymentID: UUID, from loanID: UUID) {
        guard let i = loans.firstIndex(where: { $0.id == loanID }) else { return }
        loans[i].repayments.removeAll { $0.id == repaymentID }
        save()
    }

    // MARK: Wallets

    func wallet(_ id: UUID?) -> Wallet? {
        guard let id else { return nil }
        return wallets.first { $0.id == id }
    }

    /// Every movement of money in or out of a wallet: (wallet, date, signed amount).
    /// Income adds and spending subtracts; lending takes money out and repayments to you put it
    /// back (borrowing the reverse); transfers move it between wallets.
    private func forEachFlow(_ visit: (UUID?, Date, Double) -> Void) {
        func d(_ x: Decimal) -> Double { NSDecimalNumber(decimal: x).doubleValue }
        for t in transactions {
            visit(t.walletID, t.date, t.kind == .income ? t.value : -t.value)
        }
        for loan in loans {
            let sign: Double = loan.direction == .lent ? 1 : -1
            visit(loan.walletID, loan.date, -sign * d(loan.amount))
            for r in loan.repayments {
                visit(r.walletID ?? loan.walletID, r.date, sign * d(r.amount))
            }
        }
        for x in transfers {
            visit(x.fromWalletID, x.date, -d(x.amount))
            visit(x.toWalletID, x.date, d(x.amount))
        }
        for t in trades {
            let total = d(t.shares * t.price)
            visit(t.walletID, t.date, t.side == .buy ? -total : total)
        }
    }

    /// Each wallet's balance right now: its opening amount plus every flow dated between the
    /// opening and now. Future-dated entries count once their day comes.
    func balances(now: Date = .now) -> [UUID: Double] {
        var result: [UUID: Double] = [:]
        var since: [UUID: Date] = [:]
        for w in wallets {
            result[w.id] = NSDecimalNumber(decimal: w.opening).doubleValue
            since[w.id] = w.openingDate
        }
        forEachFlow { walletID, date, delta in
            guard let walletID, let start = since[walletID], date >= start, date <= now else { return }
            result[walletID, default: 0] += delta
        }
        return result
    }

    /// Money in and out of each wallet during an interval (e.g. this month).
    func flows(in interval: DateInterval) -> [UUID: (in: Double, out: Double)] {
        var result: [UUID: (in: Double, out: Double)] = [:]
        forEachFlow { walletID, date, delta in
            guard let walletID, interval.holds(date) else { return }
            var f = result[walletID] ?? (0, 0)
            if delta >= 0 { f.in += delta } else { f.out -= delta }
            result[walletID] = f
        }
        return result
    }

    var totalBalance: Double { balances().values.reduce(0, +) }

    func addWallet(name: String, kind: Wallet.Kind, color: Int, balance: Decimal) {
        wallets.append(Wallet(name: name, kind: kind, color: color, opening: balance, openingDate: Self.anchorDate()))
        save()
    }

    func upsertWallet(_ wallet: Wallet) {
        if let i = wallets.firstIndex(where: { $0.id == wallet.id }) {
            wallets[i] = wallet
        } else {
            wallets.append(wallet)
        }
        save()
    }

    /// "This wallet has exactly this much right now" — everything earlier is already included.
    func setBalance(of walletID: UUID, to amount: Decimal) {
        guard let i = wallets.firstIndex(where: { $0.id == walletID }) else { return }
        wallets[i].opening = amount
        wallets[i].openingDate = Self.anchorDate()
        save()
    }

    func walletUsage(_ id: UUID) -> Int {
        transactions.filter { $0.walletID == id }.count
            + loans.filter { $0.walletID == id }.count
            + transfers.filter { $0.fromWalletID == id || $0.toWalletID == id }.count
            + trades.filter { $0.walletID == id }.count
    }

    /// Past entries keep their history (and still count in analytics) but no longer belong to a wallet.
    /// Transfers to or from it are removed. The last wallet can't be deleted.
    func deleteWallet(_ id: UUID) {
        guard wallets.count > 1 else { return }
        wallets.removeAll { $0.id == id }
        for i in transactions.indices where transactions[i].walletID == id { transactions[i].walletID = nil }
        for i in loans.indices {
            if loans[i].walletID == id { loans[i].walletID = nil }
            for j in loans[i].repayments.indices where loans[i].repayments[j].walletID == id {
                loans[i].repayments[j].walletID = nil
            }
        }
        transfers.removeAll { $0.fromWalletID == id || $0.toWalletID == id }
        for i in trades.indices where trades[i].walletID == id { trades[i].walletID = nil }
        save()
    }

    func moveWallets(from source: IndexSet, to destination: Int) {
        wallets.move(fromOffsets: source, toOffset: destination)
        save()
    }

    func addTransfer(_ transfer: Transfer) {
        transfers.append(transfer)
        transfers.sort { $0.date > $1.date }
        save()
    }

    @discardableResult
    func deleteTransfer(_ id: UUID) -> Transfer? {
        guard let i = transfers.firstIndex(where: { $0.id == id }) else { return nil }
        let removed = transfers.remove(at: i)
        save()
        return removed
    }

    // MARK: Stocks

    func addTrade(_ trade: Trade) {
        trades.append(trade)
        trades.sort { $0.date > $1.date }
        save()
    }

    func updateTrade(_ trade: Trade) {
        guard let i = trades.firstIndex(where: { $0.id == trade.id }) else { return }
        trades[i] = trade
        trades.sort { $0.date > $1.date }
        save()
    }

    @discardableResult
    func deleteTrades(_ ids: Set<UUID>) -> [Trade] {
        let removed = trades.filter { ids.contains($0.id) }
        trades.removeAll { ids.contains($0.id) }
        save()
        return removed
    }

    func restoreTrades(_ removed: [Trade]) {
        trades.append(contentsOf: removed)
        trades.sort { $0.date > $1.date }
        save()
    }

    func setRealisedBefore(_ amount: Decimal) {
        realisedBefore = amount
        save()
    }

    /// Prices from the market feed, merged over the old ones (symbols missing today keep their last price).
    func applyQuotes(_ fresh: [String: Quote], checkedAt: Date) {
        quotes.merge(fresh) { _, new in new }
        quotesCheckedAt = checkedAt
        recordDay(from: fresh)
        save()
    }

    /// Saves the trading day's close of everything you hold. Fetching again on the same day replaces it.
    /// A holding missing from that day's prices (e.g. it didn't trade) keeps its last price, unchanged.
    private func recordDay(from fresh: [String: Quote]) {
        let cal = Calendar.current
        guard let date = fresh.values.map(\.asOf).max() else { return }
        let held = PortfolioSummary(trades: trades, quotes: quotes, realisedBefore: 0).holdings
        let positions: [DayRecord.Position] = held.compactMap { h in
            guard let q = h.quote else { return nil }
            let tradedThatDay = fresh[h.symbol] != nil && cal.isDate(q.asOf, inSameDayAs: date)
            return DayRecord.Position(symbol: h.symbol, shares: Decimal(h.shares), cost: Decimal(h.cost),
                                      close: q.close, previousClose: tradedThatDay ? q.previousClose : q.close)
        }
        guard !positions.isEmpty else { return }
        days.removeAll { cal.isDate($0.date, inSameDayAs: date) }
        days.append(DayRecord(date: date, positions: positions))
        days.sort { $0.date < $1.date }
    }

    /// A price typed in by hand, for when the feed is down or a symbol isn't listed.
    func setPrice(_ symbol: String, close: Decimal) {
        var quote = quotes[symbol] ?? Quote(close: close, previousClose: close, asOf: .now)
        quote.previousClose = quotes[symbol]?.close ?? close
        quote.close = close
        quote.asOf = .now
        quotes[symbol] = quote
        save()
    }

    /// Whole seconds, rounded up: the data file stores whole seconds, so this keeps "what counts
    /// after the balance was set" identical before and after a relaunch.
    private static func anchorDate() -> Date {
        Date(timeIntervalSince1970: Date().timeIntervalSince1970.rounded(.up))
    }

    // MARK: Export

    func backupData() throws -> Data {
        try Self.encoder.encode(snapshot)
    }

    // MARK: Persistence

    private var snapshot: Snapshot {
        Snapshot(categories: categories, transactions: transactions, loans: loans, wallets: wallets, transfers: transfers,
                 trades: trades, quotes: quotes, quotesCheckedAt: quotesCheckedAt, realisedBefore: realisedBefore,
                 days: days)
    }

    private func sortLoansAndSave() {
        loans.sort { $0.date > $1.date }
        save()
    }

    private func sortAndSave() {
        transactions.sort { $0.date > $1.date }
        save()
    }

    private func load() {
        guard let data = try? Data(contentsOf: dataURL) else {
            categories = Category.defaults
            wallets = Wallet.starters()
            return
        }
        do {
            let snapshot = try Self.decoder.decode(Snapshot.self, from: data)
            categories = snapshot.categories.isEmpty ? Category.defaults : snapshot.categories
            transactions = snapshot.transactions.sorted { $0.date > $1.date }
            loans = snapshot.loans.sorted { $0.date > $1.date }
            transfers = snapshot.transfers.sorted { $0.date > $1.date }
            trades = snapshot.trades.sorted { $0.date > $1.date }
            quotes = snapshot.quotes
            quotesCheckedAt = snapshot.quotesCheckedAt
            realisedBefore = snapshot.realisedBefore
            days = snapshot.days.sorted { $0.date < $1.date }
            for fallback in Category.defaults where fallback.isFallback && !categories.contains(where: { $0.id == fallback.id }) {
                categories.append(fallback)
            }
            // One known-good copy per launch, in case the main file is ever damaged.
            try? data.write(to: dataURL.deletingLastPathComponent().appendingPathComponent("data.backup.json"), options: .atomic)

            if let saved = snapshot.wallets, !saved.isEmpty {
                wallets = saved
            } else {
                // Before wallets: the single account balance becomes "Bank account", and everything
                // already recorded belongs to it, so the balance carries over unchanged.
                wallets = Wallet.starters(bankOpening: snapshot.balance)
                for i in transactions.indices where transactions[i].walletID == nil { transactions[i].walletID = Wallet.bankID }
                for i in loans.indices where loans[i].walletID == nil { loans[i].walletID = Wallet.bankID }
                save()
            }
        } catch {
            // Never overwrite a file we couldn't read: move it aside and start fresh.
            let stamp = Int(Date().timeIntervalSince1970)
            let aside = dataURL.deletingLastPathComponent().appendingPathComponent("data-unreadable-\(stamp).json")
            try? FileManager.default.moveItem(at: dataURL, to: aside)
            categories = Category.defaults
            loadProblem = "Your data file couldn't be read, so it was moved to \(aside.lastPathComponent)."
        }
    }

    private func save() {
        do {
            let data = try Self.encoder.encode(snapshot)
            try data.write(to: dataURL, options: .atomic)
        } catch {
            NSLog("Kharcha: failed to save data: \(error)")
        }
    }

    private static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.prettyPrinted]
        return e
    }()

    private static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()
}
