// Writes ~14 months of realistic sample data for previewing the dashboards.
// Usage: swiftc Sources/Models.swift scripts/demo-data/main.swift -o /tmp/demo && /tmp/demo <dir>
// Then:  KHARCHA_DATA_DIR=<dir> build/Kharcha.app/Contents/MacOS/Kharcha
import Foundation

let dir = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

let cats = Dictionary(uniqueKeysWithValues: Category.defaults.map { ($0.name + "|" + $0.kind.rawValue, $0.id) })
func cat(_ name: String, _ kind: Kind = .expense) -> UUID { cats[name + "|" + kind.rawValue]! }

var rng = SystemRandomNumberGenerator()
let cal = Calendar.current
let today = cal.startOfDay(for: .now)
let start = cal.date(byAdding: .month, value: -14, to: cal.monthStart(today))!
var out: [Transaction] = []

func add(_ kind: Kind, _ amount: Double, _ category: UUID, _ note: String, _ day: Date, hour: Int = Int.random(in: 8...21)) {
    let date = cal.date(bySettingHour: hour, minute: Int.random(in: 0...59), second: 0, of: day)!
    out.append(Transaction(kind: kind, amount: Decimal(amount.rounded()), categoryID: category, note: note, date: date))
}

var day = start
while day <= today {
    let dom = cal.component(.day, from: day)
    let weekday = cal.component(.weekday, from: day)
    let weekend = weekday == 7 || weekday == 1

    if dom == 1 {
        add(.income, 85000, cat("Salary", .income), "Salary", day, hour: 9)
        add(.expense, 22000, cat("Rent & Home"), "Rent", day, hour: 10)
        add(.expense, 1299, cat("Bills"), "Internet", day)
    }
    if dom == 5 { add(.expense, Double.random(in: 1400...2600), cat("Bills"), "Electricity", day) }
    if dom == 15, Bool.random() { add(.income, Double.random(in: 8000...25000), cat("Freelance", .income), "Design project", day) }

    // Some days nothing at all.
    if Int.random(in: 0..<10, using: &rng) < (weekend ? 1 : 2) { day = cal.adding(days: 1, to: day); continue }

    if Bool.random() { add(.expense, Double.random(in: 120...260), cat("Food & Dining"), "Momo", day) }
    if Int.random(in: 0..<3) == 0 { add(.expense, Double.random(in: 90...180), cat("Food & Dining"), "Coffee", day) }
    if !weekend, Int.random(in: 0..<3) > 0 { add(.expense, Double.random(in: 40...120), cat("Transport"), "Bus fare", day) }
    if Int.random(in: 0..<5) == 0 { add(.expense, Double.random(in: 250...600), cat("Transport"), "Pathao", day) }
    if Int.random(in: 0..<4) == 0 { add(.expense, Double.random(in: 900...3500), cat("Groceries"), "Bhatbhateni", day) }
    if weekend, Bool.random() { add(.expense, Double.random(in: 1200...4500), cat("Food & Dining"), "Dinner out", day, hour: 20) }
    if weekend, Int.random(in: 0..<4) == 0 { add(.expense, Double.random(in: 1500...7000), cat("Shopping"), "Clothes", day) }
    if Int.random(in: 0..<14) == 0 { add(.expense, Double.random(in: 400...2500), cat("Health"), "Pharmacy", day) }
    if Int.random(in: 0..<9) == 0 { add(.expense, Double.random(in: 400...1500), cat("Fun"), "Movie", day) }
    if Int.random(in: 0..<40) == 0 { add(.expense, Double.random(in: 6000...18000), cat("Travel"), "Pokhara trip", day) }
    if Int.random(in: 0..<30) == 0 { add(.expense, Double.random(in: 800...3000), cat("Education"), "Course", day) }
    if Int.random(in: 0..<25) == 0 { add(.expense, Double.random(in: 100...900), cat("Other"), "", day) }

    day = cal.adding(days: 1, to: day)
}

extension Calendar {
    func monthStart(_ d: Date) -> Date { dateInterval(of: .month, for: d)!.start }
    func adding(days: Int, to d: Date) -> Date { date(byAdding: .day, value: days, to: d)! }
}

let encoder = JSONEncoder()
encoder.dateEncodingStrategy = .iso8601
encoder.outputFormatting = .prettyPrinted
let snapshot = Snapshot(categories: Category.defaults, transactions: out.sorted { $0.date > $1.date })
try encoder.encode(snapshot).write(to: dir.appendingPathComponent("data.json"))
print("Wrote \(out.count) transactions to \(dir.path)/data.json")
