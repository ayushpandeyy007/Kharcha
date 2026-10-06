import SwiftUI

struct OverviewView: View {
    @Environment(Store.self) private var store
    @Environment(UIState.self) private var ui
    var scrolls = true

    var body: some View {
        let report = Report(transactions: store.transactions, categories: store.categories, period: .thisMonth)
        let r = report.range
        let content = VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Text(r.title).font(.largeTitle.weight(.bold))
                Text("Day \(r.elapsedDays) of \(r.totalDays) · \(r.totalDays - r.elapsedDays) days left")
                    .foregroundStyle(.secondary)
            }

            if store.transactions.isEmpty {
                HStack(spacing: 12) {
                    BalanceTile().frame(maxWidth: 300)
                    Spacer()
                }
                EmptyStateView().card()
            } else {
                tiles(report)
                HStack(alignment: .top, spacing: 16) {
                    VStack(alignment: .leading, spacing: 14) {
                        CardHeader(title: "Spending pace", subtitle: paceSubtitle(report))
                        PaceChart(report: report)
                    }
                    .frame(maxHeight: .infinity, alignment: .top)
                    .card()
                    .frame(minWidth: 380)

                    VStack(alignment: .leading, spacing: 14) {
                        CardHeader(title: "Top categories", subtitle: "This month")
                        if report.expenseTotals.contains(where: { $0.amount > 0 }) {
                            CategoryBars(totals: report.expenseTotals.filter { $0.amount > 0 }, limit: 5)
                        } else {
                            Text("No spending yet this month.").foregroundStyle(.secondary)
                        }
                    }
                    .frame(maxHeight: .infinity, alignment: .top)
                    .card()
                    .frame(width: 320)
                }
                .fixedSize(horizontal: false, vertical: true)
                if !store.portfolio.isEmpty { portfolio }
                if store.loans.contains(where: { !$0.isSettled }) { loans }
                recent
            }
        }
        .padding(24)
        if scrolls { ScrollView { content } } else { content }
    }

    private func tiles(_ report: Report) -> some View {
        let cal = Calendar.current
        let today = report.daily[cal.startOfDay(for: .now)] ?? 0
        let suffix = report.range.shortCompareLabel
        return HStack(spacing: 12) {
            BalanceTile()
            StatTile(title: "Spent", value: Money.string(report.spent)) {
                DeltaLabel(current: report.spent, previous: report.prevSpent, goodWhenUp: false, suffix: suffix)
                    .help("Compared with the same number of days \(report.range.period.previousLabel)")
            }
            StatTile(title: "Income", value: Money.string(report.earned)) {
                DeltaLabel(current: report.earned, previous: report.prevEarned, goodWhenUp: true, suffix: suffix)
            }
            StatTile(title: "Today", value: Money.string(today)) {
                Text("Avg \(Money.string(report.averagePerDay.rounded())) a day").font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private func paceSubtitle(_ report: Report) -> String {
        guard let projected = report.projected else { return "Cumulative spending this month" }
        let end = Calendar.current.adding(days: report.range.totalDays - 1, to: report.range.full.start)
        return "On pace for \(Money.string(projected.rounded())) by \(end.formatted(.dateTime.month(.abbreviated).day()))"
    }

    private var portfolio: some View {
        let p = store.portfolio
        func signed(_ v: Double) -> String { (v > 0.005 ? "+" : "") + Money.string(v) }
        return HStack(spacing: 28) {
            Label("Portfolio", systemImage: "chart.line.uptrend.xyaxis").font(.headline)
            VStack(alignment: .leading, spacing: 1) {
                Text("Market value").font(.caption).foregroundStyle(.secondary)
                Text(Money.string(p.marketValue)).fontWeight(.semibold).monospacedDigit()
            }
            VStack(alignment: .leading, spacing: 1) {
                Text("Today").font(.caption).foregroundStyle(.secondary)
                HStack(spacing: 6) {
                    Text(signed(p.dayGain)).fontWeight(.semibold).monospacedDigit()
                    GainPercent(value: p.dayGain, percent: p.dayPercent)
                }
            }
            VStack(alignment: .leading, spacing: 1) {
                Text("Unrealised").font(.caption).foregroundStyle(.secondary)
                HStack(spacing: 6) {
                    Text(signed(p.unrealised)).fontWeight(.semibold).monospacedDigit()
                    GainPercent(value: p.unrealised, percent: p.unrealisedPercent)
                }
            }
            Spacer()
            Button("View portfolio") { ui.section = .portfolio }.buttonStyle(.link)
        }
        .card(padding: 14)
    }

    private var loans: some View {
        let owedToYou = store.outstanding(.lent)
        let youOwe = store.outstanding(.borrowed)
        let overdue = store.loans.filter { $0.isOverdue() }.count
        return HStack(spacing: 28) {
            Label("Loans", systemImage: "person.2").font(.headline)
            if owedToYou > 0 {
                VStack(alignment: .leading, spacing: 1) {
                    Text("Owed to you").font(.caption).foregroundStyle(.secondary)
                    Text(Money.string(owedToYou)).fontWeight(.semibold).monospacedDigit()
                }
            }
            if youOwe > 0 {
                VStack(alignment: .leading, spacing: 1) {
                    Text("You owe").font(.caption).foregroundStyle(.secondary)
                    Text(Money.string(youOwe)).fontWeight(.semibold).monospacedDigit()
                }
            }
            if overdue > 0 {
                Label("\(overdue) overdue", systemImage: "exclamationmark.circle.fill")
                    .font(.callout).foregroundStyle(Palette.bad)
            }
            Spacer()
            Button("View loans") { ui.section = .loans }.buttonStyle(.link)
        }
        .card(padding: 14)
    }

    private var recent: some View {
        VStack(alignment: .leading, spacing: 10) {
            CardHeader(title: "Recent") {
                Button("See all") { ui.section = .transactions }
                    .buttonStyle(.link)
            }
            VStack(spacing: 0) {
                ForEach(Array(store.transactions.prefix(6).enumerated()), id: \.element.id) { i, t in
                    if i > 0 { Divider().padding(.leading, 38) }
                    TransactionRow(transaction: t, category: store.category(t.categoryID), wallet: store.wallet(t.walletID), showsDate: true)
                        .padding(.vertical, 6)
                        .contentShape(Rectangle())
                        .onTapGesture(count: 2) { ui.editor = EditorTarget(transaction: t) }
                }
            }
        }
        .card()
    }
}
