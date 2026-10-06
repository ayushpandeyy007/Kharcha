import SwiftUI

struct LoansView: View {
    @Environment(Store.self) private var store
    @Environment(UIState.self) private var ui
    @Environment(\.undoManager) private var undoManager
    @State private var showSettled = false
    @State private var selection: UUID?

    var body: some View {
        if store.loans.isEmpty {
            ContentUnavailableView {
                Label("No loans yet", systemImage: "person.2")
            } description: {
                Text("Keep track of money you lend to people or borrow from them,\nand record repayments as they come in.")
            } actions: {
                HStack {
                    Button("I Lent Money") { ui.loanSheet = .new(.lent) }.buttonStyle(.borderedProminent)
                    Button("I Borrowed Money") { ui.loanSheet = .new(.borrowed) }
                }
            }
        } else {
            let visible = store.loans.filter { $0.isSettled == showSettled }
            VStack(spacing: 0) {
                header
                Divider()
                if visible.isEmpty {
                    ContentUnavailableView(showSettled ? "No settled loans yet" : "All settled up",
                                           systemImage: showSettled ? "tray" : "checkmark.circle",
                                           description: Text(showSettled ? "Loans move here once they're fully repaid." : "Nobody owes anything right now."))
                } else {
                    list(visible)
                }
            }
        }
    }

