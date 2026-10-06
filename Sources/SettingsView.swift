import SwiftUI

struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettings().tabItem { Label("General", systemImage: "gearshape") }
            CategorySettings().tabItem { Label("Categories", systemImage: "square.grid.2x2") }
        }
        .frame(width: 540, height: 480)
    }
}

private struct GeneralSettings: View {
    @Environment(Store.self) private var store
    @AppStorage(Money.symbolKey) private var symbol = "Rs"
    @AppStorage("menuBarShowsTotal") private var menuBarShowsTotal = false

    var body: some View {
        Form {
            TextField("Currency symbol", text: $symbol, prompt: Text("Rs"))
            LabeledContent("Preview", value: Money.string(Double(125000)))
            Toggle("Show this month's spending in the menu bar", isOn: $menuBarShowsTotal)

            SwiftUI.Section("Export") {
                LabeledContent("Spreadsheet (CSV)") {
                    HStack {
                        Button("Transactions…") { Exporter.exportTransactions(store) }
                        Button("Loans…") { Exporter.exportLoans(store) }
                    }
                }
                LabeledContent("Everything (JSON)") {
                    Button("Full Backup…") { Exporter.exportBackup(store) }
                }
            }
            SwiftUI.Section {
                LabeledContent("Data file") {
                    Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([store.dataURL]) }
                }
                Text("Everything is stored locally in one file (data.json). A backup copy is refreshed every launch.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

private struct CategorySettings: View {
    @Environment(Store.self) private var store
    @State private var kind: Kind = .expense
    @State private var selection: UUID?
    @State private var editing: Category?
    @State private var pendingDelete: Category?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Picker("Kind", selection: $kind) {
                Text("Expense").tag(Kind.expense)
                Text("Income").tag(Kind.income)
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            List(selection: $selection) {
                ForEach(store.categories(of: kind)) { c in
                    HStack(spacing: 10) {
                        CategoryIcon(category: c, size: 24)
                        Text(c.name)
                        Spacer()
                        let n = store.usage(of: c.id)
                        if n > 0 { Text("\(n)").font(.caption).foregroundStyle(.secondary).monospacedDigit() }
                    }
                    .tag(c.id)
                    .contextMenu {
                        Button("Edit…") { editing = c }
                        Button("Delete…", role: .destructive) { pendingDelete = c }.disabled(c.isFallback)
                    }
                }
                .onMove { store.moveCategories(of: kind, from: $0, to: $1) }
            }
            .listStyle(.bordered(alternatesRowBackgrounds: true))
            .contextMenu(forSelectionType: UUID.self) { _ in } primaryAction: { ids in
                if let id = ids.first { editing = store.category(id) }
            }

            HStack(spacing: 6) {
                Button { editing = Category(id: UUID(), name: "", icon: "tag", color: 0, kind: kind) } label: {
                    Image(systemName: "plus")
                }
                Button { pendingDelete = selected } label: { Image(systemName: "minus") }
                    .disabled(selected == nil || selected!.isFallback)
                Button("Edit…") { editing = selected }
                    .disabled(selected == nil)
                Spacer()
                Text("Drag to reorder · double-click to edit").font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(20)
        .onChange(of: kind) { selection = nil }
        .sheet(item: $editing) { c in
            CategoryEditor(draft: c) { store.upsert($0) }
        }
        .confirmationDialog("Delete “\(pendingDelete?.name ?? "")”?", isPresented: .init(
            get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } })) {
            Button("Delete", role: .destructive) {
                if let c = pendingDelete { store.deleteCategory(c.id) }
                selection = nil
            }
        } message: {
            let n = pendingDelete.map { store.usage(of: $0.id) } ?? 0
            Text(n > 0 ? "\(n) transaction\(n == 1 ? "" : "s") will move to “Other”." : "It isn't used by any transactions.")
        }
    }

    private var selected: Category? {
        selection.flatMap { id in store.categories.first { $0.id == id } }
    }
}

private struct CategoryEditor: View {
    @Environment(\.dismiss) private var dismiss
    @State var draft: Category
    let onSave: (Category) -> Void

    private static let icons = [
        "fork.knife", "cup.and.saucer", "cart", "basket", "bag", "tshirt", "car", "bus", "fuelpump", "bicycle",
        "airplane", "house", "bolt", "drop", "flame", "wifi", "phone", "tv", "gamecontroller", "popcorn",
        "film", "music.note", "book", "graduationcap", "cross.case", "pills", "heart", "stethoscope", "figure.run", "dumbbell",
        "pawprint", "gift", "scissors", "wrench.and.screwdriver", "briefcase", "laptopcomputer", "banknote", "creditcard",
        "building.columns", "chart.line.uptrend.xyaxis", "person.2", "leaf", "sparkles", "star", "camera", "tag",
        "ellipsis.circle", "plus.circle",
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                CategoryIcon(category: draft, size: 40)
                TextField("Category name", text: $draft.name)
                    .textFieldStyle(.roundedBorder)
                    .font(.title3)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Color").font(.subheadline).foregroundStyle(.secondary)
                HStack(spacing: 10) {
                    ForEach(-1..<Palette.slots.count, id: \.self) { i in
                        Circle()
                            .fill(Palette.color(i))
                            .frame(width: 22, height: 22)
                            .overlay { if draft.color == i { Circle().strokeBorder(.white, lineWidth: 2).padding(2) } }
                            .overlay { if draft.color == i { Circle().strokeBorder(Palette.color(i), lineWidth: 1) } }
                            .onTapGesture { draft.color = i }
                    }
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Icon").font(.subheadline).foregroundStyle(.secondary)
                LazyVGrid(columns: Array(repeating: GridItem(.fixed(34), spacing: 6), count: 10), spacing: 6) {
                    ForEach(Self.icons, id: \.self) { icon in
                        Image(systemName: icon)
                            .font(.system(size: 14))
                            .frame(width: 34, height: 34)
                            .background(draft.icon == icon ? Palette.color(draft.color).opacity(0.16) : Palette.well,
                                        in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                            .foregroundStyle(draft.icon == icon ? Palette.color(draft.color) : Color.primary)
                            .onTapGesture { draft.icon = icon }
                    }
                }
            }

            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Save") {
                    draft.name = draft.name.trimmingCharacters(in: .whitespaces)
                    onSave(draft)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(draft.name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 440)
    }
}
