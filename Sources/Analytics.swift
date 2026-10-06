import Foundation

enum Period: String, CaseIterable, Identifiable {
    case thisMonth, lastMonth, last3Months, thisYear

    var id: Self { self }

    var title: String {
        switch self {
        case .thisMonth: "This Month"
        case .lastMonth: "Last Month"
        case .last3Months: "3 Months"
        case .thisYear: "This Year"
        }
    }

    /// Used inside sentences: "On pace to spend Rs 40,000 this month".
    var noun: String {
        switch self {
        case .thisMonth: "this month"
        case .lastMonth: "last month"
        case .last3Months: "over 3 months"
        case .thisYear: "this year"
        }
    }

    /// Legend label for the current period: "This month", "Last 3 months".
    var label: String {
        switch self {
        case .thisMonth: "This month"
        case .lastMonth: "Last month"
        case .last3Months: "Last 3 months"
        case .thisYear: "This year"
        }
    }

    var previousLabel: String {
        switch self {
        case .thisMonth: "last month"
        case .lastMonth: "the month before"
        case .last3Months: "the 3 months before"
        case .thisYear: "last year"
        }
    }

    func range(now: Date = .now, calendar cal: Calendar = .current) -> PeriodRange {
        let month = cal.dateInterval(of: .month, for: now)!
        func back(_ n: Int, from d: Date) -> Date { cal.date(byAdding: .month, value: -n, to: d)! }

        let full: DateInterval
        let previousFull: DateInterval
        switch self {
        case .thisMonth:
            full = month
            previousFull = DateInterval(start: back(1, from: month.start), end: month.start)
        case .lastMonth:
            let start = back(1, from: month.start)
            full = DateInterval(start: start, end: month.start)
            previousFull = DateInterval(start: back(1, from: start), end: start)
        case .last3Months:
            let start = back(2, from: month.start)
            full = DateInterval(start: start, end: month.end)
            previousFull = DateInterval(start: back(3, from: start), end: start)
        case .thisYear:
            let year = cal.dateInterval(of: .year, for: now)!
            full = year
            previousFull = DateInterval(start: cal.date(byAdding: .year, value: -1, to: year.start)!, end: year.start)
        }
        return PeriodRange(period: self, full: full, previousFull: previousFull, now: now, calendar: cal)
    }
}

struct PeriodRange {
    let period: Period
    let full: DateInterval
    let previousFull: DateInterval
    /// The slice of `previousFull` that lines up with how far we are into `full`.
    let previous: DateInterval
    let totalDays: Int
    let elapsedDays: Int

    init(period: Period, full: DateInterval, previousFull: DateInterval, now: Date, calendar cal: Calendar) {
        self.period = period
        self.full = full
        self.previousFull = previousFull
        totalDays = cal.days(from: full.start, to: full.end)
        let tomorrow = cal.adding(days: 1, to: cal.startOfDay(for: now))
        elapsedDays = max(0, min(totalDays, cal.days(from: full.start, to: tomorrow)))
        let prevEnd = min(previousFull.end, cal.adding(days: elapsedDays, to: previousFull.start))
        previous = DateInterval(start: previousFull.start, end: max(previousFull.start, prevEnd))
    }

    var isOngoing: Bool { elapsedDays < totalDays }
    var compareLabel: String { isOngoing ? "vs same point \(period.previousLabel)" : "vs \(period.previousLabel)" }
    var shortCompareLabel: String { "vs \(period.previousLabel)" }

    var title: String {
        let end = full.end.addingTimeInterval(-1)
        if totalDays <= 31 { return full.start.formatted(.dateTime.month(.wide).year()) }
        return "\(full.start.formatted(.dateTime.month(.abbreviated).year())) – \(end.formatted(.dateTime.month(.abbreviated).year()))"
    }
}

struct CategoryTotal: Identifiable {
    let category: Category
    let amount: Double
    let previous: Double
    let share: Double

