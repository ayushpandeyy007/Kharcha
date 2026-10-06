import SwiftUI

struct WalletsView: View {
    @Environment(Store.self) private var store
    @Environment(UIState.self) private var ui
    @Environment(\.undoManager) private var undoManager
    @State private var pendingDelete: Wallet?
    var scrolls = true

    var body: some View {
        let balances = store.balances()
        let month = Calendar.current.dateInterval(of: .month, for: .now)!
        let flows = store.flows(in: month)
        let content = VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Total balance").foregroundStyle(.secondary)
                    Text(Money.string(balances.values.reduce(0, +)))
                        .font(.system(size: 34, weight: .bold))
                    Text(store.wallets.count == 1 ? "In 1 wallet" : "Across \(store.wallets.count) wallets")
                        .font(.callout).foregroundStyle(.secondary)
                }
                Spacer()
                Button { ui.walletSheet = .transfer } label: { Label("Move Money", systemImage: "arrow.left.arrow.right") }
                    .disabled(store.wallets.count < 2)
                    .help("Move money between your wallets, e.g. an ATM withdrawal (⌘T)")
                Button { ui.walletSheet = .new } label: { Label("Add Wallet", systemImage: "plus") }
            }

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 240), spacing: 12)], spacing: 12) {
                ForEach(store.wallets) { wallet in
                    WalletCard(wallet: wallet, balance: balances[wallet.id] ?? 0,
                               flow: flows[wallet.id] ?? (0, 0),
                               onEdit: { ui.walletSheet = .edit(wallet.id) },
                               onDelete: store.wallets.count > 1 ? { pendingDelete = wallet } : nil)
                }
            }

            if !store.transfers.isEmpty { transfers }

            Text("Balances update by themselves as you add income, expenses, loans and transfers. If one drifts from what your bank or pocket shows, edit the wallet and type the real amount.")
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(24)
        .confirmationDialog("Delete “\(pendingDelete?.name ?? "")”?", isPresented: .init(
            get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } })) {
            Button("Delete Wallet", role: .destructive) {
                if let w = pendingDelete { store.deleteWallet(w.id) }
            }
        } message: {
            Text("Past entries stay in your history and analytics, but won't belong to any wallet. Transfers to or from it are removed.")
        }

        if scrolls { ScrollView { content } } else { content }
    }

    private var transfers: some View {
        VStack(alignment: .leading, spacing: 10) {
            CardHeader(title: "Recent transfers")
            VStack(spacing: 0) {
                ForEach(Array(store.transfers.prefix(8).enumerated()), id: \.element.id) { i, x in
                    if i > 0 { Divider() }
                    HStack(spacing: 10) {
                        Image(systemName: "arrow.left.arrow.right")
                            .foregroundStyle(.secondary)
                            .frame(width: 28, height: 28)
                            .background(Palette.well, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                        VStack(alignment: .leading, spacing: 1) {
                            Text("\(store.wallet(x.fromWalletID)?.name ?? "?") → \(store.wallet(x.toWalletID)?.name ?? "?")")
                                .lineLimit(1)
                            Text([x.date.dayTitle(), x.note].filter { !$0.isEmpty }.joined(separator: " · "))
                                .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        }
                        Spacer()
                        Text(Money.string(x.amount)).monospacedDigit()
                        Button { deleteTransfer(x.id) } label: {
                            Image(systemName: "xmark.circle.fill").foregroundStyle(.tertiary)
                        }
                        .buttonStyle(.plain)
                        .help("Remove this transfer")
                    }
                    .padding(.vertical, 6)
                }
            }
        }
        .card()
    }

    private func deleteTransfer(_ id: UUID) {
        guard let removed = store.deleteTransfer(id) else { return }
        let store = store
        undoManager?.registerUndo(withTarget: store) { target in
            MainActor.assumeIsolated { target.addTransfer(removed) }
        }
        undoManager?.setActionName("Delete Transfer")
    }
}

private struct WalletCard: View {
    let wallet: Wallet
    let balance: Double
    let flow: (in: Double, out: Double)
    let onEdit: () -> Void
    let onDelete: (() -> Void)?

