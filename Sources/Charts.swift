import SwiftUI
import Charts

private let cal = Calendar.current

private func moneyAxis() -> some AxisContent {
    AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { value in
        AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5)).foregroundStyle(Palette.hairline)
        AxisValueLabel {
            if let v = value.as(Double.self) { Text(Money.compact(v)).monospacedDigit() }
        }
    }
}

// MARK: - Spending pace

/// Cumulative spending through the period, against the previous period and a straight-line projection.
struct PaceChart: View {
    let report: Report
    var height: CGFloat = 210
    @State private var hover: Date?

    var body: some View {
        let r = report
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 14) {
                LegendDot(color: Palette.expense, label: r.range.period.label)
                if !r.pacePrevious.isEmpty { LegendDot(color: Palette.neutral, label: r.range.period.previousLabel.capitalizedFirst) }
                if !r.projection.isEmpty { LegendDot(color: Palette.expense, label: "Projection", dashed: true) }
            }
            Chart {
                ForEach(r.pacePrevious) { p in
                    LineMark(x: .value("Day", p.date, unit: .day), y: .value("Spent", p.value), series: .value("Series", "Previous"))
                        .foregroundStyle(Palette.neutral.opacity(0.7))
                        .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round))
                }
                ForEach(r.paceCurrent) { p in
                    AreaMark(x: .value("Day", p.date, unit: .day), y: .value("Spent", p.value))
                        .foregroundStyle(LinearGradient(colors: [Palette.expense.opacity(0.18), Palette.expense.opacity(0.01)],
                                                        startPoint: .top, endPoint: .bottom))
                    LineMark(x: .value("Day", p.date, unit: .day), y: .value("Spent", p.value), series: .value("Series", "Current"))
                        .foregroundStyle(Palette.expense)
                        .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round))
                }
                ForEach(r.projection) { p in
                    LineMark(x: .value("Day", p.date, unit: .day), y: .value("Spent", p.value), series: .value("Series", "Projection"))
                        .foregroundStyle(Palette.expense.opacity(0.7))
                        .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, dash: [4, 4]))
                }
                if let hover, let day = Optional(cal.startOfDay(for: hover)), r.range.full.holds(day) {
                    RuleMark(x: .value("Day", day, unit: .day))
                        .foregroundStyle(Palette.axis)
                        .lineStyle(StrokeStyle(lineWidth: 1))
                        .annotation(position: .top, spacing: 4, overflowResolution: .init(x: .fit(to: .chart), y: .disabled)) {
                            tooltip(for: day)
                        }
                    if let p = r.paceCurrent.first(where: { $0.date == day }) {
                        PointMark(x: .value("Day", p.date, unit: .day), y: .value("Spent", p.value))
                            .foregroundStyle(Palette.expense)
                            .symbolSize(60)
                    }
                }
            }
            .chartXSelection(value: $hover)
            .chartYAxis { moneyAxis() }
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 6)) { _ in
                    AxisTick(stroke: StrokeStyle(lineWidth: 0.5)).foregroundStyle(Palette.axis)
                    if r.range.totalDays > 62 {
                        AxisValueLabel(format: .dateTime.month(.abbreviated))
                    } else {
                        AxisValueLabel(format: .dateTime.day())
                    }
                }
            }
            .chartXScale(domain: r.range.full.start...cal.adding(days: max(r.range.totalDays - 1, 1), to: r.range.full.start))
            .frame(height: height)
        }
    }

    private func tooltip(for day: Date) -> some View {
        var rows: [ChartTooltip.Row] = []
        if let p = report.paceCurrent.first(where: { $0.date == day }) {
            rows.append(.init(color: Palette.expense, label: report.range.period.label, value: Money.string(p.value)))
            if let d = report.daily[day] { rows.append(.init(color: .clear, label: "That day", value: Money.string(d))) }
        }
        if let p = report.pacePrevious.first(where: { $0.date == day }) {
            rows.append(.init(color: Palette.neutral, label: report.range.period.previousLabel.capitalizedFirst, value: Money.string(p.value)))
        }
        return ChartTooltip(title: day.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()), rows: rows)
    }
}

// MARK: - Monthly trend