    var id: UUID { category.id }
    var change: Double? { previous > 0 ? (amount - previous) / previous : nil }
}

struct DayPoint: Identifiable {
    let date: Date
    let value: Double
    var id: Date { date }
}

struct MonthPoint: Identifiable {
    let month: Date
    let income: Double
    let expense: Double
    var net: Double { income - expense }
    var id: Date { month }
}

struct WeekdayAverage: Identifiable {
    let weekday: Int   // 1 = Sunday
    let average: Double
    var id: Int { weekday }
}

struct Insight: Identifiable {
    enum Tone { case neutral, good, bad }
    let icon: String
    let tone: Tone
    let title: String
    let detail: String
    var id: String { title }
}

/// Everything the dashboards show for one period, computed in a single pass.
struct Report {
    let range: PeriodRange
    let spent: Double
    let earned: Double
    let prevSpent: Double
    let prevEarned: Double
    let prevFullSpent: Double
    let expenseTotals: [CategoryTotal]
    let incomeTotals: [CategoryTotal]
    /// Expense per day (keyed by start of day) across the whole period.
    let daily: [Date: Double]
    let paceCurrent: [DayPoint]
    let pacePrevious: [DayPoint]
    let projection: [DayPoint]
    let weekdays: [WeekdayAverage]
    let insights: [Insight]
    let count: Int

    var saved: Double { earned - spent }
    var savingsRate: Double? { earned > 0 ? saved / earned : nil }
    var prevSavingsRate: Double? { prevEarned > 0 ? (prevEarned - prevSpent) / prevEarned : nil }
    var averagePerDay: Double { range.elapsedDays > 0 ? spent / Double(range.elapsedDays) : 0 }
    var projected: Double? { projection.last?.value }

