import SwiftUI
import AppKit

extension Color {
    /// A color with its own light and dark step (not an automatic flip).
    init(light: UInt32, dark: UInt32) {
        self.init(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            let hex = isDark ? dark : light
            return NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
                           green: CGFloat((hex >> 8) & 0xFF) / 255,
                           blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
        })
    }
}

enum Palette {
    // Categorical slots in validated order: blue, orange, aqua, yellow, magenta, green, violet, red.
    static let slots: [Color] = [
        Color(light: 0x2A78D6, dark: 0x3987E5),
        Color(light: 0xEB6834, dark: 0xD95926),
        Color(light: 0x1BAF7A, dark: 0x199E70),
        Color(light: 0xEDA100, dark: 0xC98500),
        Color(light: 0xE87BA4, dark: 0xD55181),
        Color(light: 0x008300, dark: 0x008300),
        Color(light: 0x4A3AA7, dark: 0x9085E9),
        Color(light: 0xE34948, dark: 0xE66767),
    ]
    static let neutral = Color(light: 0x898781, dark: 0x898781)

    static func color(_ index: Int) -> Color { slots.indices.contains(index) ? slots[index] : neutral }

    static let expense = slots[1]
    static let income = slots[2]

    // Status ink: only ever shown next to an arrow/icon and a label.
    static let good = Color(light: 0x006300, dark: 0x0CA30C)
    static let bad = Color(light: 0xD03B3B, dark: 0xE66767)

    // Surfaces
    static let page = Color(light: 0xF4F4F2, dark: 0x111111)
    static let surface = Color(light: 0xFFFFFF, dark: 0x1A1A19)
    static let well = Color(light: 0xF0EFEC, dark: 0x262624)
    static let hairline = Color(light: 0xE1E0D9, dark: 0x2C2C2A)
    static let axis = Color(light: 0xC3C2B7, dark: 0x383835)

    /// Sequential blue for the heatmap: index 0 = no spending, 4 = most.
    static let heat: [Color] = [
        Color(light: 0xF0EFEC, dark: 0x262624),
        Color(light: 0xB7D3F6, dark: 0x184F95),
        Color(light: 0x6DA7EC, dark: 0x256ABF),
        Color(light: 0x2A78D6, dark: 0x3987E5),
        Color(light: 0x184F95, dark: 0x86B6EF),
    ]
}

extension Insight.Tone {
    var color: Color {
        switch self {
        case .good: Palette.good
        case .bad: Palette.bad
        case .neutral: Palette.slots[0]
        }
    }
}

// MARK: - Building blocks

extension View {
    func card(padding: CGFloat = 16) -> some View {
        self.padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Palette.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Palette.hairline))
    }
}

struct CardHeader<Trailing: View>: View {
    let title: String
    var subtitle: String? = nil
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                if let subtitle { Text(subtitle).font(.subheadline).foregroundStyle(.secondary) }
            }
            Spacer(minLength: 12)
            trailing
        }
    }
}

extension CardHeader where Trailing == EmptyView {
    init(title: String, subtitle: String? = nil) {
        self.init(title: title, subtitle: subtitle) { EmptyView() }
    }
}

struct StatTile<Footer: View>: View {
    let title: String
    let value: String
    @ViewBuilder var footer: Footer

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.subheadline).foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 24, weight: .semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            footer
        }
        .card(padding: 14)
    }
}

/// Arrow + percentage + label. Colored by whether the move is good news.
struct DeltaLabel: View {
    let current: Double
    let previous: Double
    let goodWhenUp: Bool
    var suffix: String = ""

    var body: some View {
        if previous > 0 {
            let change = (current - previous) / previous
            let flat = abs(change) < 0.005
            let good = (change > 0) == goodWhenUp
            HStack(spacing: 3) {
                Image(systemName: flat ? "equal" : change > 0 ? "arrow.up.right" : "arrow.down.right")
                    .font(.caption2.weight(.bold))
                Text(percent(abs(change)))
                    .foregroundStyle(flat ? Color.secondary : good ? Palette.good : Palette.bad)
                if !suffix.isEmpty { Text(suffix).foregroundStyle(.secondary) }
            }
            .font(.caption)
            .foregroundStyle(flat ? Color.secondary : good ? Palette.good : Palette.bad)
            .lineLimit(1)
        } else {
            Text(suffix.isEmpty ? "No earlier data" : "No data \(suffix)")
                .font(.caption).foregroundStyle(.tertiary).lineLimit(1)
        }
    }
}