struct TrendChart: View {
    let months: [MonthPoint]
    var height: CGFloat = 230
    @State private var hover: Date?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 14) {
                LegendDot(color: Palette.income, label: "Income")
                LegendDot(color: Palette.expense, label: "Spending")
            }
            Chart {
                ForEach(months) { m in
                    BarMark(x: .value("Month", m.month, unit: .month), y: .value("Amount", m.income))
                        .foregroundStyle(Palette.income)
                        .cornerRadius(3)
                        .position(by: .value("Kind", "Income"), axis: .horizontal, span: .ratio(0.62))
                    BarMark(x: .value("Month", m.month, unit: .month), y: .value("Amount", m.expense))
                        .foregroundStyle(Palette.expense)
                        .cornerRadius(3)
                        .position(by: .value("Kind", "Spending"), axis: .horizontal, span: .ratio(0.62))
                }
                RuleMark(y: .value("Zero", 0)).foregroundStyle(Palette.axis).lineStyle(StrokeStyle(lineWidth: 1))
                if let hover, let m = months.first(where: { cal.isDate($0.month, equalTo: hover, toGranularity: .month) }) {
                    RectangleMark(x: .value("Month", m.month, unit: .month))
                        .foregroundStyle(Palette.well.opacity(0.7))
                        .zIndex(-1)
                        .annotation(position: .top, spacing: 2, overflowResolution: .init(x: .fit(to: .chart), y: .disabled)) {
                            ChartTooltip(title: m.month.formatted(.dateTime.month(.wide).year()), rows: [
                                .init(color: Palette.income, label: "Income", value: Money.string(m.income)),
                                .init(color: Palette.expense, label: "Spending", value: Money.string(m.expense)),
                                .init(color: .clear, label: m.net >= 0 ? "Saved" : "Overspent", value: Money.string(abs(m.net))),
                            ])
                        }
                }
            }
            .chartXSelection(value: $hover)
            .chartYAxis { moneyAxis() }
            .chartXAxis {
                AxisMarks(values: .stride(by: .month)) { _ in
                    AxisValueLabel(format: .dateTime.month(.abbreviated), centered: true)
                }
            }
            .frame(height: height)
        }
    }
}

// MARK: - Category donut

struct CategoryDonut: View {
    let totals: [CategoryTotal]
    let total: Double
    @State private var angle: Double?

    private struct Slice: Identifiable {
        let id: String
        let name: String
        let color: Color
        let amount: Double
    }

    /// Five biggest categories, the rest folded into one gray "Everything else" slice.
    private var slices: [Slice] {
        let positive = totals.filter { $0.amount > 0 }
        var out = positive.prefix(5).map {
            Slice(id: $0.id.uuidString, name: $0.category.name, color: Palette.color($0.category.color), amount: $0.amount)
        }
        let rest = positive.dropFirst(5).map(\.amount).reduce(0, +)
        if rest > 0 { out.append(Slice(id: "rest", name: "Everything else", color: Palette.neutral, amount: rest)) }
        return out
    }

    private func slice(at angle: Double?, in slices: [Slice]) -> Slice? {
        guard let angle else { return nil }
        var running = 0.0
        for s in slices {
            running += s.amount
            if angle <= running { return s }
        }
        return nil
    }

