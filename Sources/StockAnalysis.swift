import SwiftUI

/// Plain facts about each holding: weight, gain, 52-week range, averages, break-even.
/// It describes, it doesn't recommend: there are no buy or sell signals here.
struct StockAnalysisView: View {
    let summary: PortfolioSummary
    var scrolls = true

    var body: some View {
        if scrolls { ScrollView { content } } else { content }
    }

    private var content: some View {
        let total = summary.marketValue
        return VStack(alignment: .leading, spacing: 16) {
                facts(total: total)

                VStack(alignment: .leading, spacing: 12) {
                    CardHeader(title: "Allocation", subtitle: "Share of your portfolio's market value")
                    ForEach(summary.holdings) { h in
                        let weight = total > 0 ? h.marketValue / total : 0
                        HStack(spacing: 10) {
                            Text(h.symbol).fontWeight(.semibold).frame(width: 70, alignment: .leading)
                            GeometryReader { geo in
                                ZStack(alignment: .leading) {
                                    Capsule().fill(Palette.well)
                                    Capsule().fill(Palette.slots[0]).frame(width: max(4, geo.size.width * weight))
                                }
                            }
                            .frame(height: 6)
                            Text(percent(weight)).monospacedDigit().frame(width: 44, alignment: .trailing)
                            Text(Money.string(h.marketValue)).monospacedDigit().foregroundStyle(.secondary)
                                .frame(width: 120, alignment: .trailing)
                        }
                    }
                }
                .card()

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 320), spacing: 12)], spacing: 12) {
                    ForEach(summary.holdings) { h in
                        HoldingFacts(holding: h, weight: total > 0 ? h.marketValue / total : 0)
                    }
                }

                Label("These are facts from the latest fetched prices, not advice. Kharcha doesn't tell you what to buy or sell. For that, talk to a SEBON-registered investment adviser.",
                      systemImage: "info.circle")
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(16)
    }

    private func facts(total: Double) -> some View {
        let hs = summary.holdings
        var lines: [(String, String)] = []
        if let top = hs.max(by: { $0.marketValue < $1.marketValue }), total > 0 {
            lines.append(("chart.pie", "Biggest holding: \(top.symbol), \(percent(top.marketValue / total)) of your portfolio"))
        }
        if let worst = hs.filter({ $0.unrealised < 0 }).min(by: { ($0.unrealisedPercent ?? 0) < ($1.unrealisedPercent ?? 0) }),
           let pct = worst.unrealisedPercent {
            lines.append(("arrow.down.right", "Biggest unrealised loss: \(worst.symbol), \(signedPercent(pct)) (\(Money.string(worst.unrealised)))"))
        }
        if let best = hs.filter({ $0.unrealised > 0 }).max(by: { ($0.unrealisedPercent ?? 0) < ($1.unrealisedPercent ?? 0) }),
           let pct = best.unrealisedPercent {
            lines.append(("arrow.up.right", "Biggest unrealised gain: \(best.symbol), \(signedPercent(pct)) (+\(Money.string(best.unrealised)))"))
        }
        let ranged = hs.compactMap { h in h.rangePosition.map { (h, $0) } }
        if let low = ranged.min(by: { $0.1 < $1.1 }) {
            lines.append(("arrow.down.to.line", "Closest to its 52-week low: \(low.0.symbol), at \(percent(low.1)) of its low–high range"))
        }
        if let high = ranged.max(by: { $0.1 < $1.1 }), ranged.count > 1 {
            lines.append(("arrow.up.to.line", "Closest to its 52-week high: \(high.0.symbol), at \(percent(high.1)) of its low–high range"))
        }
        return VStack(alignment: .leading, spacing: 10) {
            CardHeader(title: "At a glance")
            ForEach(lines, id: \.1) { icon, text in
                Label(text, systemImage: icon)
            }
            if ranged.isEmpty {
                Text("Click Fetch Prices to load 52-week ranges and average prices.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .card()
    }
}

private struct HoldingFacts: View {
    let holding: Holding
    let weight: Double

    var body: some View {
        let h = holding
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text(h.symbol).font(.title3.weight(.bold))
                Text("\(percent(weight)) of portfolio")
                    .font(.caption).foregroundStyle(.secondary)
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(Palette.well, in: Capsule())
                Spacer()
                if let close = h.close {
                    Text("Rs \(Money.plain(close))").fontWeight(.semibold).monospacedDigit()
                }
            }

            row("Your average cost", "Rs \(Money.plain(h.avgCost)) × \(Money.plain(h.shares, decimals: 0)) shares")

            if let q = h.quote, let close = h.close, let prev = h.previousClose, prev > 0 {
                let change = close / prev - 1
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Last trading day").foregroundStyle(.secondary)
                        Spacer()
                        Text("\(signedPercent(change))  (\(h.dayGain > 0 ? "+" : "")\(Money.string(h.dayGain)) on your shares)")
                            .monospacedDigit()
                            .foregroundStyle(abs(change) < 0.00005 ? Color.primary : change > 0 ? Palette.good : Palette.bad)
                    }
                    if let o = q.open.map(double), let hi = q.high.map(double), let lo = q.low.map(double) {
                        Text("Open \(Money.plain(o)) · High \(Money.plain(hi)) · Low \(Money.plain(lo))" +
                             (q.volume.map { " · Volume \(Money.plain(double($0), decimals: 0))" } ?? ""))
                            .font(.caption).foregroundStyle(.secondary).monospacedDigit()
                    }
                }
                .font(.callout)
            }

            HStack {
                Text("Unrealised").foregroundStyle(.secondary)
                Spacer()
                Text("\(h.unrealised > 0 ? "+" : "")\(Money.string(h.unrealised))" +
                     (h.unrealisedPercent.map { "  (\(signedPercent($0)))" } ?? ""))
                    .monospacedDigit()
                    .foregroundStyle(abs(h.unrealised) < 0.005 ? Color.primary : h.unrealised > 0 ? Palette.good : Palette.bad)
            }
            .font(.callout)

            if let close = h.close, h.avgCost > 0 {
                let move = h.avgCost / close - 1
                row("Break-even", abs(move) < 0.0005 ? "At your average cost"
                    : move > 0 ? "Price needs to rise \(percent(move, decimals: 1)) to Rs \(Money.plain(h.avgCost))"
                               : "Price is \(percent(-move / (1 + move), decimals: 1)) above your cost")
            }

            if let q = h.quote, let low = q.low52.map(double), let high = q.high52.map(double), high > low, let close = h.close {
                VStack(alignment: .leading, spacing: 6) {
                    Text("52-week range").font(.caption).foregroundStyle(.secondary)
                    RangeBar(low: low, high: high, value: close, marker: h.avgCost)
                    HStack {
                        Text("Low \(Money.plain(low))")
                        Spacer()
                        Text("High \(Money.plain(high))")
                    }
                    .font(.caption2).foregroundStyle(.secondary).monospacedDigit()
                    Text("\(percent(close / low - 1, decimals: 1)) above the low · \(percent(1 - close / high, decimals: 1)) below the high")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }

            if let q = h.quote, let close = h.close, q.avg120 != nil || q.avg180 != nil {
                VStack(alignment: .leading, spacing: 4) {
                    if let a = q.avg120.map(double) { row("vs 120-day average (\(Money.plain(a)))", signedPercent(close / a - 1)) }
                    if let a = q.avg180.map(double) { row("vs 180-day average (\(Money.plain(a)))", signedPercent(close / a - 1)) }
                }
            }

            if h.quote?.low52 == nil {
                Text("Fetch prices to see the 52-week range and averages.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .card()
    }

    private func row(_ title: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).foregroundStyle(.secondary)
            Spacer(minLength: 8)
            Text(value).multilineTextAlignment(.trailing).monospacedDigit()
        }
        .font(.callout)
    }

    private func double(_ d: Decimal) -> Double { NSDecimalNumber(decimal: d).doubleValue }
}