struct CategoryIcon: View {
    let category: Category
    var size: CGFloat = 28

    var body: some View {
        let tint = Palette.color(category.color)
        Image(systemName: category.icon)
            .font(.system(size: size * 0.46, weight: .medium))
            .foregroundStyle(tint)
            .frame(width: size, height: size)
            .background(tint.opacity(0.14), in: RoundedRectangle(cornerRadius: size * 0.3, style: .continuous))
    }
}

struct AmountText: View {
    let transaction: Transaction

    var body: some View {
        Text((transaction.kind == .income ? "+" : "") + Money.string(transaction.amount))
            .monospacedDigit()
            .foregroundStyle(transaction.kind == .income ? Palette.good : Color.primary)
    }
}

struct TransactionRow: View {
    let transaction: Transaction
    let category: Category
    var wallet: Wallet? = nil
    var showsDate = false

    var body: some View {
        HStack(spacing: 10) {
            CategoryIcon(category: category)
            VStack(alignment: .leading, spacing: 1) {
                Text(transaction.note.isEmpty ? category.name : transaction.note).lineLimit(1)
                if let sub = subtitle {
                    Text(sub).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            Spacer(minLength: 8)
            AmountText(transaction: transaction)
        }
        .padding(.vertical, 2)
    }

    private var subtitle: String? {
        let date = showsDate ? transaction.date.dayTitle() : nil
        let parts = [transaction.note.isEmpty ? nil : category.name, wallet?.name, date].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}

/// Horizontal share bars, one row per category. Text stays in ink; the bar carries the color.
struct CategoryBars: View {
    let totals: [CategoryTotal]
    var limit: Int? = nil

    var body: some View {
        let rows = limit.map { Array(totals.prefix($0)) } ?? totals
        let maxAmount = rows.map(\.amount).max() ?? 0
        VStack(spacing: 12) {
            ForEach(rows) { row in
                HStack(spacing: 10) {
                    CategoryIcon(category: row.category, size: 26)
                    VStack(alignment: .leading, spacing: 5) {
                        HStack(spacing: 8) {
                            Text(row.category.name).lineLimit(1)
                            Spacer(minLength: 4)
                            Text(Money.string(row.amount)).monospacedDigit()
                        }
                        HStack(spacing: 8) {
                            GeometryReader { geo in
                                ZStack(alignment: .leading) {
                                    Capsule().fill(Palette.well)
                                    Capsule().fill(Palette.color(row.category.color))
                                        .frame(width: maxAmount > 0 ? max(4, geo.size.width * row.amount / maxAmount) : 0)
                                }
                            }
                            .frame(height: 5)
                            Text(percent(row.share)).font(.caption).foregroundStyle(.secondary)
                                .monospacedDigit().frame(width: 34, alignment: .trailing)
                        }
                    }
                }
            }
        }
    }
}

struct LegendDot: View {
    let color: Color
    let label: String
    var dashed = false

    var body: some View {
        HStack(spacing: 5) {
            if dashed {
                Capsule().stroke(color, style: StrokeStyle(lineWidth: 2, dash: [3, 2])).frame(width: 12, height: 2)
            } else {
                Circle().fill(color).frame(width: 8, height: 8)
            }
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
    }
}

struct ChartTooltip: View {
    struct Row: Identifiable {
        let color: Color
        let label: String
        let value: String
        var id: String { label }
    }

    let title: String
    let rows: [Row]

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption.weight(.semibold))
            ForEach(rows) { row in
                HStack(spacing: 6) {
                    Circle().fill(row.color).frame(width: 7, height: 7)
                    Text(row.label).foregroundStyle(.secondary)
                    Spacer(minLength: 10)
                    Text(row.value).monospacedDigit()
                }
                .font(.caption)
            }
        }
        .padding(8)
        .frame(minWidth: 150)
        .background(Palette.surface, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Palette.hairline))
        .shadow(color: .black.opacity(0.08), radius: 6, y: 2)
    }
}