    var body: some View {
        let slices = slices
        let selected = slice(at: angle, in: slices)
        Chart(slices) { s in
            SectorMark(angle: .value("Amount", s.amount), innerRadius: .ratio(0.66), angularInset: 1.2)
                .cornerRadius(3)
                .foregroundStyle(s.color)
                .opacity(selected == nil || selected?.id == s.id ? 1 : 0.35)
        }
        .chartAngleSelection(value: $angle)
        .chartBackground { proxy in
            GeometryReader { geo in
                if let plot = proxy.plotFrame {
                    let frame = geo[plot]
                    VStack(spacing: 2) {
                        Text(selected?.name ?? "Total").font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        Text(Money.compactWithSymbol(selected?.amount ?? total))
                            .font(.title3.weight(.semibold))
                        if let s = selected, total > 0 {
                            Text(percent(s.amount / total)).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .frame(width: frame.width * 0.6)
                    .position(x: frame.midX, y: frame.midY)
                }
            }
        }
        .frame(width: 190, height: 190)
    }
}

// MARK: - Daily heatmap

/// One cell per day, shaded by how much was spent. A single month renders as a calendar;
/// longer periods render as week columns.
struct HeatmapView: View {
    let range: PeriodRange
    let daily: [Date: Double]
    @State private var width: CGFloat = 700

    private var weeks: [[Date?]] {
        var weeks: [[Date?]] = []
        var day = cal.dateInterval(of: .weekOfYear, for: range.full.start)!.start
        while day < range.full.end {
            var week: [Date?] = []
            for _ in 0..<7 {
                week.append(range.full.holds(day) ? day : nil)
                day = cal.adding(days: 1, to: day)
            }
            weeks.append(week)
        }
        return weeks
    }

    private var thresholds: [Double] {
        let values = daily.filter { range.full.holds($0.key) && $0.value > 0 }.map(\.value).sorted()
        guard !values.isEmpty else { return [] }
        return [0.25, 0.5, 0.75].map { values[Int(Double(values.count - 1) * $0)] }
    }

    private func level(_ value: Double, _ t: [Double]) -> Int {
        guard value > 0, t.count == 3 else { return 0 }
        return value <= t[0] ? 1 : value <= t[1] ? 2 : value <= t[2] ? 3 : 4
    }

    private func tip(_ day: Date) -> String {
        let amount = daily[day] ?? 0
        return "\(day.formatted(.dateTime.weekday(.wide).month(.abbreviated).day())) · " +
            (amount > 0 ? Money.string(amount) : "No spending")
    }

    var body: some View {
        let weeks = weeks
        let t = thresholds
        VStack(alignment: .leading, spacing: 10) {
            if weeks.count <= 6 {
                calendar(weeks, t)
            } else {
                strip(weeks, t)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(GeometryReader { geo in
                        Color.clear
                            .onAppear { width = geo.size.width }
                            .onChange(of: geo.size.width) { _, w in width = w }
                    })
            }
            HStack(spacing: 4) {
                Text("Less").font(.caption2).foregroundStyle(.secondary)
                ForEach(0..<5) { i in
                    RoundedRectangle(cornerRadius: 2).fill(Palette.heat[i]).frame(width: 10, height: 10)
                }
                Text("More").font(.caption2).foregroundStyle(.secondary)
            }
        }
    }

    private func calendar(_ weeks: [[Date?]], _ t: [Double]) -> some View {
        let today = cal.startOfDay(for: .now)
        return Grid(horizontalSpacing: 4, verticalSpacing: 4) {
            GridRow {
                ForEach(cal.orderedWeekdays, id: \.self) { wd in
                    Text(cal.veryShortWeekdaySymbols[wd - 1]).font(.caption2).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                }
            }
            ForEach(weeks.indices, id: \.self) { w in
                GridRow {
                    ForEach(0..<7, id: \.self) { d in
                        if let day = weeks[w][d] {
                            let amount = daily[day] ?? 0
                            let lvl = level(amount, t)
                            let future = day > today
                            RoundedRectangle(cornerRadius: 5, style: .continuous)
                                .fill(future ? Color.clear : Palette.heat[lvl])
                                .overlay {
                                    if future {
                                        RoundedRectangle(cornerRadius: 5, style: .continuous).strokeBorder(Palette.hairline)
                                    }
                                }
                                .overlay(alignment: .topLeading) {
                                    Text("\(cal.component(.day, from: day))")
                                        .font(.caption2.weight(cal.isDate(day, inSameDayAs: today) ? .bold : .regular))
                                        .foregroundStyle(lvl >= 3 ? Color.white.opacity(0.9) : future ? Color.secondary.opacity(0.5) : Color.secondary)
                                        .padding(4)
                                }
                                .overlay(alignment: .bottomTrailing) {
                                    if amount > 0 {
                                        Text(Money.compact(amount)).font(.system(size: 9, weight: .medium))
                                            .foregroundStyle(lvl >= 3 ? Color.white : Color.primary.opacity(0.75))
                                            .padding(4)
                                    }
                                }
                                .frame(height: 42)
                                .help(tip(day))
                        } else {
                            Color.clear.frame(height: 42)
                        }
                    }
                }
            }
        }
    }

    private func strip(_ weeks: [[Date?]], _ t: [Double]) -> some View {
        // Cells grow to fill the card width (weekday labels take ~32pt).
        let gap: CGFloat = weeks.count <= 28 ? 4 : 3
        let size = min(30, max(8, ((width - 32) / CGFloat(weeks.count)).rounded(.down) - gap))
        let today = cal.startOfDay(for: .now)
        return HStack(alignment: .top, spacing: gap) {
            VStack(alignment: .trailing, spacing: gap) {
                Text(" ").font(.caption2).frame(height: 14)
                ForEach(Array(cal.orderedWeekdays.enumerated()), id: \.offset) { i, wd in
                    Text(i % 2 == 0 ? cal.shortWeekdaySymbols[wd - 1] : "")
                        .font(.system(size: 9)).foregroundStyle(.secondary)
                        .frame(height: size)
                }
            }
            ForEach(weeks.indices, id: \.self) { w in
                VStack(spacing: gap) {
                    let firstDay = weeks[w].compactMap { $0 }.first
                    let monthStarts = weeks[w].compactMap { $0 }.first { cal.component(.day, from: $0) == 1 }
                    Text((w == 0 ? firstDay : monthStarts)?.formatted(.dateTime.month(.abbreviated)) ?? " ")
                        .font(.caption2).foregroundStyle(.secondary)
                        .fixedSize()
                        .frame(width: size, height: 14, alignment: .leading)
                    ForEach(0..<7, id: \.self) { d in
                        if let day = weeks[w][d] {
                            RoundedRectangle(cornerRadius: size > 12 ? 3 : 2, style: .continuous)
                                .fill(day > today ? Color.clear : Palette.heat[level(daily[day] ?? 0, t)])
                                .overlay {
                                    if day > today {
                                        RoundedRectangle(cornerRadius: 2).strokeBorder(Palette.hairline)
                                    }
                                }
                                .frame(width: size, height: size)
                                .help(tip(day))
                        } else {
                            Color.clear.frame(width: size, height: size)
                        }
                    }
                }
            }
        }
    }
}

extension String {
    var capitalizedFirst: String { prefix(1).uppercased() + dropFirst() }
}