    var body: some View {
        let tint = Palette.color(wallet.color)
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: wallet.kind.icon)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(tint)
                    .frame(width: 34, height: 34)
                    .background(tint.opacity(0.14), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                VStack(alignment: .leading, spacing: 1) {
                    Text(wallet.name).fontWeight(.medium).lineLimit(1)
                    if wallet.kind.title.caseInsensitiveCompare(wallet.name) != .orderedSame {
                        Text(wallet.kind.title).font(.caption).foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Menu {
                    Button("Edit or Correct Balance…", action: onEdit)
                    if let onDelete {
                        Divider()
                        Button("Delete…", role: .destructive, action: onDelete)
                    }
                } label: {
                    Image(systemName: "ellipsis.circle").foregroundStyle(.secondary)
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
            }
            HStack(spacing: 6) {
                Text(Money.string(balance))
                    .font(.system(size: 24, weight: .semibold))
                    .lineLimit(1).minimumScaleFactor(0.6)
                if balance < 0 {
                    Image(systemName: "exclamationmark.circle.fill").foregroundStyle(Palette.bad)
                        .help("Below zero — check that this wallet's balance is right")
                }
            }
            HStack(spacing: 12) {
                Text("In \(Money.string(flow.in))")
                Text("Out \(Money.string(flow.out))")
                Spacer()
                Text("this month")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .monospacedDigit()
            .help("Money in and out of this wallet this month")
        }
        .card()
        .contentShape(Rectangle())
        .onTapGesture(count: 2, perform: onEdit)
    }
}

// MARK: - Add / edit wallet

struct WalletForm: View {
    @Environment(Store.self) private var store
    let original: Wallet?
    var onFinish: () -> Void

    @State private var name: String
    @State private var kind: Wallet.Kind
    @State private var color: Int
    @State private var balanceText = ""
    @State private var startingBalance: Double?
    @FocusState private var balanceFocused: Bool

    init(original: Wallet? = nil, onFinish: @escaping () -> Void) {
        self.original = original
        self.onFinish = onFinish
        _name = State(initialValue: original?.name ?? "")
        _kind = State(initialValue: original?.kind ?? .digital)
        _color = State(initialValue: original?.color ?? 0)
    }

    private var amount: Decimal? { Money.parse(balanceText, allowZero: true) }
    private var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(original == nil ? "New Wallet" : "Edit Wallet").font(.title3.weight(.semibold))

            HStack(spacing: 12) {
                Image(systemName: kind.icon)
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(Palette.color(color))
                    .frame(width: 40, height: 40)
                    .background(Palette.color(color).opacity(0.14), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                TextField("Name — e.g. Nabil Bank, eSewa, Cash", text: $name)
                    .textFieldStyle(.roundedBorder)
                    .font(.title3)
            }

            Picker("Type", selection: $kind) {
                ForEach(Wallet.Kind.allCases) { Label($0.title, systemImage: $0.icon).tag($0) }
            }
            .pickerStyle(.segmented)

            HStack(spacing: 10) {
                Text("Color").foregroundStyle(.secondary)
                ForEach(0..<Palette.slots.count, id: \.self) { i in
                    Circle()
                        .fill(Palette.color(i))
                        .frame(width: 20, height: 20)
                        .overlay { if color == i { Circle().strokeBorder(.white, lineWidth: 2).padding(2) } }
                        .onTapGesture { color = i }
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Balance right now").foregroundStyle(.secondary)
                AmountField(text: $balanceText, focused: $balanceFocused)
                Text(original == nil
                     ? "What this wallet holds today. From now on it updates by itself as you add entries."
                     : "Change this only to match what your bank or pocket really shows.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            HStack {
                Spacer()
                Button("Cancel", role: .cancel, action: onFinish).keyboardShortcut(.cancelAction)
                Button(original == nil ? "Add Wallet" : "Save", action: save)
                    .keyboardShortcut(.defaultAction)
                    .disabled(trimmedName.isEmpty || amount == nil)
            }
        }
        .onAppear {
            let current = original.map { store.balances()[$0.id] ?? 0 } ?? 0
            startingBalance = original == nil ? nil : current
            balanceText = original == nil ? "" : plain(current)
            balanceFocused = original == nil ? false : true
        }
    }

    private func save() {
        guard let amount, !trimmedName.isEmpty else { NSSound.beep(); return }
        if var wallet = original {
            wallet.name = trimmedName
            wallet.kind = kind
            wallet.color = color
            store.upsertWallet(wallet)
            // Only re-anchor when the balance was actually corrected.
            if let startingBalance, abs(NSDecimalNumber(decimal: amount).doubleValue - startingBalance) >= 0.005 {
                store.setBalance(of: wallet.id, to: amount)
            }
        } else {
            store.addWallet(name: trimmedName, kind: kind, color: color, balance: amount)
        }
        onFinish()
    }

    private func plain(_ value: Double) -> String {
        NSDecimalNumber(value: (value * 100).rounded() / 100).stringValue
    }
}

// MARK: - Move money between wallets

struct TransferForm: View {
    @Environment(Store.self) private var store
    var onFinish: () -> Void

    @State private var from: UUID?
    @State private var to: UUID?
    @State private var amountText = ""
    @State private var note = ""
    @State private var date = Date()
    @FocusState private var amountFocused: Bool

    private var amount: Decimal? { Money.parse(amountText) }

    var body: some View {
        let balances = store.balances()
        VStack(alignment: .leading, spacing: 14) {
            Text("Move Money").font(.title3.weight(.semibold))
            Text("For money moving between your own wallets, like an ATM withdrawal or loading eSewa. It isn't counted as spending or income.")
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            WalletPicker(title: "From", selection: $from, balances: balances)
            WalletPicker(title: "To", selection: $to, balances: balances, excluding: from)

            AmountField(text: $amountText, focused: $amountFocused)

            TextField("Note (optional) — e.g. ATM withdrawal", text: $note)
                .textFieldStyle(.roundedBorder)

            HStack {
                DatePicker("Date", selection: $date, displayedComponents: .date)
                    .labelsHidden().datePickerStyle(.field)
                Spacer()
                Button("Cancel", role: .cancel, action: onFinish).keyboardShortcut(.cancelAction)
                Button("Move", action: save)
                    .keyboardShortcut(.defaultAction)
                    .disabled(amount == nil || from == nil || to == nil || from == to)
            }
        }
        .onAppear {
            from = store.wallets.first { $0.kind == .bank }?.id ?? store.wallets.first?.id
            to = store.wallets.first { $0.kind == .cash && $0.id != from }?.id ?? store.wallets.first { $0.id != from }?.id
            amountFocused = true
        }
        .onChange(of: from) { _, newFrom in
            if to == newFrom { to = store.wallets.first { $0.id != newFrom }?.id }
        }
    }

    private func save() {
        guard let amount, let from, let to, from != to else { NSSound.beep(); return }
        let cal = Calendar.current
        let time = cal.dateComponents([.hour, .minute, .second], from: .now)
        let stamped = cal.date(bySettingHour: time.hour ?? 12, minute: time.minute ?? 0, second: time.second ?? 0, of: date) ?? date
        store.addTransfer(Transfer(fromWalletID: from, toWalletID: to, amount: amount, date: stamped,
                                   note: note.trimmingCharacters(in: .whitespacesAndNewlines)))
        onFinish()
    }
}

// MARK: - Picking a wallet

/// One-click wallet chips, used wherever money comes from or goes into a wallet.
struct WalletPicker: View {
    @Environment(Store.self) private var store
    let title: String
    @Binding var selection: UUID?
    var balances: [UUID: Double]? = nil
    var excluding: UUID? = nil
    var compact = false

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: compact ? 72 : 100), spacing: 6)], spacing: 6) {
                ForEach(store.wallets.filter { $0.id != excluding }) { w in
                    let tint = Palette.color(w.color)
                    let selected = w.id == selection
                    Button { selection = w.id } label: {
                        HStack(spacing: 5) {
                            Image(systemName: w.kind.icon).foregroundStyle(tint)
                            VStack(alignment: .leading, spacing: 0) {
                                Text(w.name).lineLimit(1).minimumScaleFactor(0.75)
                                if let b = balances?[w.id] {
                                    Text(Money.compact(b)).font(.caption2).foregroundStyle(.secondary)
                                }
                            }
                        }
                        .font(.caption)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 6)
                        .padding(.horizontal, 7)
                        .background(selected ? tint.opacity(0.14) : Color.clear, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(selected ? tint : Palette.hairline, lineWidth: selected ? 1.5 : 1))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help(w.name)
                }
            }
        }
    }
}

/// Remembers the wallet you last used for each kind of entry, so the next one starts there.
enum WalletMemory {
    @MainActor
    static func last(_ key: String, in store: Store) -> UUID? {
        let saved = UserDefaults.standard.string(forKey: "lastWallet.\(key)").flatMap(UUID.init(uuidString:))
        return store.wallet(saved)?.id ?? store.wallets.first?.id
    }

    static func remember(_ id: UUID?, for key: String) {
        UserDefaults.standard.set(id?.uuidString, forKey: "lastWallet.\(key)")
    }
}