/// Low–high track with a dot for today's price and a tick for your average cost.
private struct RangeBar: View {
    let low: Double
    let high: Double
    let value: Double
    let marker: Double

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Palette.well).frame(height: 6)
                Rectangle().fill(Color.secondary).frame(width: 2, height: 14)
                    .offset(x: x(marker, geo.size.width) - 1)
                    .help("Your average cost: Rs \(Money.plain(marker))")
                Circle().fill(Palette.slots[0])
                    .overlay(Circle().strokeBorder(Palette.surface, lineWidth: 2))
                    .frame(width: 14, height: 14)
                    .offset(x: x(value, geo.size.width) - 7)
                    .help("Latest close: Rs \(Money.plain(value))")
            }
            .frame(height: 16)
        }
        .frame(height: 16)
        .accessibilityLabel("Price \(Money.plain(value)) in a 52-week range of \(Money.plain(low)) to \(Money.plain(high))")
    }

    private func x(_ v: Double, _ width: CGFloat) -> CGFloat {
        CGFloat(min(max((v - low) / (high - low), 0), 1)) * width
    }
}

extension Holding {
    /// Where today's close sits between the 52-week low (0) and high (1).
    var rangePosition: Double? {
        guard let q = quote, let close, let lo = q.low52, let hi = q.high52 else { return nil }
        let low = NSDecimalNumber(decimal: lo).doubleValue, high = NSDecimalNumber(decimal: hi).doubleValue
        guard high > low else { return nil }
        return min(max((close - low) / (high - low), 0), 1)
    }
}

private func signedPercent(_ x: Double) -> String {
    (x > 0.00005 ? "+" : "") + x.formatted(.percent.precision(.fractionLength(2)))
}