    init(transactions: [Transaction], categories: [Category], period: Period, now: Date = .now) {
        let cal = Calendar.current
        let r = period.range(now: now, calendar: cal)
        range = r

        var spent = 0.0, earned = 0.0, prevSpent = 0.0, prevEarned = 0.0, prevFullSpent = 0.0
        var catNow: [UUID: Double] = [:], catPrev: [UUID: Double] = [:]
        var daily: [Date: Double] = [:], dailyPrev: [Date: Double] = [:]
        var largest: Transaction?
        var count = 0

        for t in transactions {
            let v = t.value
            if r.full.holds(t.date) {
                count += 1
                catNow[t.categoryID, default: 0] += v
                if t.kind == .expense {
                    spent += v
                    daily[cal.startOfDay(for: t.date), default: 0] += v
                    if v > (largest?.value ?? 0) { largest = t }
                } else {
                    earned += v
                }
            } else if r.previousFull.holds(t.date) {
                if t.kind == .expense {
                    prevFullSpent += v
                    dailyPrev[cal.startOfDay(for: t.date), default: 0] += v
                }
                if r.previous.holds(t.date) {
                    catPrev[t.categoryID, default: 0] += v
                    if t.kind == .expense { prevSpent += v } else { prevEarned += v }
                }
            }
        }

        self.spent = spent
        self.earned = earned
        self.prevSpent = prevSpent
        self.prevEarned = prevEarned
        self.prevFullSpent = prevFullSpent
        self.daily = daily
        self.count = count

        func totals(_ kind: Kind, total: Double) -> [CategoryTotal] {
            categories.filter { $0.kind == kind }
                .map { CategoryTotal(category: $0, amount: catNow[$0.id] ?? 0, previous: catPrev[$0.id] ?? 0,
                                     share: total > 0 ? (catNow[$0.id] ?? 0) / total : 0) }
                .filter { $0.amount > 0 || $0.previous > 0 }
                .sorted { $0.amount > $1.amount }
        }
        expenseTotals = totals(.expense, total: spent)
        incomeTotals = totals(.income, total: earned)

        // Cumulative spending, day by day. The previous period is laid over the current dates.
        var pace: [DayPoint] = [], running = 0.0
        for i in 0..<r.elapsedDays {
            let day = cal.adding(days: i, to: r.full.start)
            running += daily[day] ?? 0
            pace.append(DayPoint(date: day, value: running))
        }
        paceCurrent = pace

        var prevPace: [DayPoint] = [], prevRunning = 0.0
        let prevDays = min(r.totalDays, cal.days(from: r.previousFull.start, to: r.previousFull.end))
        for i in 0..<prevDays {
            prevRunning += dailyPrev[cal.adding(days: i, to: r.previousFull.start)] ?? 0
            prevPace.append(DayPoint(date: cal.adding(days: i, to: r.full.start), value: prevRunning))
        }
        pacePrevious = prevFullSpent > 0 ? prevPace : []

        // Forecast = spent so far + remaining days at your usual daily rate. The rate comes from recent
        // history, and for monthly views skips big one-offs (rent, a trip) so day-1 bills don't explode it.
        var typicalDaily = 0.0
        if r.isOngoing, r.elapsedDays > 0, let last = pace.last {
            let tomorrow = cal.adding(days: 1, to: cal.startOfDay(for: now))
            let lookback = r.totalDays > 31 ? 90 : 30
            let windowStart = cal.adding(days: -lookback, to: tomorrow)
            let recent = transactions.filter { $0.kind == .expense && $0.date >= windowStart && $0.date < tomorrow }
            let recentTotal = recent.reduce(0) { $0 + $1.value }
            let typical = r.totalDays > 31 ? recentTotal
                : recent.filter { $0.value < recentTotal * 0.1 }.reduce(0) { $0 + $1.value }
            let oldest = transactions.lazy.filter { $0.kind == .expense }.map(\.date).min() ?? now
            let historyDays = max(1, min(lookback, cal.days(from: oldest, to: tomorrow)))
            typicalDaily = typical / Double(historyDays)
            let end = cal.adding(days: r.totalDays - 1, to: r.full.start)
            projection = [last, DayPoint(date: end, value: running + typicalDaily * Double(r.totalDays - r.elapsedDays))]
        } else {
            projection = []
        }

        // Average spend per weekday over the days that have happened.
        var sums: [Int: (sum: Double, n: Int)] = [:]
        for i in 0..<r.elapsedDays {
            let day = cal.adding(days: i, to: r.full.start)
            let wd = cal.component(.weekday, from: day)
            let old = sums[wd] ?? (0, 0)
            sums[wd] = (old.sum + (daily[day] ?? 0), old.n + 1)
        }
        weekdays = cal.orderedWeekdays.map { wd in
            let s = sums[wd] ?? (0, 0)
            return WeekdayAverage(weekday: wd, average: s.n > 0 ? s.sum / Double(s.n) : 0)
        }

        // MARK: Insights
        var out: [Insight] = []
        let lookup = Dictionary(uniqueKeysWithValues: categories.map { ($0.id, $0) })

        if let projected = projection.last?.value {
            var detail = "Based on your usual \(Money.string(typicalDaily.rounded())) a day"
            var tone = Insight.Tone.neutral
            if prevFullSpent > 0 {
                let diff = (projected - prevFullSpent) / prevFullSpent
                detail = "\(percent(abs(diff))) \(diff >= 0 ? "more" : "less") than \(period.previousLabel) (\(Money.string(prevFullSpent)))"
                tone = diff > 0.05 ? .bad : diff < -0.05 ? .good : .neutral
            }
            out.append(Insight(icon: "chart.line.uptrend.xyaxis", tone: tone,
                               title: "On pace to spend \(Money.string(projected.rounded())) \(period.noun)", detail: detail))
        }

        if earned > 0 {
            let rate = (earned - spent) / earned
            if rate >= 0 {
                out.append(Insight(icon: "banknote", tone: rate >= 0.2 ? .good : .neutral,
                                   title: "You kept \(percent(rate)) of your income",
                                   detail: "Saved \(Money.string(earned - spent)) of \(Money.string(earned)) earned"))
            } else {
                out.append(Insight(icon: "exclamationmark.triangle", tone: .bad,
                                   title: "Spent \(Money.string(spent - earned)) more than you earned",
                                   detail: "Income \(Money.string(earned)) · Spending \(Money.string(spent))"))
            }
        } else if spent > 0 {
            out.append(Insight(icon: "tray", tone: .neutral, title: "No income logged \(period.noun)",
                               detail: "Add income to see how much you're saving"))
        }

        if let top = expenseTotals.first, top.amount > 0 {
            out.append(Insight(icon: top.category.icon, tone: .neutral,
                               title: "\(top.category.name) is your biggest expense",
                               detail: "\(Money.string(top.amount)) · \(percent(top.share)) of spending"))
        }

        let movers = expenseTotals.filter { $0.previous > 0 }
        if let up = movers.max(by: { $0.amount - $0.previous < $1.amount - $1.previous }),
           up.amount > up.previous, let change = up.change {
            out.append(Insight(icon: "arrow.up.right", tone: .bad,
                               title: "\(up.category.name) up \(percent(change))",
                               detail: "\(Money.string(up.amount)) vs \(Money.string(up.previous)) \(r.compareLabel.dropFirst(3))"))
        }
        if let down = movers.min(by: { $0.amount - $0.previous < $1.amount - $1.previous }),
           down.amount > 0, down.amount < down.previous, let change = down.change {
            out.append(Insight(icon: "arrow.down.right", tone: .good,
                               title: "\(down.category.name) down \(percent(abs(change)))",
                               detail: "\(Money.string(down.amount)) vs \(Money.string(down.previous)) \(r.compareLabel.dropFirst(3))"))
        }

        if r.elapsedDays >= 14, let top = weekdays.max(by: { $0.average < $1.average }), top.average > 0 {
            let rest = weekdays.filter { $0.weekday != top.weekday }
            let others = rest.map(\.average).reduce(0, +) / Double(max(rest.count, 1))
            let name = cal.weekdaySymbols[top.weekday - 1]
            out.append(Insight(icon: "calendar", tone: .neutral, title: "\(name)s are your priciest day",
                               detail: "Avg \(Money.string(top.average.rounded())) vs \(Money.string(others.rounded())) on other days"))
        }

        if r.elapsedDays >= 3, spent > 0 {
            let quiet = (0..<r.elapsedDays).filter { daily[cal.adding(days: $0, to: r.full.start)] == nil }.count
            out.append(Insight(icon: "leaf", tone: quiet > 0 ? .good : .neutral,
                               title: quiet == 1 ? "1 no-spend day" : "\(quiet) no-spend days",
                               detail: "Out of \(r.elapsedDays) days \(period.noun)"))
        }

        if let big = largest {
            let label = big.note.isEmpty ? (lookup[big.categoryID]?.name ?? "Other") : big.note
            out.append(Insight(icon: "flame", tone: .neutral, title: "Biggest expense: \(Money.string(big.value))",
                               detail: "\(label) · \(big.date.formatted(.dateTime.month(.abbreviated).day()))"))
        }

        insights = Array(out.prefix(4))
    }

    /// Income and expense for each of the last `months` months, oldest first.
    static func monthly(_ transactions: [Transaction], months: Int = 12, now: Date = .now) -> [MonthPoint] {
        let cal = Calendar.current
        let current = cal.monthStart(now)
        let starts = (0..<months).reversed().map { cal.date(byAdding: .month, value: -$0, to: current)! }
        guard let first = starts.first else { return [] }
        var income: [Date: Double] = [:], expense: [Date: Double] = [:]
        for t in transactions where t.date >= first {
            let m = cal.monthStart(t.date)
            if t.kind == .income { income[m, default: 0] += t.value } else { expense[m, default: 0] += t.value }
        }
        return starts.map { MonthPoint(month: $0, income: income[$0] ?? 0, expense: expense[$0] ?? 0) }
    }
}
