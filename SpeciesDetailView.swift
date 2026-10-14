import SwiftUI
import SwiftData
import MapKit

/// Species page: your log, ID tips, how to measure, sex guide and the rules.
struct SpeciesDetailView: View {
    let species: Species

    @Query(sort: \CatchRecord.date, order: .reverse) private var allRecords: [CatchRecord]
    @Environment(LocationService.self) private var location
    @Environment(RegulationStore.self) private var regulations
    @Environment(AppState.self) private var appState
    @AppStorage(SettingsKey.manualState) private var manualState = ""
    @AppStorage(SettingsKey.useMetric) private var useMetric = false

    @State private var showScanner = false
    @State private var showSexGuide = false
    @State private var regionRefresh = 0

    private var records: [CatchRecord] { allRecords.filter { $0.speciesID == species.id } }
    private var stateCode: String? { manualState.isEmpty ? location.stateCode : manualState }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                logCard
                identificationCard
                measureCard
                if species.sexMode == .apron { sexCard }
                rulesHereCard
                otherStatesCard
                aboutCard
            }
            .padding()
        }
        .background(Theme.screenBackground)
        .navigationTitle(species.commonName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    appState.scanSpeciesID = species.id
                    showScanner = true
                } label: {
                    Label("Scan", systemImage: "camera.viewfinder")
                }
            }
        }
        .fullScreenCover(isPresented: $showScanner) {
            ScanFlowView(species: species, mode: .camera)
        }
        .sheet(isPresented: $showSexGuide) {
            SexGuideView()
        }
    }

    private var header: some View {
        HStack(spacing: 16) {
            SpeciesGlyph(species: species, size: 84)
            VStack(alignment: .leading, spacing: 4) {
                Text(species.commonName).font(.title2.bold())
                Text(species.scientificName).font(.subheadline.italic()).foregroundStyle(.secondary)
                if !species.nicknames.isEmpty {
                    Text(species.nicknames.joined(separator: " · "))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Label(species.isFreshwater ? "Freshwater" : "Saltwater", systemImage: "drop.fill")
                    .font(.caption)
                    .foregroundStyle(species.color)
            }
        }
    }

    @ViewBuilder
    private var logCard: some View {
        if records.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("Not in your journal yet").font(.headline)
                Text("Scan your first \(species.commonName.lowercased()) to add it to your collection.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Button {
                    appState.scanSpeciesID = species.id
                    showScanner = true
                } label: {
                    Label("Scan one now", systemImage: "camera.viewfinder")
                }
                .buttonStyle(.borderedProminent)
            }
            .card()
        } else {
            let sizes = records.map(\.sizeInches)
            let best = records.max { $0.sizeInches < $1.sizeInches }
            VStack(alignment: .leading, spacing: 12) {
                Text("Your log").font(.headline)
                HStack(spacing: 10) {
                    StatTile(title: "Logged", value: "\(records.count)", symbol: "number")
                    StatTile(title: "Biggest", value: Units.format(sizes.max() ?? 0, metric: useMetric), symbol: "arrow.up.right")
                    StatTile(title: "Average", value: Units.format(sizes.reduce(0, +) / Double(sizes.count), metric: useMetric), symbol: "equal")
                }
                if let best, let photo = best.photo {
                    VStack(alignment: .leading, spacing: 6) {
                        MeasuredPhotoView(image: photo, markerA: best.markerA, markerB: best.markerB)
                            .frame(maxHeight: 220)
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        Text("Best: \(Units.format(best.sizeInches, metric: useMetric)) on \(best.date.formatted(date: .abbreviated, time: .omitted))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                let points = records.compactMap { record -> CatchPoint? in
                    guard let coordinate = record.coordinate else { return nil }
                    return CatchPoint(id: record.uuid, coordinate: coordinate)
                }
                if !points.isEmpty {
                    Map {
                        ForEach(points) { point in
                            Marker("", coordinate: point.coordinate)
                                .tint(species.color)
                        }
                    }
                    .frame(height: 180)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                if let first = records.last?.date {
                    Text("First logged \(first.formatted(date: .abbreviated, time: .omitted))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .card()
        }
    }

    private var identificationCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("How to identify").font(.headline)
            ForEach(species.identification, id: \.self) { line in
                Label(line, systemImage: "eye")
                    .font(.subheadline)
            }
        }
        .card()
    }

    private var measureCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("How to measure").font(.headline)
            MeasureDiagram(species: species, height: 150)
            Text(species.measurementLabel).font(.subheadline.weight(.semibold))
            Text(species.howToMeasure).font(.subheadline).foregroundStyle(.secondary)
        }
        .card()
    }

    private var sexCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Male or female?").font(.headline)
            HStack(spacing: 6) {
                ForEach([CrabSex.male, .immatureFemale, .matureFemale, .eggBearing]) { sex in
                    VStack(spacing: 4) {
                        ApronDiagram(sex: sex, size: 70)
                        Text(sex.crabNickname ?? sex.label)
                            .font(.caption2.weight(.semibold))
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            Button("Open the sex guide") { showSexGuide = true }
                .font(.subheadline)
        }
        .card()
    }

    @ViewBuilder
    private var rulesHereCard: some View {
        let rule = regulations.rule(species: species.id, state: stateCode)
        let stateName = regulations.state(stateCode)?.name ?? stateCode ?? "your state"
        VStack(alignment: .leading, spacing: 10) {
            Text("Rules in \(stateName)").font(.headline)
            if let rule {
                let region = RuleEngine.resolveRegion(
                    rule: rule,
                    preferred: stateCode.flatMap { RegionMemory.region(state: $0, species: species.id) },
                    county: location.county)
                if let regions = rule.regions, !regions.isEmpty, let code = stateCode {
                    Menu {
                        ForEach(regions) { item in
                            Button(item.name) {
                                RegionMemory.set(item.id, state: code, species: species.id)
                                regionRefresh += 1
                            }
                        }
                    } label: {
                        Label(region?.name ?? "Choose your region", systemImage: "map")
                            .font(.subheadline.weight(.medium))
                    }
                    .id(regionRefresh)
                }
                RuleSummaryView(rule: rule, species: species, region: region, metric: useMetric)
            } else {
                Text(stateCode == nil
                     ? "Turn on location or choose a state on the Scan tab to see local rules."
                     : "No \(species.commonName.lowercased()) rules on file for \(stateName). Check the official regulations.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                if let state = regulations.state(stateCode), let url = URL(string: state.regulationsURL) {
                    Link(destination: url) {
                        Label(state.agency, systemImage: "link")
                    }
                    .font(.subheadline)
                }
            }
        }
        .card()
    }

    @ViewBuilder
    private var otherStatesCard: some View {
        let others = regulations.rules(forSpecies: species.id).filter { $0.state != stateCode }
        if !others.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("Other states").font(.headline)
                ForEach(others) { rule in
                    DisclosureGroup(regulations.state(rule.state)?.name ?? rule.state) {
                        RuleSummaryView(rule: rule, species: species, region: nil, metric: useMetric)
                            .padding(.top, 6)
                    }
                    .font(.subheadline)
                }
            }
            .card()
        }
    }

    private var aboutCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Habitat").font(.headline)
            Text(species.habitat).font(.subheadline).foregroundStyle(.secondary)
            Text("Did you know?").font(.headline).padding(.top, 4)
            Text(species.funFact).font(.subheadline).foregroundStyle(.secondary)
        }
        .card()
    }
}

