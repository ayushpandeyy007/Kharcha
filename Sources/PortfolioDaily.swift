import SwiftUI
import Charts

/// Day-by-day history of your portfolio, one entry per trading day you fetched prices.
struct PortfolioDailyView: View {
    @Environment(Store.self) private var store
    var scrolls = true

    var body: some View {
        if scrolls { ScrollView { content } } else { content }
    }

    private var content: some View {
        let days = store.days
        return VStack(alignment: .leading, spacing: 16) {
            if days.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    CardHeader(title: "No daily history yet")
                    Text("Click Fetch Prices after the market closes. Each fetch saves that day's close, and your day-by-day history builds from there.")
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .card()
            } else {
                summary(days)
                if days.count >= 2 {
                    HStack(alignment: .top, spacing: 16) {
                        VStack(alignment: .leading, spacing: 12) {
                            CardHeader(title: "Value by day",
                                       subtitle: "Market value at each close · invested \(Money.string(days.last!.cost))")
                            ValueChart(days: days)
                        }
                        .card()
                        VStack(alignment: .leading, spacing: 12) {
                            CardHeader(title: "Day's gain", subtitle: "How much your holdings moved each day")
                            DayGainChart(days: days)
                        }
                        .card()
                    }
                } else {
                    Label("This is your first saved day. Fetch prices on the next trading days to see charts and trends here.",
                          systemImage: "calendar.badge.plus")
                        .foregroundStyle(.secondary)
                }
                log(days)
            }
        }
        .padding(16)
    }

    private func summary(_ days: [DayRecord]) -> some View {
        let up = days.filter { $0.dayGain > 0.005 }.count
        let down = days.filter { $0.dayGain < -0.005 }.count
        let best = days.max { $0.dayGain < $1.dayGain }
        let worst = days.min { $0.dayGain < $1.dayGain }
        let first = days.first!, last = days.last!
        let change = last.value - first.previousValue
        return HStack(spacing: 12) {
            StatTile(title: "Days recorded", value: "\(days.count)") {
                Text("\(up) up · \(down) down · \(days.count - up - down) flat").font(.caption).foregroundStyle(.secondary)
            }
            if let best {
                StatTile(title: "Best day", value: signed(best.dayGain)) {
                    Text(best.date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated)))
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            if let worst, days.count > 1 {
                StatTile(title: "Worst day", value: signed(worst.dayGain)) {
                    Text(worst.date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated)))
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            StatTile(title: "Since first record", value: signed(change)) {
                GainPercent(value: change, percent: first.previousValue > 0 ? change / first.previousValue : nil)
            }
        }
    }

    private func log(_ days: [DayRecord]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            CardHeader(title: "Each day", subtitle: "Newest first")
            VStack(spacing: 0) {
                ForEach(Array(days.reversed().enumerated()), id: \.element.id) { i, day in
                    if i > 0 { Divider() }
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(alignment: .firstTextBaseline) {
                            Text(day.date.formatted(.dateTime.weekday(.wide).day().month(.wide).year()))
                                .fontWeight(.medium)
                            Spacer()
                            Text(Money.string(day.value)).monospacedDigit()
                            Text(signed(day.dayGain))
                                .monospacedDigit()
                                .foregroundStyle(tone(day.dayGain))
                                .frame(minWidth: 110, alignment: .trailing)
                            GainPercent(value: day.dayGain, percent: day.dayPercent)
                                .frame(minWidth: 70, alignment: .trailing)
                        }
                        // Each stock's move that day.
                        HStack(spacing: 6) {
                            ForEach(day.positions.sorted { $0.symbol < $1.symbol }, id: \.symbol) { p in
                                let change = p.previousClose > 0 ? NSDecimalNumber(decimal: (p.close - p.previousClose) / p.previousClose).doubleValue : 0
                                let amount = NSDecimalNumber(decimal: p.shares * (p.close - p.previousClose)).doubleValue
                                HStack(spacing: 4) {
                                    Text(p.symbol).fontWeight(.semibold)
                                    Text((change > 0 ? "+" : "") + change.formatted(.percent.precision(.fractionLength(2))))
                                        .foregroundStyle(tone(change))
                                }
                                .font(.caption)
                                .monospacedDigit()
                                .padding(.horizontal, 7).padding(.vertical, 3)
                                .background(Palette.well, in: Capsule())
                                .help("\(p.symbol): Rs \(Money.plain(NSDecimalNumber(decimal: p.close).doubleValue)) close, " +
                                      "\(amount > 0 ? "+" : "")\(Money.string(amount)) on your \(Money.plain(NSDecimalNumber(decimal: p.shares).doubleValue, decimals: 0)) shares")
                            }
                        }
                    }
                    .padding(.vertical, 10)
                }
            }
        }
        .card()
    }

    private func signed(_ v: Double) -> String { (v > 0.005 ? "+" : "") + Money.string(v) }
    private func tone(_ v: Double) -> Color { abs(v) < 0.00005 ? .secondary : v > 0 ? Palette.good : Palette.bad }
}

