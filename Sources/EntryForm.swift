import SwiftUI

/// Add or edit one transaction. Used in the main window's sheet and inline in the menu bar.
struct EntryForm: View {
    @Environment(Store.self) private var store

    let original: Transaction?
    var compact = false
    var onFinish: (Transaction?) -> Void

    @State private var kind: Kind
    @State private var amountText: String
    @State private var categoryID: UUID
    @State private var categoryTouched: Bool
    @State private var note: String
    @State private var date: Date
    @State private var walletID: UUID?
    @State private var walletTouched: Bool
    @FocusState private var amountFocused: Bool

    init(original: Transaction? = nil, kind: Kind = .expense, compact: Bool = false, onFinish: @escaping (Transaction?) -> Void) {
        self.original = original
        self.compact = compact
        self.onFinish = onFinish
        let k = original?.kind ?? kind
        _kind = State(initialValue: k)
        _amountText = State(initialValue: original.map { NSDecimalNumber(decimal: $0.amount).stringValue } ?? "")
        _categoryID = State(initialValue: original?.categoryID ?? Category.fallbackID(for: k))
        _categoryTouched = State(initialValue: original != nil)
        _note = State(initialValue: original?.note ?? "")
        _date = State(initialValue: original?.date ?? .now)
        _walletID = State(initialValue: original?.walletID)
        _walletTouched = State(initialValue: original != nil)
    }

    private var amount: Decimal? { Money.parse(amountText) }

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 10 : 14) {
            if !compact {
                Text(original == nil ? "New Transaction" : "Edit Transaction").font(.title3.weight(.semibold))
            }

            Picker("Type", selection: $kind) {
                ForEach(Kind.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            AmountField(text: $amountText, compact: compact, focused: $amountFocused)

            LazyVGrid(columns: [GridItem(.adaptive(minimum: compact ? 70 : 84), spacing: 6)], spacing: 6) {
                ForEach(store.categories(of: kind)) { c in
                    CategoryChip(category: c, selected: c.id == categoryID) {
                        categoryID = c.id
                        categoryTouched = true
                    }
                }
            }

            WalletPicker(title: kind == .expense ? "Paid from" : "Received in",
                         selection: Binding(get: { walletID }, set: { walletID = $0; walletTouched = true }),
                         compact: compact)

            TextField("Note (optional) — e.g. momo, bus fare", text: $note)
                .textFieldStyle(.roundedBorder)

            HStack(spacing: 8) {
                DatePicker("Date", selection: $date, displayedComponents: .date)
                    .labelsHidden()
                    .datePickerStyle(.field)
                if !Calendar.current.isDateInToday(date) {
                    Button("Today") { date = .now }.controlSize(.small)
                }
                Spacer()
                if !compact {
                    Button("Cancel", role: .cancel) { onFinish(nil) }
                        .keyboardShortcut(.cancelAction)
                }
                Button(original == nil ? "Add" : "Save", action: save)
                    .keyboardShortcut(.defaultAction)
                    .disabled(amount == nil)
            }
        }
        .onChange(of: kind) { _, newKind in
            if store.category(categoryID).kind != newKind {
                categoryID = Category.fallbackID(for: newKind)
                categoryTouched = false
            }
            if !walletTouched { walletID = WalletMemory.last(newKind.rawValue, in: store) }
        }
        .onChange(of: note) { _, newNote in
            guard !categoryTouched, let suggested = store.suggestedCategory(forNote: newNote, kind: kind) else { return }
            categoryID = suggested
        }
        .onAppear {
            if walletID == nil || store.wallet(walletID) == nil { walletID = WalletMemory.last(kind.rawValue, in: store) }
            amountFocused = true
        }
    }

    private func save() {
        guard let amount else {
            amountFocused = true
            NSSound.beep()
            return
        }
        // Keep the time of day (original, or now) so entries stay in the order they were made.
        let cal = Calendar.current
        let time = cal.dateComponents([.hour, .minute, .second], from: original?.date ?? .now)
        let stamped = cal.date(bySettingHour: time.hour ?? 12, minute: time.minute ?? 0, second: time.second ?? 0, of: date) ?? date

        var t = original ?? Transaction(kind: kind, amount: amount, categoryID: categoryID, date: stamped)
        t.kind = kind
        t.amount = amount
        t.categoryID = categoryID
        t.note = note.trimmingCharacters(in: .whitespacesAndNewlines)
        t.date = stamped
        t.walletID = walletID
        WalletMemory.remember(walletID, for: kind.rawValue)

        if original == nil { store.add(t) } else { store.update(t) }
        onFinish(t)

        if compact {
            amountText = ""
            note = ""
            date = .now
            categoryID = Category.fallbackID(for: kind)
            categoryTouched = false
            walletTouched = false
            amountFocused = true
        }
    }
}

private struct CategoryChip: View {
    let category: Category
    let selected: Bool
    let action: () -> Void

    var body: some View {
        let tint = Palette.color(category.color)
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: category.icon)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(tint)
                Text(category.name)
                    .font(.caption)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 7)
            .padding(.horizontal, 4)
            .background(selected ? tint.opacity(0.14) : Color.clear, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(selected ? tint : Palette.hairline, lineWidth: selected ? 1.5 : 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(category.name)
    }
}

/// Big amount input with the currency symbol, shared by the transaction and loan forms.
struct AmountField: View {
    @Binding var text: String
    var compact = false
    var focused: FocusState<Bool>.Binding

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(Money.symbol)
                .font(.system(size: compact ? 18 : 22, weight: .medium))
                .foregroundStyle(.secondary)
            TextField("0", text: $text)
                .textFieldStyle(.plain)
                .font(.system(size: compact ? 26 : 32, weight: .semibold))
                .focused(focused)
            if Money.isExpression(text), let amount = Money.parse(text) {
                Text("= \(Money.string(amount))").font(.callout).foregroundStyle(.secondary).monospacedDigit()
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, compact ? 6 : 8)
        .background(Palette.well, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}
