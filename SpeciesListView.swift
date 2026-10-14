import SwiftUI
import SwiftData

/// Species journal: a collection of every species, filled in as you log them.
struct SpeciesListView: View {
    @Query private var records: [CatchRecord]
    @Environment(LocationService.self) private var location
    @Environment(RegulationStore.self) private var regulations
    @AppStorage(SettingsKey.manualState) private var manualState = ""
    @AppStorage(SettingsKey.useMetric) private var useMetric = false

    @State private var group: SpeciesGroup? = nil
    @State private var onlyMyState = false

    private var stateCode: String? { manualState.isEmpty ? location.stateCode : manualState }

    private var stats: [String: SpeciesLogStats] { SpeciesLogStats.build(records) }

    private var visible: [Species] {
        Catalog.all.filter { species in
            if let group, species.group != group { return false }
            if onlyMyState, regulations.rule(species: species.id, state: stateCode) == nil { return false }
            return true
        }
    }

    var body: some View {
        let allStats = stats
        let logged = Catalog.all.filter { allStats[$0.id] != nil }.count

        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("\(logged) of \(Catalog.all.count) species logged")
                            .font(.headline)
                        ProgressView(value: Double(logged), total: Double(max(Catalog.all.count, 1)))
                            .tint(Theme.accent)
                        Text("Log a species to fill in its page. Each one has ID tips, how to measure it, and the rules where you are.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    .card()

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            chip("All", selected: group == nil) { group = nil }
                            ForEach(SpeciesGroup.allCases) { item in
                                chip(item.label, selected: group == item) { group = item }
                            }
                            if let stateCode {
                                chip("Rules in \(stateCode)", selected: onlyMyState) { onlyMyState.toggle() }
                            }
                        }
                    }

                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 158), spacing: 12)], spacing: 12) {
                        ForEach(visible) { species in
                            NavigationLink(value: species) {
                                SpeciesCard(species: species,
                                            stats: allStats[species.id],
                                            hasRules: regulations.rule(species: species.id, state: stateCode) != nil,
                                            metric: useMetric)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding()
            }
            .background(Theme.screenBackground)
            .navigationTitle("Species")
            .navigationDestination(for: Species.self) { species in
                SpeciesDetailView(species: species)
            }
        }
    }

    private func chip(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .foregroundStyle(selected ? Color.white : Color.primary)
                .background(selected ? Theme.accent : Theme.cardBackground, in: Capsule())
        }
        .buttonStyle(.plain)
    }
}

struct SpeciesCard: View {
    let species: Species
    let stats: SpeciesLogStats?
    let hasRules: Bool
    var metric = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                SpeciesGlyph(species: species, size: 54, muted: stats == nil)
                Spacer()
                if hasRules {
                    Image(systemName: "checkmark.shield.fill")
                        .foregroundStyle(Theme.keep)
                        .accessibilityLabel("Rules on file for your state")
                }
            }
            Text(species.commonName)
                .font(.headline)
                .lineLimit(2)
                .minimumScaleFactor(0.85)
            if let stats {
                Text("\(stats.count) logged · best \(Units.format(stats.largest, metric: metric))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text("Not logged yet")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 150, alignment: .topLeading)
        .background(Theme.cardBackground, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(stats == nil ? Color.clear : species.color.opacity(0.5), lineWidth: 1.5)
        )
    }
}
