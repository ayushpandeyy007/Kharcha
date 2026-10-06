// Writes ~14 months of realistic sample data (wallets, transfers, loans) for previewing the app.
// Usage: swiftc Sources/Models.swift scripts/demo-data/main.swift -o /tmp/demo && /tmp/demo <dir>
// Then:  KHARCHA_DATA_DIR=<dir> build/Kharcha.app/Contents/MacOS/Kharcha
import Foundation

let dir = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

let cats = Dictionary(uniqueKeysWithValues: Category.defaults.map { ($0.name + "|" + $0.kind.rawValue, $0.id) })
func cat(_ name: String, _ kind: Kind = .expense) -> UUID { cats[name + "|" + kind.rawValue]! }

let cal = Calendar.current
let today = cal.startOfDay(for: .now)
let start = cal.date(byAdding: .month, value: -14, to: cal.dateInterval(of: .month, for: today)!.start)!

var wallets = Wallet.starters(now: start)
let bank = wallets[0].id, cash = wallets[1].id, esewa = wallets[2].id, khalti = wallets[3].id
let opening: [UUID: Double] = [bank: 120000, cash: 3000, esewa: 1500, khalti: 500]
for i in wallets.indices { wallets[i].opening = Decimal(opening[wallets[i].id]!) }
var balance = opening

var transactions: [Transaction] = []
var transfers: [Transfer] = []
var loans: [Loan] = []

func at(_ day: Date, _ hour: Int = Int.random(in: 8...21)) -> Date {
    cal.date(bySettingHour: hour, minute: Int.random(in: 0...59), second: 0, of: day)!
}

/// Tops up a cash/digital wallet from the bank first if it can't cover the payment, like real life.
func ensure(_ wallet: UUID, _ amount: Double, _ day: Date) {
    guard wallet != bank, balance[wallet]! < amount else { return }
    let usual = wallet == cash ? 5000.0 : 2000
    let topUp = max(usual, ((amount - balance[wallet]!) / 1000).rounded(.up) * 1000 + 1000)
    transfers.append(Transfer(fromWalletID: bank, toWalletID: wallet, amount: Decimal(topUp), date: at(day, 8),
                              note: wallet == cash ? "ATM withdrawal" : "Top-up"))
    balance[bank]! -= topUp
    balance[wallet]! += topUp
}

func spend(_ amount: Double, _ category: String, _ note: String, _ wallet: UUID, _ day: Date, hour: Int? = nil) {
    let value = amount.rounded()
    ensure(wallet, value, day)
    transactions.append(Transaction(kind: .expense, amount: Decimal(value), categoryID: cat(category), note: note,
                                    date: at(day, hour ?? Int.random(in: 9...21)), walletID: wallet))
    balance[wallet]! -= value
}

func earn(_ amount: Double, _ category: String, _ note: String, _ wallet: UUID, _ day: Date) {
    let value = amount.rounded()
    transactions.append(Transaction(kind: .income, amount: Decimal(value), categoryID: cat(category, .income), note: note,
                                    date: at(day, 9), walletID: wallet))
    balance[wallet]! += value
}

var day = start
while day <= today {
    let dom = cal.component(.day, from: day)
    let weekday = cal.component(.weekday, from: day)
    let weekend = weekday == 7 || weekday == 1

    if dom == 1 {
        earn(85000, "Salary", "Salary", bank, day)
        spend(22000, "Rent & Home", "Rent", bank, day, hour: 10)
        spend(1299, "Bills", "Internet", esewa, day)
    }
    if dom == 5 { spend(Double.random(in: 1400...2600), "Bills", "Electricity", esewa, day) }
    if dom == 15, Bool.random() { earn(Double.random(in: 8000...25000), "Freelance", "Design project", bank, day) }

    // Some days nothing at all.
    if Int.random(in: 0..<10) < (weekend ? 1 : 2) { day = cal.date(byAdding: .day, value: 1, to: day)!; continue }

    if Bool.random() { spend(Double.random(in: 120...260), "Food & Dining", "Momo", cash, day) }
    if Int.random(in: 0..<3) == 0 { spend(Double.random(in: 90...180), "Food & Dining", "Coffee", Bool.random() ? cash : esewa, day) }
    if !weekend, Int.random(in: 0..<3) > 0 { spend(Double.random(in: 40...120), "Transport", "Bus fare", cash, day) }
    if Int.random(in: 0..<5) == 0 { spend(Double.random(in: 250...600), "Transport", "Taxi", khalti, day) }
    if Int.random(in: 0..<4) == 0 { spend(Double.random(in: 900...3500), "Groceries", "Supermarket", bank, day) }
    if Int.random(in: 0..<5) == 0 { spend(Double.random(in: 150...600), "Groceries", "Vegetables", cash, day) }
    if weekend, Bool.random() { spend(Double.random(in: 1200...4500), "Food & Dining", "Dinner out", bank, day, hour: 20) }
    if weekend, Int.random(in: 0..<4) == 0 { spend(Double.random(in: 1500...7000), "Shopping", "Clothes", bank, day) }
    if Int.random(in: 0..<14) == 0 { spend(Double.random(in: 400...2500), "Health", "Pharmacy", cash, day) }
    if Int.random(in: 0..<9) == 0 { spend(Double.random(in: 400...1500), "Fun", "Movie", esewa, day) }
    if Int.random(in: 0..<40) == 0 { spend(Double.random(in: 6000...18000), "Travel", "Pokhara trip", bank, day) }
    if Int.random(in: 0..<30) == 0 { spend(Double.random(in: 800...3000), "Education", "Course", khalti, day) }

    day = cal.date(byAdding: .day, value: 1, to: day)!
}

// Loans: lent to friends (one overdue, one partly repaid), borrowed from family.
func ago(_ days: Int) -> Date { at(cal.date(byAdding: .day, value: -days, to: today)!, 18) }
var l1 = Loan(direction: .lent, person: "Suman Shrestha", amount: 15000, date: ago(62), note: "Laptop repair", walletID: bank)
l1.dueDate = cal.date(byAdding: .day, value: 20, to: today)
l1.repayments = [Repayment(amount: 5000, date: ago(30)), Repayment(amount: 4000, date: ago(6), walletID: cash)]
var l2 = Loan(direction: .lent, person: "Bibek", amount: 3000, date: ago(25), walletID: cash)
l2.dueDate = cal.date(byAdding: .day, value: -4, to: today)
var l3 = Loan(direction: .borrowed, person: "Dai", amount: 20000, date: ago(45), note: "Bike service", walletID: bank)
l3.repayments = [Repayment(amount: 10000, date: ago(14))]
let l4 = Loan(direction: .lent, person: "Anisha", amount: 2500, date: ago(80),
              repayments: [Repayment(amount: 2500, date: ago(50))], walletID: esewa)
loans = [l1, l2, l3, l4]

let encoder = JSONEncoder()
encoder.dateEncodingStrategy = .iso8601
encoder.outputFormatting = .prettyPrinted
let snapshot = Snapshot(categories: Category.defaults,
                        transactions: transactions.sorted { $0.date > $1.date },
                        loans: loans.sorted { $0.date > $1.date },
                        wallets: wallets,
                        transfers: transfers.sorted { $0.date > $1.date })
try encoder.encode(snapshot).write(to: dir.appendingPathComponent("data.json"))
print("Wrote \(transactions.count) transactions, \(transfers.count) transfers, \(loans.count) loans to \(dir.path)/data.json")
