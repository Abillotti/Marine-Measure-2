import SwiftUI
import UIKit

/// Colored pill such as "Keep" or "Release".
struct VerdictPill: View {
    let kind: VerdictKind

    var body: some View {
        Label(kind.shortTitle, systemImage: kind.symbol)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .foregroundStyle(kind.color)
            .background(kind.color.opacity(0.14), in: Capsule())
            .labelStyle(.titleAndIcon)
    }
}

/// The main keep/release answer.
struct VerdictCard: View {
    let verdict: Verdict
    var metric = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: verdict.kind.symbol)
                    .font(.system(size: 34, weight: .semibold))
                    .foregroundStyle(verdict.kind.color)
                VStack(alignment: .leading, spacing: 4) {
                    Text(verdict.headline)
                        .font(.title2.bold())
                    Text(verdict.detail)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            if let limit = verdict.limitText {
                Label(limit, systemImage: "ruler")
                    .font(.subheadline.weight(.medium))
            }

            ForEach(Array(verdict.reasons.dropFirst()), id: \.self) { reason in
                Label(reason, systemImage: "xmark.circle.fill")
                    .font(.subheadline)
                    .foregroundStyle(Theme.release)
            }
            ForEach(verdict.confirmations, id: \.self) { line in
                Label(line, systemImage: "checkmark.circle.fill")
                    .font(.subheadline)
                    .foregroundStyle(Theme.keep)
            }
            ForEach(verdict.hints.filter { $0 != verdict.detail }, id: \.self) { hint in
                Label(hint, systemImage: "lightbulb.fill")
                    .font(.subheadline)
                    .foregroundStyle(Theme.info)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(verdict.kind.color.opacity(0.10), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(verdict.kind.color.opacity(0.45), lineWidth: 1.5))
    }
}

struct StatTile: View {
    let title: String
    let value: String
    var symbol: String? = nil
    var tint: Color = Theme.accent

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                if let symbol {
                    Image(systemName: symbol).foregroundStyle(tint)
                }
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            Text(value)
                .font(.title3.weight(.bold))
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.cardBackground, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

/// Journal list row.
struct CatchRow: View {
    let record: CatchRecord
    var metric = false

    var body: some View {
        HStack(spacing: 12) {
            Group {
                if let thumbnail = record.thumbnail {
                    Image(uiImage: thumbnail)
                        .resizable()
                        .scaledToFill()
                } else if let species = record.species {
                    SpeciesGlyph(species: species, size: 52)
                } else {
                    Color.gray.opacity(0.2)
                }
            }
            .frame(width: 52, height: 52)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(record.speciesName).font(.headline)
                    if record.isTrophy {
                        Image(systemName: "trophy.fill").foregroundStyle(BadgeTier.gold.color).font(.caption)
                    }
                }
                Text(record.locationLine)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Text(record.date.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 4)
            VStack(alignment: .trailing, spacing: 4) {
                Text(Units.format(record.sizeInches, metric: metric))
                    .font(.headline.monospacedDigit())
                VerdictPill(kind: record.verdict)
            }
        }
        .padding(.vertical, 2)
    }
}

/// Photo with the measuring line drawn where the markers were placed.
struct MeasuredPhotoView: View {
    let image: UIImage
    var markerA: CGPoint?
    var markerB: CGPoint?

    var body: some View {
        Image(uiImage: image)
            .resizable()
            .scaledToFit()
            .overlay {
                GeometryReader { geo in
                    if let markerA, let markerB {
                        let a = CGPoint(x: markerA.x * geo.size.width, y: markerA.y * geo.size.height)
                        let b = CGPoint(x: markerB.x * geo.size.width, y: markerB.y * geo.size.height)
                        Path { path in
                            path.move(to: a)
                            path.addLine(to: b)
                        }
                        .stroke(Theme.measure, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                        .shadow(color: .black.opacity(0.5), radius: 2)
                        Circle().fill(Theme.measure).frame(width: 10, height: 10).position(a)
                        Circle().fill(Theme.measure).frame(width: 10, height: 10).position(b)
                    }
                }
            }
    }
}

/// A file to hand to the share sheet.
struct ShareFile: Identifiable {
    let id = UUID()
    let url: URL
}

/// UIKit share sheet (Save to Files, AirDrop, Mail, ...).
struct ActivityView: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

/// Section title used on scrolling screens.
struct SectionTitle: View {
    let title: String
    var subtitle: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.title3.bold())
            if let subtitle {
                Text(subtitle).font(.subheadline).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