private struct CatchPoint: Identifiable {
    let id: UUID
    let coordinate: CLLocationCoordinate2D
}

/// Plain-language rule breakdown with its source.
struct RuleSummaryView: View {
    let rule: SpeciesRule
    let species: Species
    let region: RegionInfo?
    var metric = false

    var body: some View {
        let summary = RuleEngine.summary(rule: rule, species: species, region: region, metric: metric)
        VStack(alignment: .leading, spacing: 8) {
            ForEach(summary.sizes, id: \.self) { line in
                Label(line, systemImage: "ruler").font(.subheadline)
            }
            ForEach(summary.seasons, id: \.self) { line in
                Label(line, systemImage: "calendar").font(.subheadline)
            }
            ForEach(summary.restrictions, id: \.self) { line in
                Label(line, systemImage: "exclamationmark.shield").font(.subheadline)
            }
            if let bag = summary.bag {
                Label(bag, systemImage: "bag").font(.subheadline)
            }
            ForEach(summary.notes, id: \.self) { line in
                Label(line, systemImage: "info.circle")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            if let url = URL(string: rule.sourceURL) {
                Link(destination: url) {
                    Label("\(rule.sourceName) · verified \(rule.lastVerified)", systemImage: "link")
                        .font(.caption)
                        .multilineTextAlignment(.leading)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
