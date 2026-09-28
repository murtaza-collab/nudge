import DailyCore
import SwiftUI

extension Priority {
    /// Nil for `.none`, so unprioritized tasks stay visually neutral.
    var color: Color? {
        switch self {
        case .none: nil
        case .low: Theme.blue
        case .medium: Theme.yellow
        case .high: Theme.orange
        case .critical: Theme.red
        }
    }

    var symbol: String {
        switch self {
        case .none: "flag.slash"
        default: "flag.fill"
        }
    }
}

/// Small uppercase section heading used across panels.
struct SectionHeader: View {
    let title: String
    var count: Int? = nil
    var tint: Color = .secondary

    var body: some View {
        HStack(spacing: 6) {
            Text(title.uppercased())
                .font(.system(size: 11, weight: .semibold))
                .tracking(0.6)
                .foregroundStyle(tint)
            if let count, count > 0 {
                Text("\(count)")
                    .font(.system(size: 11, weight: .medium))
                    .monospacedDigit()
                    .foregroundStyle(.tertiary)
            }
            Spacer()
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}

extension TaskCategory {
    static let palette: [Color] = [NSColor.systemBlue, .systemPurple, .systemPink, .systemOrange, .systemGreen, .systemTeal, .systemIndigo, .systemBrown].map(Theme.soft)
    static let paletteNames = ["Blue", "Purple", "Pink", "Orange", "Green", "Teal", "Indigo", "Brown"]

    var swiftUIColor: Color { Self.palette[((color % Self.palette.count) + Self.palette.count) % Self.palette.count] }
}

/// "● Work": a small colored category label.
struct CategoryLabel: View {
    let category: TaskCategory
    var fontSize: CGFloat = 11

    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(category.swiftUIColor)
                .frame(width: 6, height: 6)
            Text(category.name)
                .font(.system(size: fontSize, weight: .medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Category \(category.name)")
    }
}

/// App colors. Light mode uses the system colors; in dark mode they're softened toward
/// gray, because fully saturated red and blue glare against a dark background.
enum Theme {
    static let red = soft(.systemRed)
    static let orange = soft(.systemOrange)
    static let yellow = soft(.systemYellow)
    static let green = soft(.systemGreen)
    static let blue = soft(.systemBlue)
    /// The user's accent color (usually blue), softened in dark mode.
    static let accent = soft(.controlAccentColor)
    /// Solid red for filled badges (white text on top). Stays clearly red in dark mode,
    /// where the softened `red` would disappear against a dark background.
    static let attentionFill = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(srgbRed: 0.91, green: 0.30, blue: 0.27, alpha: 1)
            : .systemRed
    })

    /// How far dark-mode colors move toward gray (0 = unchanged).
    private static let darkSoftening: CGFloat = 0.4

    static func soft(_ base: NSColor) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            guard appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua else { return base }
            let resolved = base.usingColorSpace(.sRGB) ?? base
            return resolved.blended(withFraction: darkSoftening, of: NSColor(white: 0.62, alpha: 1)) ?? resolved
        })
    }
}
