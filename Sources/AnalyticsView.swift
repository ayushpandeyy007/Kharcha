import SwiftUI

struct AnalyticsView: View {
    @Environment(Store.self) private var store
    @AppStorage("analyticsPeriod") private var period: Period = .thisMonth
    var scrolls = true

    var body: some View {
        let report = Report(transactions: store.transactions, categories: store.categories, period: period)
        let content = VStack(alignment: .leading, spacing: 16) {
            // One filter row scopes everything below it.
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Analytics").font(.largeTitle.weight(.bold))
                    Text(report.range.title).foregroundStyle(.secondary)
                }
                Spacer()
                Picker("Period", selection: $period) {
                    ForEach(Period.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
            }

            if store.transactions.isEmpty {
                EmptyStateView().card()
            } else {
                summary(report)
                if !report.insights.isEmpty { insights(report) }
                categories(report)
                VStack(alignment: .leading, spacing: 14) {
                    CardHeader(title: "Daily spending", subtitle: "Stronger color = more spent · hover a day for the amount")
                    HeatmapView(range: report.range, daily: report.daily)
                }
                .card()
                VStack(alignment: .leading, spacing: 14) {
                    CardHeader(title: "Monthly trend", subtitle: "Last 12 months")
                    TrendChart(months: Report.monthly(store.transactions))
                }
                .card()
            }
        }
        .padding(24)
        if scrolls { ScrollView { content } } else { content }
    }

    private func summary(_ r: Report) -> some View {
        let suffix = r.range.shortCompareLabel
        return HStack(spacing: 12) {
            StatTile(title: "Spent", value: Money.string(r.spent)) {
                DeltaLabel(current: r.spent, previous: r.prevSpent, goodWhenUp: false, suffix: suffix)
                    .help("Compared with \(r.range.compareLabel.dropFirst(3))")
            }
            StatTile(title: "Income", value: Money.string(r.earned)) {
                DeltaLabel(current: r.earned, previous: r.prevEarned, goodWhenUp: true, suffix: suffix)
            }
            StatTile(title: r.saved >= 0 ? "Saved" : "Overspent", value: Money.string(abs(r.saved))) {
                if let rate = r.savingsRate, rate >= 0 {
                    Text("\(percent(rate)) of income").font(.caption).foregroundStyle(.secondary)
                } else {
                    Text(r.earned > 0 ? "More than you earned" : "No income logged")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }

    private func insights(_ r: Report) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            CardHeader(title: "Insights")
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 20, alignment: .topLeading),
                                GridItem(.flexible(), spacing: 20, alignment: .topLeading)],
                      alignment: .leading, spacing: 14) {
                ForEach(r.insights) { insight in
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: insight.icon)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(insight.tone.color)
                            .frame(width: 30, height: 30)
                            .background(insight.tone.color.opacity(0.12), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(insight.title).font(.callout.weight(.medium))
                            Text(insight.detail).font(.caption).foregroundStyle(.secondary)
                        }
                        .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
        .card()
    }

    private func categories(_ r: Report) -> some View {
        let totals = r.expenseTotals.filter { $0.amount > 0 }
        return VStack(alignment: .leading, spacing: 16) {
            CardHeader(title: "Spending by category", subtitle: "Hover the ring for details")
            if totals.isEmpty {
                Text("No spending in this period.").foregroundStyle(.secondary)
            } else {
                HStack(alignment: .center, spacing: 32) {
                    CategoryDonut(totals: totals, total: r.spent)
                    CategoryBars(totals: totals, limit: 6)
                }
            }
        }
        .card()
    }
}
