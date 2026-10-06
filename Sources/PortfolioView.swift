import SwiftUI

struct PortfolioView: View {
    @Environment(Store.self) private var store
    @Environment(UIState.self) private var ui
    @Environment(\.undoManager) private var undoManager
    @State private var sortOrder = [KeyPathComparator(\Holding.marketValue, order: .reverse)]
    @State private var selection: Holding.ID?
    @AppStorage("portfolioView") private var tab: Tab = .holdings

    enum Tab: String, CaseIterable, Identifiable {
        case holdings, daily, analysis
        var id: Self { self }
        var title: String { rawValue.capitalized }
    }

    var body: some View {
        let summary = store.portfolio
        if store.trades.isEmpty {
            ContentUnavailableView {
                Label("No stocks yet", systemImage: "chart.line.uptrend.xyaxis")
            } description: {
                Text("Add the NEPSE shares you own, then click Fetch Prices\nwhenever you want the latest closing prices.")
            } actions: {
                Button("Add Stock") { ui.portfolioSheet = .trade(symbol: nil, side: .buy) }
                    .buttonStyle(.borderedProminent)
            }
        } else {
            VStack(spacing: 0) {
                header(summary)
                Divider()
                if summary.isEmpty {
                    ContentUnavailableView("Everything is sold", systemImage: "checkmark.circle",
                                           description: Text("Your realised gain is shown above. Add a stock to start again."))
                } else {
                    switch tab {
                    case .holdings: table(summary.holdings.sorted(using: sortOrder))
                    case .daily: PortfolioDailyView()
                    case .analysis: StockAnalysisView(summary: summary)
                    }
                }
            }
        }
    }

    // MARK: Header

