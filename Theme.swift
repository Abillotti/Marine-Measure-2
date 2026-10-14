import SwiftUI

enum Theme {
    static let ocean = Color(red: 0.035, green: 0.215, blue: 0.380)     // deep water
    static let accent = Color(red: 0.180, green: 0.435, blue: 0.847)    // blue-crab blue
    static let teal = Color(red: 0.110, green: 0.600, blue: 0.620)
    static let sand = Color(red: 0.960, green: 0.900, blue: 0.790)
    static let claw = Color(red: 0.860, green: 0.330, blue: 0.250)      // "painted fingernails"
    static let keep = Color(red: 0.150, green: 0.600, blue: 0.350)
    static let release = Color(red: 0.830, green: 0.250, blue: 0.250)
    static let caution = Color(red: 0.900, green: 0.580, blue: 0.050)
    static let info = Color(red: 0.250, green: 0.480, blue: 0.880)
    static let measure = Color(red: 1.000, green: 0.840, blue: 0.040)   // marker yellow

    static var oceanGradient: LinearGradient {
        LinearGradient(colors: [ocean, accent], startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    static let cardBackground = Color(.secondarySystemGroupedBackground)
    static let screenBackground = Color(.systemGroupedBackground)
}

extension Color {
    /// Creates a color from "#RRGGBB" (falls back to the app accent).
    init(hex: String) {
        var text = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.hasPrefix("#") { text.removeFirst() }
        guard text.count == 6, let value = UInt32(text, radix: 16) else {
            self = Theme.accent
            return
        }
        let red = Double((value >> 16) & 0xFF) / 255.0
        let green = Double((value >> 8) & 0xFF) / 255.0
        let blue = Double(value & 0xFF) / 255.0
        self = Color(red: red, green: green, blue: blue)
    }
}

extension VerdictKind {
    var color: Color {
        switch self {
        case .keep: return Theme.keep
        case .release: return Theme.release
        case .borderline: return Theme.caution
        case .needsInfo: return Theme.info
        case .noRules: return .gray
        }
    }

    var symbol: String {
        switch self {
        case .keep: return "checkmark.seal.fill"
        case .release: return "arrow.uturn.backward.circle.fill"
        case .borderline: return "exclamationmark.triangle.fill"
        case .needsInfo: return "questionmark.circle.fill"
        case .noRules: return "doc.text.magnifyingglass"
        }
    }

    var shortTitle: String {
        switch self {
        case .keep: return "Keep"
        case .release: return "Release"
        case .borderline: return "Borderline"
        case .needsInfo: return "Check"
        case .noRules: return "No rules"
        }
    }
}

/// Rounded card container used across the app.
struct CardModifier: ViewModifier {
    var padding: CGFloat = 16
    func body(content: Content) -> some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.cardBackground, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

extension View {
    func card(padding: CGFloat = 16) -> some View {
        modifier(CardModifier(padding: padding))
    }
}