    private var header: some View {
        let lent = store.loans.filter { $0.direction == .lent && !$0.isSettled }
        let borrowed = store.loans.filter { $0.direction == .borrowed && !$0.isSettled }
        return VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                StatTile(title: "Owed to you", value: Money.string(store.outstanding(.lent))) {
                    footer(lent, empty: "Nobody owes you")
                }
                StatTile(title: "You owe", value: Money.string(store.outstanding(.borrowed))) {
                    footer(borrowed, empty: "You don't owe anyone")
                }
            }
            Picker("Show", selection: $showSettled) {
                Text("Active").tag(false)
                Text("Settled").tag(true)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
        }
        .padding(16)
    }

    @ViewBuilder
    private func footer(_ loans: [Loan], empty: String) -> some View {
        let overdue = loans.filter { $0.isOverdue() }.count
        if overdue > 0 {
            Label("\(overdue) overdue", systemImage: "exclamationmark.circle.fill")
                .font(.caption).foregroundStyle(Palette.bad)
        } else {
            let people = Set(loans.map { $0.person.lowercased() }).count
            Text(people == 0 ? empty : people == 1 ? "1 person" : "\(people) people")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private func list(_ visible: [Loan]) -> some View {
        List(selection: $selection) {
            ForEach(Loan.Direction.allCases) { direction in
                let items = visible.filter { $0.direction == direction }
                if !items.isEmpty {
                    SwiftUI.Section(direction == .lent ? "Lent · people owe you" : "Borrowed · you owe") {
                        ForEach(items) { LoanRow(loan: $0).tag($0.id) }
                    }
                }
            }
        }
        .listStyle(.inset)
        .scrollContentBackground(.hidden)
        .contextMenu(forSelectionType: UUID.self) { ids in
            if let id = ids.first, let loan = store.loan(id) {
                Button("Open…") { ui.loanSheet = .detail(id) }
                if !loan.isSettled {
                    Button("Mark as Fully Repaid") { store.addRepayment(Repayment(amount: loan.remaining, date: .now, walletID: loan.walletID), to: id) }
                }
                Divider()
                Button("Delete", role: .destructive) { delete(id) }
            }
        } primaryAction: { ids in
            if let id = ids.first { ui.loanSheet = .detail(id) }
        }
        .onDeleteCommand { if let id = selection { delete(id) } }
    }

    private func delete(_ id: UUID) {
        guard let removed = store.deleteLoan(id) else { return }
        selection = nil
        let store = store
        undoManager?.registerUndo(withTarget: store) { target in
            MainActor.assumeIsolated { target.addLoan(removed) }
        }
        undoManager?.setActionName("Delete Loan")
    }
}

struct LoanRow: View {
    let loan: Loan

    var body: some View {
        HStack(spacing: 12) {
            PersonAvatar(name: loan.person, color: loan.direction.color)
            VStack(alignment: .leading, spacing: 2) {
                Text(loan.person).fontWeight(.medium).lineLimit(1)
                HStack(spacing: 4) {
                    Text(loan.date.formatted(.dateTime.day().month(.abbreviated).year()))
                    if loan.isOverdue(), let due = loan.dueDate {
                        Label("Overdue · was due \(due.formatted(.dateTime.day().month(.abbreviated)))", systemImage: "exclamationmark.circle.fill")
                            .foregroundStyle(Palette.bad)
                    } else if !loan.isSettled, let due = loan.dueDate {
                        Text("· due \(due.formatted(.dateTime.day().month(.abbreviated)))")
                    }
                    if !loan.note.isEmpty { Text("· \(loan.note)") }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }
            Spacer(minLength: 12)
            VStack(alignment: .trailing, spacing: 4) {
                if loan.isSettled {
                    Label("Settled", systemImage: "checkmark.circle.fill")
                        .font(.callout).foregroundStyle(Palette.good)
                    Text(Money.string(loan.amount)).font(.caption).foregroundStyle(.secondary).monospacedDigit()
                } else {
                    Text(Money.string(loan.remaining)).fontWeight(.semibold).monospacedDigit()
                    if loan.repaid > 0 {
                        RepaidBar(progress: loan.progress, color: loan.direction.color).frame(width: 110)
                        Text("\(Money.string(loan.repaid)) of \(Money.string(loan.amount)) back")
                            .font(.caption2).foregroundStyle(.secondary).monospacedDigit()
                    } else {
                        Text("Nothing repaid yet").font(.caption2).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Add / edit

struct LoanForm: View {
    @Environment(Store.self) private var store
    let original: Loan?
    var onFinish: (Loan?) -> Void

    @State private var direction: Loan.Direction
    @State private var person: String
    @State private var amountText: String
    @State private var date: Date
    @State private var hasDueDate: Bool
    @State private var dueDate: Date
    @State private var note: String
    @State private var walletID: UUID?
    @FocusState private var amountFocused: Bool
    @FocusState private var personFocused: Bool

    init(original: Loan? = nil, direction: Loan.Direction = .lent, onFinish: @escaping (Loan?) -> Void) {
        self.original = original
        self.onFinish = onFinish
        _direction = State(initialValue: original?.direction ?? direction)
        _person = State(initialValue: original?.person ?? "")
        _amountText = State(initialValue: original.map { NSDecimalNumber(decimal: $0.amount).stringValue } ?? "")
        _date = State(initialValue: original?.date ?? .now)
        _hasDueDate = State(initialValue: original?.dueDate != nil)
        _dueDate = State(initialValue: original?.dueDate ?? Calendar.current.date(byAdding: .month, value: 1, to: .now)!)
        _note = State(initialValue: original?.note ?? "")
        _walletID = State(initialValue: original?.walletID)
    }

    private var amount: Decimal? { Money.parse(amountText) }
    private var trimmedPerson: String { person.trimmingCharacters(in: .whitespacesAndNewlines) }

    private var suggestions: [String] {
        let typed = trimmedPerson.lowercased()
        return store.people
            .filter { typed.isEmpty || ($0.lowercased().hasPrefix(typed) && $0.lowercased() != typed) }
            .prefix(6).map { $0 }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(original == nil ? "New Loan" : "Edit Loan").font(.title3.weight(.semibold))

            Picker("Direction", selection: $direction) {
                ForEach(Loan.Direction.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            VStack(alignment: .leading, spacing: 6) {
                TextField(direction == .lent ? "Who did you lend to?" : "Who did you borrow from?", text: $person)
                    .textFieldStyle(.roundedBorder)
                    .focused($personFocused)
                if !suggestions.isEmpty {
                    HStack(spacing: 6) {
                        ForEach(suggestions, id: \.self) { name in
                            Button(name) { person = name; amountFocused = true }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                        }
                    }
                }
            }

            AmountField(text: $amountText, focused: $amountFocused)

            WalletPicker(title: direction == .lent ? "Paid from" : "Received in", selection: $walletID)

            TextField("Note (optional) — e.g. for rent, phone", text: $note)
                .textFieldStyle(.roundedBorder)

            HStack(spacing: 10) {
                Text("Date").foregroundStyle(.secondary)
                DatePicker("Date", selection: $date, displayedComponents: .date)
                    .labelsHidden().datePickerStyle(.field)
                Spacer()
                Toggle("Due date", isOn: $hasDueDate).toggleStyle(.checkbox)
                if hasDueDate {
                    DatePicker("Due", selection: $dueDate, displayedComponents: .date)
                        .labelsHidden().datePickerStyle(.field)
                }
            }

            if let original, let amount, amount < original.repaid {
                Label("That's less than the \(Money.string(original.repaid)) already repaid.", systemImage: "exclamationmark.triangle.fill")
                    .font(.caption).foregroundStyle(Palette.bad)
            }

            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { onFinish(nil) }
                    .keyboardShortcut(.cancelAction)
                Button(original == nil ? "Add Loan" : "Save", action: save)
                    .keyboardShortcut(.defaultAction)
                    .disabled(amount == nil || trimmedPerson.isEmpty)
            }
        }
        .onAppear {
            if walletID == nil || store.wallet(walletID) == nil { walletID = WalletMemory.last("loan", in: store) }
            if original == nil { personFocused = true } else { amountFocused = true }
        }
    }

    private func save() {
        guard let amount, !trimmedPerson.isEmpty else { NSSound.beep(); return }
        var loan = original ?? Loan(direction: direction, person: trimmedPerson, amount: amount, date: date)
        loan.direction = direction
        loan.person = trimmedPerson
        loan.amount = amount
        loan.date = date
        loan.dueDate = hasDueDate ? dueDate : nil
        loan.note = note.trimmingCharacters(in: .whitespacesAndNewlines)
        loan.walletID = walletID
        WalletMemory.remember(walletID, for: "loan")
        if original == nil { store.addLoan(loan) } else { store.updateLoan(loan) }
        onFinish(loan)
    }
}

// MARK: - Detail & repayments

struct LoanDetail: View {
    @Environment(Store.self) private var store
    let loanID: UUID
    var onClose: () -> Void

    @State private var editing = false
    @State private var payText = ""
    @State private var payDate = Date()
    @State private var payWallet: UUID?
    @State private var confirmDelete = false
    @FocusState private var payFocused: Bool

    var body: some View {
        if let loan = store.loan(loanID) {
            if editing {
                LoanForm(original: loan) { _ in editing = false }
            } else {
                detail(loan)
            }
        } else {
            Color.clear.frame(height: 1).onAppear(perform: onClose)
        }
    }

    private func detail(_ loan: Loan) -> some View {
        let lent = loan.direction == .lent
        let fmt = Date.FormatStyle.dateTime.day().month(.abbreviated).year()
        return VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                PersonAvatar(name: loan.person, color: loan.direction.color, size: 44)
                VStack(alignment: .leading, spacing: 2) {
                    Text(loan.person).font(.title3.weight(.semibold))
                    Text("\(lent ? "You lent" : "You borrowed") \(Money.string(loan.amount)) · \(loan.date.formatted(fmt))")
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Edit") { editing = true }
            }

            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline) {
                    Text(loan.isSettled ? "Fully repaid" : lent ? "Still owed to you" : "You still owe")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("\(percent(loan.progress)) repaid").font(.caption).foregroundStyle(.secondary)
                }
                Text(Money.string(loan.isSettled ? loan.amount : loan.remaining))
                    .font(.system(size: 30, weight: .semibold))
                RepaidBar(progress: loan.progress, color: loan.direction.color)
                Text("\(Money.string(loan.repaid)) of \(Money.string(loan.amount)) paid back")
                    .font(.caption).foregroundStyle(.secondary).monospacedDigit()
            }
            .padding(14)
            .background(Palette.well, in: RoundedRectangle(cornerRadius: 10, style: .continuous))

            if let due = loan.dueDate, !loan.isSettled {
                if loan.isOverdue() {
                    Label("Overdue — was due \(due.formatted(fmt))", systemImage: "exclamationmark.circle.fill")
                        .foregroundStyle(Palette.bad)
                } else {
                    Label("Due \(due.formatted(fmt))", systemImage: "calendar").foregroundStyle(.secondary)
                }
            }
            if !loan.note.isEmpty {
                Label(loan.note, systemImage: "note.text").foregroundStyle(.secondary)
            }

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                Text("Repayments").font(.headline)
                if loan.repayments.isEmpty {
                    Text("No repayments yet.").foregroundStyle(.secondary)
                } else {
                    ForEach(loan.repayments) { r in
                        HStack {
                            Text(r.date.formatted(fmt)).foregroundStyle(.secondary)
                            if let w = store.wallet(r.walletID ?? loan.walletID) {
                                Text("· \(w.name)").foregroundStyle(.tertiary)
                            }
                            Spacer()
                            Text(Money.string(r.amount)).monospacedDigit()
                            Button { store.deleteRepayment(r.id, from: loan.id) } label: {
                                Image(systemName: "xmark.circle.fill").foregroundStyle(.tertiary)
                            }
                            .buttonStyle(.plain)
                            .help("Remove this repayment")
                        }
                    }
                }
            }

            if !loan.isSettled {
                HStack(spacing: 8) {
                    AmountField(text: $payText, compact: true, focused: $payFocused)
                        .frame(width: 190)
                    DatePicker("Paid on", selection: $payDate, displayedComponents: .date)
                        .labelsHidden().datePickerStyle(.field)
                    Spacer()
                    Button("Record") { record(loan) }
                        .keyboardShortcut(.defaultAction)
                        .disabled(Money.parse(payText) == nil)
                    Button("Settle in Full") {
                        store.addRepayment(Repayment(amount: loan.remaining, date: stamped(payDate), walletID: payWallet), to: loan.id)
                    }
                }
                WalletPicker(title: lent ? "Received in" : "Paid from", selection: $payWallet, compact: true)
                Text("Record a partial repayment, or settle the remaining \(Money.string(loan.remaining)) at once.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Divider()

            HStack {
                Button("Delete Loan", role: .destructive) { confirmDelete = true }
                Spacer()
                Button("Done", action: onClose).keyboardShortcut(.cancelAction)
            }
        }
        .onAppear {
            payWallet = store.wallet(loan.walletID)?.id ?? WalletMemory.last("loan", in: store)
            if !loan.isSettled { payFocused = true }
        }
        .confirmationDialog("Delete the loan with \(loan.person)?", isPresented: $confirmDelete) {
            Button("Delete", role: .destructive) {
                store.deleteLoan(loan.id)
                onClose()
            }
        } message: {
            Text("This removes the loan and its repayment history.")
        }
    }

    private func record(_ loan: Loan) {
        guard let amount = Money.parse(payText) else { return }
        // Paying more than what's left just settles the loan.
        store.addRepayment(Repayment(amount: min(amount, loan.remaining), date: stamped(payDate), walletID: payWallet), to: loan.id)
        payText = ""
        payDate = .now
    }

    /// The chosen day at the current time of day, so a repayment made today counts in today's balance.
    private func stamped(_ day: Date) -> Date {
        let cal = Calendar.current
        let t = cal.dateComponents([.hour, .minute, .second], from: .now)
        return cal.date(bySettingHour: t.hour ?? 12, minute: t.minute ?? 0, second: t.second ?? 0, of: day) ?? day
    }
}

// MARK: - Pieces

extension Loan.Direction {
    /// Lent money comes back to you (income color); borrowed money goes out (spending color).
    var color: Color { self == .lent ? Palette.income : Palette.expense }
}

struct PersonAvatar: View {
    let name: String
    let color: Color
    var size: CGFloat = 32

    private var initials: String {
        let letters = name.split(separator: " ").prefix(2).compactMap(\.first)
        return letters.isEmpty ? "?" : String(letters).uppercased()
    }

    var body: some View {
        Text(initials)
            .font(.system(size: size * 0.38, weight: .semibold))
            .foregroundStyle(color)
            .frame(width: size, height: size)
            .background(color.opacity(0.15), in: Circle())
    }
}

struct RepaidBar: View {
    let progress: Double
    let color: Color

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Palette.axis.opacity(0.5))
                Capsule().fill(color).frame(width: progress > 0 ? max(4, geo.size.width * progress) : 0)
            }
        }
        .frame(height: 5)
    }
}