private struct ValueChart: View {
    let days: [DayRecord]
    @State private var hover: Date?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Chart {
                ForEach(days) { d in
                    LineMark(x: .value("Day", d.date, unit: .day), y: .value("Rs", d.value), series: .value("Series", "Value"))
                        .foregroundStyle(Palette.slots[0])
                        .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round))
                    PointMark(x: .value("Day", d.date, unit: .day), y: .value("Rs", d.value))
                        .foregroundStyle(Palette.slots[0]).symbolSize(24)
                }
                if let hover, let d = days.first(where: { Calendar.current.isDate($0.date, inSameDayAs: hover) }) {
                    RuleMark(x: .value("Day", d.date, unit: .day))
                        .foregroundStyle(Palette.axis)
                        .annotation(position: .top, spacing: 4, overflowResolution: .init(x: .fit(to: .chart), y: .disabled)) {
                            ChartTooltip(title: d.date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated)), rows: [
                                .init(color: Palette.slots[0], label: "Value", value: Money.string(d.value)),
                                .init(color: .clear, label: "Day's gain", value: (d.dayGain > 0 ? "+" : "") + Money.string(d.dayGain)),
                            ])
                        }
                }
            }
            .chartXSelection(value: $hover)
            .chartYScale(domain: .automatic(includesZero: false))
            .chartYAxis {
                AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { v in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5)).foregroundStyle(Palette.hairline)
                    AxisValueLabel { if let x = v.as(Double.self) { Text(Money.compact(x)) } }
                }
            }
            .chartXAxis { AxisMarks(values: .automatic(desiredCount: 6)) { _ in AxisValueLabel(format: .dateTime.day().month(.abbreviated)) } }
            .frame(height: 222)
        }
    }
}

private struct DayGainChart: View {
    let days: [DayRecord]
    @State private var hover: Date?

    var body: some View {
        Chart {
            ForEach(days) { d in
                BarMark(x: .value("Day", d.date, unit: .day), y: .value("Gain", d.dayGain), width: .ratio(0.5))
                    .foregroundStyle(d.dayGain >= 0 ? Palette.good : Palette.bad)
                    .cornerRadius(3)
            }
            RuleMark(y: .value("Zero", 0)).foregroundStyle(Palette.axis)
            if let hover, let d = days.first(where: { Calendar.current.isDate($0.date, inSameDayAs: hover) }) {
                RuleMark(x: .value("Day", d.date, unit: .day))
                    .foregroundStyle(.clear)
                    .annotation(position: .top, spacing: 4, overflowResolution: .init(x: .fit(to: .chart), y: .disabled)) {
                        ChartTooltip(title: d.date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated)), rows: [
                            .init(color: d.dayGain >= 0 ? Palette.good : Palette.bad, label: "Day's gain",
                                  value: (d.dayGain > 0 ? "+" : "") + Money.string(d.dayGain)),
                        ])
                    }
            }
        }
        .chartXSelection(value: $hover)
        .chartYAxis {
            AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { v in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5)).foregroundStyle(Palette.hairline)
                AxisValueLabel { if let x = v.as(Double.self) { Text(Money.compact(x)) } }
            }
        }
        .chartXAxis { AxisMarks(values: .automatic(desiredCount: 6)) { _ in AxisValueLabel(format: .dateTime.day().month(.abbreviated)) } }
        .frame(height: 222)
    }
}
