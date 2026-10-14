import SwiftUI

/// Bottom-side view of a blue crab with the apron shape that identifies its sex.
struct ApronDiagram: View {
    let sex: CrabSex
    var size: CGFloat = 96

    var body: some View {
        Canvas { context, canvasSize in
            let r = CGRect(origin: .zero, size: canvasSize)
            func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { GlyphDrawing.point(r, x, y) }

            // Underside of the shell
            context.fill(GlyphDrawing.crabCarapace(r), with: .color(Color(red: 0.95, green: 0.93, blue: 0.86)))
            context.stroke(GlyphDrawing.crabCarapace(r), with: .color(.gray.opacity(0.6)), lineWidth: 1)

            var apron = Path()
            switch sex {
            case .male, .unknown:
                // Long narrow "T" (the Washington Monument)
                apron.move(to: p(0.40, 0.66))
                apron.addLine(to: p(0.60, 0.66))
                apron.addLine(to: p(0.545, 0.60))
                apron.addLine(to: p(0.525, 0.40))
                apron.addLine(to: p(0.475, 0.40))
                apron.addLine(to: p(0.455, 0.60))
                apron.closeSubpath()
            case .immatureFemale:
                // Triangle
                apron.move(to: p(0.50, 0.40))
                apron.addLine(to: p(0.63, 0.66))
                apron.addLine(to: p(0.37, 0.66))
                apron.closeSubpath()
            case .matureFemale, .eggBearing:
                // Wide rounded dome (the Capitol)
                apron.move(to: p(0.34, 0.66))
                apron.addQuadCurve(to: p(0.50, 0.40), control: p(0.33, 0.42))
                apron.addQuadCurve(to: p(0.66, 0.66), control: p(0.67, 0.42))
                apron.closeSubpath()
            }
            context.fill(apron, with: .color(Color(red: 0.86, green: 0.80, blue: 0.66)))
            context.stroke(apron, with: .color(.brown.opacity(0.7)), lineWidth: 1.2)

            if sex == .eggBearing {
                let eggs = Path(ellipseIn: CGRect(origin: p(0.33, 0.56), size: CGSize(width: r.width * 0.34, height: r.height * 0.26)))
                context.fill(eggs, with: .color(Color(red: 0.95, green: 0.55, blue: 0.15)))
            }
        }
        .frame(width: size, height: size * 0.8)
        .accessibilityHidden(true)
    }
}

/// Guided sex identification for blue crabs (Junior Research Project reach goal:
/// "guided/annotated images").
struct SexGuideView: View {
    var onPick: ((CrabSex) -> Void)? = nil
    @Environment(\.dismiss) private var dismiss

    private struct Entry: Identifiable {
        let sex: CrabSex
        let title: String
        let text: String
        var id: String { sex.rawValue }
    }

    private let entries: [Entry] = [
        Entry(sex: .male, title: "Male · Jimmy",
              text: "Long, narrow apron shaped like an upside-down T (or the Washington Monument). Claw tips are blue."),
        Entry(sex: .immatureFemale, title: "Immature female · Sally",
              text: "Triangle-shaped apron that is sealed to the body. Claw tips are red-orange."),
        Entry(sex: .matureFemale, title: "Mature female · Sook",
              text: "Wide, rounded apron shaped like the Capitol dome that can be lifted open. Claw tips are red-orange."),
        Entry(sex: .eggBearing, title: "Egg-bearing female · Sponge",
              text: "A mature female with a spongy mass of orange to brown/black eggs under the apron. Release her — almost every state requires it."),
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Carefully flip the crab over (hold it from behind, away from the claws) and match the apron on its belly.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    HStack(spacing: 10) {
                        Image(systemName: "hand.point.up.left.fill").foregroundStyle(Theme.claw)
                        Text("Quick check from the top: females have red-orange \"painted fingernails\" on their claw tips; males have blue tips.")
                            .font(.subheadline)
                    }
                    .card()

                    ForEach(entries) { entry in
                        HStack(alignment: .center, spacing: 14) {
                            ApronDiagram(sex: entry.sex)
                            VStack(alignment: .leading, spacing: 6) {
                                Text(entry.title).font(.headline)
                                Text(entry.text).font(.subheadline).foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                                if let onPick {
                                    Button("This one") {
                                        onPick(entry.sex)
                                        dismiss()
                                    }
                                    .buttonStyle(.borderedProminent)
                                    .controlSize(.small)
                                }
                            }
                        }
                        .card()
                    }
                }
                .padding()
            }
            .background(Theme.screenBackground)
            .navigationTitle("Is it male or female?")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