    private func header(_ p: PortfolioSummary) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center) {
                priceStatus
                Spacer()
                Picker("View", selection: $tab) {
                    ForEach(Tab.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
                Button {
                    Task { await store.refreshPrices() }
                } label: {
                    Label("Fetch Prices", systemImage: "arrow.down.circle")
                }
                .buttonStyle(.borderedProminent)
                .disabled(store.priceStatus == .updating)
                .help("Download today's NEPSE prices from \(PriceFeed.sourceName). Final after the market closes at 3 PM.")
                Button { ui.portfolioSheet = .trade(symbol: nil, side: .buy) } label: {
                    Label("Add Stock", systemImage: "plus")
                }
                Menu {
                    Button("Earlier Realised Gain…") { ui.portfolioSheet = .realisedBefore }
                    Button("Export Portfolio as CSV…") { Exporter.exportPortfolio(store) }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
            }
            HStack(spacing: 12) {
                StatTile(title: "Market value", value: Money.string(p.marketValue)) {
                    Text("Invested \(Money.string(p.cost))").font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                StatTile(title: "Day's gain", value: signed(p.dayGain)) { GainPercent(value: p.dayGain, percent: p.dayPercent) }
                StatTile(title: "Unrealised gain", value: signed(p.unrealised)) { GainPercent(value: p.unrealised, percent: p.unrealisedPercent) }
                StatTile(title: "Realised gain", value: signed(p.realised)) {
                    Text("From shares you sold").font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                StatTile(title: "Overall gain", value: signed(p.overall)) {
                    GainPercent(value: p.overall, percent: nil)
                }
            }
        }
        .padding(16)
    }

    @ViewBuilder
    private var priceStatus: some View {
        switch store.priceStatus {
        case .updating:
            HStack(spacing: 6) {
                ProgressView().controlSize(.small)
                Text("Fetching prices…").foregroundStyle(.secondary)
            }
        case .failed(let message):
            Label("Couldn't fetch prices: \(message)", systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(Palette.bad)
                .lineLimit(2)
        case .idle:
            if let asOf = store.quotes.values.map(\.asOf).max() {
                VStack(alignment: .leading, spacing: 1) {
                    Text("NEPSE closing prices for \(asOf.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated)))")
                    Text("From \(PriceFeed.sourceName)" +
                         (store.quotesCheckedAt.map { " · fetched \($0.formatted(.dateTime.day().month(.abbreviated).hour().minute()))" } ?? ""))
                        .font(.caption).foregroundStyle(.secondary)
                }
            } else {
                VStack(alignment: .leading, spacing: 1) {
                    Text("No prices yet")
                    Text("Click Fetch Prices to get the latest NEPSE closing prices.").font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: Table

    private func table(_ rows: [Holding]) -> some View {
        Table(rows, selection: $selection, sortOrder: $sortOrder) {
            TableColumn("Company", value: \.symbol) { h in
                Text(h.symbol).fontWeight(.semibold)
            }
            TableColumn("Latest Close", value: \.sortClose) { h in
                number(h.close.map { Money.plain($0) } ?? "—")
            }
            TableColumn("Shares", value: \.shares) { h in number(Money.plain(h.shares, decimals: 0)) }
            TableColumn("Avg Cost", value: \.avgCost) { h in number(Money.plain(h.avgCost)) }
            TableColumn("Cost Basis", value: \.cost) { h in number(Money.plain(h.cost)) }
            TableColumn("Unrealised", value: \.unrealised) { h in
                GainCell(value: h.unrealised, percent: h.unrealisedPercent)
            }
            TableColumn("Day's Gain", value: \.dayGain) { h in
                GainCell(value: h.dayGain, percent: h.dayPercent)
            }
            TableColumn("Market Value", value: \.marketValue) { h in number(Money.plain(h.marketValue)).fontWeight(.medium) }
        }
        .contextMenu(forSelectionType: Holding.ID.self) { ids in
            if let symbol = ids.first {
                Button("Details & History…") { ui.portfolioSheet = .detail(symbol) }
                Button("Buy More…") { ui.portfolioSheet = .trade(symbol: symbol, side: .buy) }
                Button("Sell…") { ui.portfolioSheet = .trade(symbol: symbol, side: .sell) }
                Divider()
                Button("Remove \(symbol)…", role: .destructive) { remove(symbol) }
            }
        } primaryAction: { ids in
            if let symbol = ids.first { ui.portfolioSheet = .detail(symbol) }
        }
        .onDeleteCommand { if let symbol = selection { remove(symbol) } }
    }

    private func number(_ s: String) -> Text {
        Text(s).monospacedDigit()
    }

    private func signed(_ value: Double) -> String {
        (value > 0.005 ? "+" : "") + Money.string(value)
    }

    /// Removes every trade of a symbol (undoable).
    private func remove(_ symbol: String) {
        let ids = Set(store.trades.filter { $0.symbol == symbol }.map(\.id))
        let removed = store.deleteTrades(ids)
        selection = nil
        let store = store
        undoManager?.registerUndo(withTarget: store) { target in
            MainActor.assumeIsolated { target.restoreTrades(removed) }
        }
        undoManager?.setActionName("Remove \(symbol)")
    }
}

extension Holding {
    var sortClose: Double { close ?? 0 }
}

/// "▲ 5.87%" in good/bad ink. The arrow and sign carry the meaning, not just the color.
struct GainPercent: View {
    let value: Double
    let percent: Double?

    var body: some View {
        let flat = abs(value) < 0.005
        HStack(spacing: 3) {
            Image(systemName: flat ? "equal" : value > 0 ? "arrowtriangle.up.fill" : "arrowtriangle.down.fill")
                .font(.system(size: 8))
            if let percent { Text(percent.formatted(.percent.precision(.fractionLength(2)))) }
            else { Text(flat ? "No change" : value > 0 ? "Up" : "Down") }
        }
        .font(.caption)
        .foregroundStyle(flat ? Color.secondary : value > 0 ? Palette.good : Palette.bad)
        .lineLimit(1)
    }
}

private struct GainCell: View {
    let value: Double
    let percent: Double?

    var body: some View {
        let flat = abs(value) < 0.005
        HStack(spacing: 4) {
            Text((value > 0.005 ? "+" : "") + Money.plain(value))
            if let percent {
                Text("(\(percent > 0 ? "+" : "")\(percent.formatted(.percent.precision(.fractionLength(2)))))")
                    .font(.caption)
            }
        }
        .monospacedDigit()
        .foregroundStyle(flat ? Color.secondary : value > 0 ? Palette.good : Palette.bad)
    }
}

// MARK: - Buy / sell

struct TradeForm: View {
    @Environment(Store.self) private var store
    let original: Trade?
    var onFinish: () -> Void

    @State private var side: Trade.Side
    @State private var symbol: String
    @State private var sharesText: String
    @State private var priceText: String
    @State private var date: Date
    @State private var walletID: UUID?
    @State private var note: String
    @FocusState private var priceFocused: Bool
    @FocusState private var symbolFocused: Bool

    init(original: Trade? = nil, symbol: String? = nil, side: Trade.Side = .buy, onFinish: @escaping () -> Void) {
        self.original = original
        self.onFinish = onFinish
        _side = State(initialValue: original?.side ?? side)
        _symbol = State(initialValue: original?.symbol ?? symbol ?? "")
        _sharesText = State(initialValue: original.map { NSDecimalNumber(decimal: $0.shares).stringValue } ?? "")
        _priceText = State(initialValue: original.map { NSDecimalNumber(decimal: $0.price).stringValue } ?? "")
        _date = State(initialValue: original?.date ?? .now)
        _walletID = State(initialValue: original?.walletID)
        _note = State(initialValue: original?.note ?? "")
    }

    private var cleanSymbol: String { symbol.trimmingCharacters(in: .whitespaces).uppercased() }
    private var shares: Decimal? { Money.parse(sharesText) }
    private var price: Decimal? { Money.parse(priceText) }
    private var owned: Double {
        // Shares held excluding this trade, so editing a sell doesn't count against itself.
        let others = store.trades.filter { $0.id != original?.id }
        return PortfolioSummary(trades: others, quotes: [:], realisedBefore: 0)
            .holdings.first { $0.symbol == cleanSymbol }?.shares ?? 0
    }
    private var tooMany: Bool {
        side == .sell && (shares.map { NSDecimalNumber(decimal: $0).doubleValue > owned + 0.000001 } ?? false)
    }

    private var suggestions: [String] {
        let typed = cleanSymbol
        guard !typed.isEmpty, store.quotes[typed] == nil else { return [] }
        let owned = store.knownSymbols.filter { $0.hasPrefix(typed) }
        let market = store.quotes.keys.filter { $0.hasPrefix(typed) && !owned.contains($0) }.sorted()
        return Array((owned + market).prefix(8))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(original != nil ? "Edit Trade" : side == .buy ? "Buy Shares" : "Sell Shares").font(.title3.weight(.semibold))

            Picker("Side", selection: $side) {
                ForEach(Trade.Side.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            VStack(alignment: .leading, spacing: 6) {
                TextField("Symbol — e.g. NABIL, NICA", text: $symbol)
                    .textFieldStyle(.roundedBorder)
                    .font(.title3)
                    .focused($symbolFocused)
                if !suggestions.isEmpty {
                    HStack(spacing: 6) {
                        ForEach(suggestions, id: \.self) { s in
                            Button(s) { symbol = s; priceFocused = true }
                                .buttonStyle(.bordered).controlSize(.small)
                        }
                    }
                }
                if let q = store.quotes[cleanSymbol] {
                    Text("Last close Rs \(Money.plain(NSDecimalNumber(decimal: q.close).doubleValue)) on \(q.asOf.formatted(.dateTime.day().month(.abbreviated)))")
                        .font(.caption).foregroundStyle(.secondary)
                } else if !cleanSymbol.isEmpty && !store.quotes.isEmpty && suggestions.isEmpty {
                    Label("\(cleanSymbol) isn't in the latest NEPSE price list. Check the symbol.", systemImage: "exclamationmark.triangle.fill")
                        .font(.caption).foregroundStyle(Palette.bad)
                }
            }

            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Shares").font(.caption).foregroundStyle(.secondary)
                    TextField("0", text: $sharesText)
                        .textFieldStyle(.roundedBorder)
                        .font(.title3)
                        .frame(width: 120)
                    if side == .sell {
                        Text("You own \(Money.plain(owned, decimals: 0))")
                            .font(.caption).foregroundStyle(tooMany ? Palette.bad : .secondary)
                    }
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text("Price per share").font(.caption).foregroundStyle(.secondary)
                    AmountField(text: $priceText, compact: true, focused: $priceFocused)
                }
            }
            Text(side == .buy ? "Include broker, SEBON and DP charges for an accurate average cost."
                              : "Use what you actually got per share after charges and tax.")
                .font(.caption).foregroundStyle(.secondary)

            if let shares, let price {
                Text("Total \(Money.string(shares * price))").fontWeight(.medium)
            }

            WalletPicker(title: side == .buy ? "Paid from" : "Received in", selection: $walletID,
                         noneLabel: "No wallet")

            TextField("Note (optional)", text: $note).textFieldStyle(.roundedBorder)

            HStack {
                DatePicker("Date", selection: $date, displayedComponents: .date)
                    .labelsHidden().datePickerStyle(.field)
                Spacer()
                Button("Cancel", role: .cancel, action: onFinish).keyboardShortcut(.cancelAction)
                Button(original == nil ? side.title : "Save", action: save)
                    .keyboardShortcut(.defaultAction)
                    .disabled(cleanSymbol.isEmpty || shares == nil || price == nil || tooMany)
            }
        }
        .onAppear {
            if original == nil {
                let saved = UserDefaults.standard.string(forKey: "lastWallet.stock")
                walletID = saved.flatMap(UUID.init(uuidString:)).flatMap { store.wallet($0)?.id }
                if cleanSymbol.isEmpty { symbolFocused = true } else { prefillPrice(); priceFocused = true }
            }
        }
        .onChange(of: symbol) { _, _ in prefillPrice() }
    }

    private func prefillPrice() {
        guard original == nil, priceText.isEmpty, let q = store.quotes[cleanSymbol] else { return }
        priceText = NSDecimalNumber(decimal: q.close).stringValue
    }

    private func save() {
        guard let shares, let price, !cleanSymbol.isEmpty, !tooMany else { NSSound.beep(); return }
        let cal = Calendar.current
        let time = cal.dateComponents([.hour, .minute, .second], from: original?.date ?? .now)
        let stamped = cal.date(bySettingHour: time.hour ?? 12, minute: time.minute ?? 0, second: time.second ?? 0, of: date) ?? date
        var trade = original ?? Trade(symbol: cleanSymbol, side: side, shares: shares, price: price, date: stamped)
        trade.symbol = cleanSymbol
        trade.side = side
        trade.shares = shares
        trade.price = price
        trade.date = stamped
        trade.walletID = walletID
        trade.note = note.trimmingCharacters(in: .whitespacesAndNewlines)
        if original == nil { store.addTrade(trade) } else { store.updateTrade(trade) }
        UserDefaults.standard.set(walletID?.uuidString ?? "none", forKey: "lastWallet.stock")
        onFinish()
    }
}

// MARK: - One holding: details, history, manual price

struct HoldingDetail: View {
    @Environment(Store.self) private var store
    let symbol: String
    var onClose: () -> Void

    private enum Mode: Equatable { case detail, trade(Trade.Side), edit(Trade) }
    @State private var mode: Mode = .detail
    @State private var editingPrice = false
    @State private var priceText = ""
    @FocusState private var priceFocused: Bool

    var body: some View {
        switch mode {
        case .detail: detail
        case .trade(let side): TradeForm(symbol: symbol, side: side) { mode = .detail }
        case .edit(let trade): TradeForm(original: trade) { mode = .detail }
        }
    }

    private var detail: some View {
        let holding = store.portfolio.holdings.first { $0.symbol == symbol }
        let history = store.trades.filter { $0.symbol == symbol }
        let fmt = Date.FormatStyle.dateTime.day().month(.abbreviated).year()
        return VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(symbol).font(.title2.weight(.bold))
                    if let h = holding {
                        Text("\(Money.plain(h.shares, decimals: 0)) shares · avg cost Rs \(Money.plain(h.avgCost))")
                            .foregroundStyle(.secondary)
                    } else {
                        Text("All shares sold").foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Button("Buy More") { mode = .trade(.buy) }
                Button("Sell") { mode = .trade(.sell) }.disabled(holding == nil)
            }

            if let h = holding {
                HStack(spacing: 24) {
                    stat("Market value", Money.string(h.marketValue))
                    stat("Unrealised", (h.unrealised > 0 ? "+" : "") + Money.string(h.unrealised))
                    stat("Day's gain", (h.dayGain > 0 ? "+" : "") + Money.string(h.dayGain))
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                if editingPrice {
                    HStack {
                        AmountField(text: $priceText, compact: true, focused: $priceFocused).frame(width: 200)
                        Button("Save Price") {
                            if let p = Money.parse(priceText) { store.setPrice(symbol, close: p) }
                            editingPrice = false
                        }
                        .keyboardShortcut(.defaultAction)
                        .disabled(Money.parse(priceText) == nil)
                        Button("Cancel") { editingPrice = false }
                    }
                } else {
                    HStack {
                        if let q = store.quotes[symbol] {
                            Text("Latest close Rs \(Money.plain(NSDecimalNumber(decimal: q.close).doubleValue)) · \(q.asOf.formatted(.dateTime.day().month(.abbreviated)))")
                        } else {
                            Text("No price yet").foregroundStyle(.secondary)
                        }
                        Button("Set Price…") {
                            priceText = store.quotes[symbol].map { NSDecimalNumber(decimal: $0.close).stringValue } ?? ""
                            editingPrice = true
                            priceFocused = true
                        }
                        .buttonStyle(.link)
                        .help("Type a price yourself if the daily update can't get one")
                    }
                }
            }

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                Text("History").font(.headline)
                ForEach(history) { t in
                    HStack(spacing: 8) {
                        Text(t.side.title)
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Palette.well, in: Capsule())
                        Text("\(Money.plain(NSDecimalNumber(decimal: t.shares).doubleValue, decimals: 0)) × Rs \(Money.plain(NSDecimalNumber(decimal: t.price).doubleValue))")
                            .monospacedDigit()
                        Text("· \(t.date.formatted(fmt))").foregroundStyle(.secondary)
                        if let w = store.wallet(t.walletID) { Text("· \(w.name)").foregroundStyle(.tertiary) }
                        Spacer()
                        Button("Edit") { mode = .edit(t) }.buttonStyle(.link)
                        Button { store.deleteTrades([t.id]) } label: {
                            Image(systemName: "xmark.circle.fill").foregroundStyle(.tertiary)
                        }
                        .buttonStyle(.plain)
                        .help("Delete this trade")
                    }
                    .font(.callout)
                }
            }

            HStack {
                Spacer()
                Button("Done", action: onClose).keyboardShortcut(.cancelAction)
            }
        }
    }

    private func stat(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value).fontWeight(.semibold).monospacedDigit()
        }
    }
}

// MARK: - Realised gain from before Kharcha

struct RealisedBeforeEditor: View {
    @Environment(Store.self) private var store
    var onDone: () -> Void
    @State private var isLoss = false
    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Earlier realised gain").font(.title3.weight(.semibold))
            Text("Profit or loss from shares you sold before tracking them here, e.g. the realised gain shown in your broker or npstocks. It's added to your realised and overall gain.")
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Picker("", selection: $isLoss) {
                Text("Gain").tag(false)
                Text("Loss").tag(true)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            AmountField(text: $text, focused: $focused)
            HStack {
                Spacer()
                Button("Cancel", role: .cancel, action: onDone).keyboardShortcut(.cancelAction)
                Button("Save") {
                    guard let amount = Money.parse(text, allowZero: true) else { return }
                    store.setRealisedBefore(isLoss ? -amount : amount)
                    onDone()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(Money.parse(text, allowZero: true) == nil)
            }
        }
        .onAppear {
            let current = store.realisedBefore
            isLoss = current < 0
            text = current == 0 ? "" : NSDecimalNumber(decimal: current < 0 ? -current : current).stringValue
            focused = true
        }
    }
}
