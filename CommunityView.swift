import SwiftUI
import Charts
import MapKit

/// Community science: everyone's shared scans, mapped and summarized by area.
struct CommunityView: View {
    @Environment(CommunityService.self) private var community
    @Environment(RegulationStore.self) private var regulations
    @Environment(LocationService.self) private var location
    @AppStorage(SettingsKey.sampleCommunity) private var sampleMode = false
    @AppStorage(SettingsKey.useMetric) private var useMetric = false
    @AppStorage(SettingsKey.manualState) private var manualState = ""
    @AppStorage(SettingsKey.firebaseProjectID) private var customProjectID = ""

    @State private var speciesID = "blue_crab"
    @State private var range: TimeRange = .year
    @State private var mapPosition: MapCameraPosition = .automatic

    enum TimeRange: String, CaseIterable, Identifiable {
        case month = "30 days"
        case year = "12 months"
        case all = "All time"
        var id: String { rawValue }

        var cutoff: Date {
            switch self {
            case .month: return Date().addingTimeInterval(-30 * 86_400)
            case .year: return Date().addingTimeInterval(-365 * 86_400)
            case .all: return .distantPast
            }
        }
    }

    private var species: Species? { Catalog.species(speciesID) }
    private var stateCode: String? { manualState.isEmpty ? location.stateCode : manualState }

    private var scans: [CommunityScan] {
        let cutoff = range.cutoff
        return community.scans.filter { $0.speciesID == speciesID && $0.takenAt >= cutoff }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if sampleMode {
                        Label("Sample data — these are not real scans. Turn this off in Settings › Developer.", systemImage: "testtube.2")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(Theme.caution)
                            .card(padding: 12)
                    }
                    controls
                    content
                }
                .padding()
            }
            .background(Theme.screenBackground)
            .navigationTitle("Community")
            .task(id: "\(speciesID)|\(sampleMode)|\(customProjectID)") {
                await community.load(speciesID: speciesID, sample: sampleMode)
            }
            .refreshable {
                await community.load(speciesID: speciesID, sample: sampleMode)
            }
        }
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: 10) {
            Menu {
                Picker("Species", selection: $speciesID) {
                    ForEach(Catalog.all) { item in
                        Text(item.commonName).tag(item.id)
                    }
                }
            } label: {
                HStack(spacing: 10) {
                    if let species { SpeciesGlyph(species: species, size: 36) }
                    Text(species?.commonName ?? "Species").font(.headline).foregroundStyle(.primary)
                    Image(systemName: "chevron.up.chevron.down").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                }
            }
            Picker("Time", selection: $range) {
                ForEach(TimeRange.allCases) { item in
                    Text(item.rawValue).tag(item)
                }
            }
            .pickerStyle(.segmented)
        }
    }

    @ViewBuilder
    private var content: some View {
        if !community.isConfigured && !sampleMode {
            setupCard
        } else {
            switch community.loadState {
            case .loading where community.scans.isEmpty:
                ProgressView("Loading community scans…")
                    .frame(maxWidth: .infinity)
                    .padding(40)
            case .failed(let message):
                errorCard(message)
            default:
                if scans.isEmpty {
                    ContentUnavailableView {
                        Label("No scans yet", systemImage: "map")
                    } description: {
                        Text("Nobody has shared a \(species?.commonName.lowercased() ?? "catch") in this time range. Share yours from the result screen or the journal.")
                    }
                } else {
                    dashboard(CommunityStats(scans: scans))
                }
            }
        }
    }

    // MARK: Dashboard

    private func dashboard(_ stats: CommunityStats) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                StatTile(title: "Scans", value: "\(stats.count)", symbol: "number")
                StatTile(title: "Average size", value: Units.format(stats.average, metric: useMetric), symbol: "ruler")
                StatTile(title: "Median", value: Units.format(stats.median, metric: useMetric), symbol: "chart.bar")
                StatTile(title: "Largest", value: Units.format(stats.largest, metric: useMetric), symbol: "trophy.fill", tint: BadgeTier.gold.color)
                if let legal = stats.legalPercent {
                    StatTile(title: "Legal size", value: String(format: "%.0f%%", legal), symbol: "checkmark.seal.fill", tint: Theme.keep)
                }
                if let male = stats.malePercent {
                    StatTile(title: "Males", value: String(format: "%.0f%%", male), symbol: "person.fill", tint: Theme.accent)
                }
            }

            mapCard(stats)
            histogramCard(stats)
            if stats.months.count >= 2 { trendCard(stats) }
            areasCard(stats)

            Text("Shared scans are anonymous. Locations are rounded to about 1 km before they leave the phone, and the map groups them into ~11 km squares.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func mapCard(_ stats: CommunityStats) -> some View {
        let low = stats.cells.map(\.average).min() ?? 0
        let high = stats.cells.map(\.average).max() ?? 1
        return VStack(alignment: .leading, spacing: 8) {
            Text("Where they're caught").font(.headline)
            Map(position: $mapPosition) {
                ForEach(stats.cells) { cell in
                    MapCircle(center: cell.center, radius: radius(for: cell.count))
                        .foregroundStyle(color(for: cell.average, low: low, high: high).opacity(0.45))
                        .stroke(color(for: cell.average, low: low, high: high), lineWidth: 1.5)
                }
                if let current = location.location?.coordinate {
                    Marker("You", systemImage: "location.fill", coordinate: current)
                        .tint(Theme.accent)
                }
            }
            .mapStyle(.standard(pointsOfInterest: .excludingAll))
            .frame(height: 300)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

            HStack(spacing: 8) {
                Text(Units.format(low, metric: useMetric)).font(.caption2)
                LinearGradient(colors: [color(for: 0, low: 0, high: 1), color(for: 0.5, low: 0, high: 1), color(for: 1, low: 0, high: 1)],
                               startPoint: .leading, endPoint: .trailing)
                    .frame(height: 8)
                    .clipShape(Capsule())
                Text(Units.format(high, metric: useMetric)).font(.caption2)
            }
            Text("Circle size = number of scans · color = average size")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .card()
    }

    private func histogramCard(_ stats: CommunityStats) -> some View {
        let factor = useMetric ? Units.centimetersPerInch : 1
        let minimum = legalMinimum
        return VStack(alignment: .leading, spacing: 8) {
            Text("Size distribution").font(.headline)
            Chart {
                ForEach(stats.bins) { bin in
                    BarMark(xStart: .value("From", bin.lower * factor),
                            xEnd: .value("To", bin.upper * factor),
                            y: .value("Scans", bin.count))
                    .foregroundStyle(Theme.accent.gradient)
                }
                if let minimum {
                    RuleMark(x: .value("Minimum", minimum * factor))
                        .foregroundStyle(Theme.release)
                        .lineStyle(StrokeStyle(lineWidth: 2, dash: [5, 4]))
                        .annotation(position: .top, alignment: .leading) {
                            Text("\(stateCode ?? "") min").font(.caption2).foregroundStyle(Theme.release)
                        }
                }
            }
            .chartXAxisLabel("Size (\(Units.unitLabel(metric: useMetric)))")
            .chartYAxisLabel("Scans")
            .frame(height: 200)
            Text(String(format: "Standard deviation %.2f %@", stats.standardDeviation * factor, Units.unitLabel(metric: useMetric)))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .card()
    }

    private func trendCard(_ stats: CommunityStats) -> some View {
        let factor = useMetric ? Units.centimetersPerInch : 1
        return VStack(alignment: .leading, spacing: 8) {
            Text("Average size by month").font(.headline)
            Chart(stats.months) { month in
                LineMark(x: .value("Month", month.month, unit: .month),
                         y: .value("Average", month.average * factor))
                    .foregroundStyle(Theme.teal)
                PointMark(x: .value("Month", month.month, unit: .month),
                          y: .value("Average", month.average * factor))
                    .foregroundStyle(Theme.teal)
            }
            .chartYScale(domain: .automatic(includesZero: false))
            .frame(height: 180)
        }
        .card()
    }

    private func areasCard(_ stats: CommunityStats) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("By area").font(.headline)
            ForEach(stats.areas.prefix(15)) { area in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(area.county.isEmpty ? (regulations.state(area.state)?.name ?? area.state) : area.county)
                            .font(.subheadline.weight(.semibold))
                        Text("\(area.state) · \(area.count) scans")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(Units.format(area.average, metric: useMetric))
                            .font(.subheadline.monospacedDigit())
                        if let legal = area.legalPercent {
                            Text(String(format: "%.0f%% legal", legal))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                Divider()
            }
        }
        .card()
    }

    // MARK: Setup / errors

    private var setupCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Turn on the community map", systemImage: "person.3.fill").font(.headline)
            Text("The community map pools everyone's shared scans so you can compare blue crab sizes across bays, counties and states. It needs a free Firebase project:")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 6) {
                Text("1. Create a project at console.firebase.google.com")
                Text("2. Turn on Authentication › Anonymous and Firestore")
                Text("3. Paste firebase/firestore.rules into Firestore › Rules")
                Text("4. Enter the project ID and Web API key in Settings › Community database (or in AppConfig.swift)")
            }
            .font(.footnote)
            Text("Want to see what it looks like first? Turn on sample data in Settings › Developer.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .card()
    }

    private func errorCard(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Couldn't load community scans", systemImage: "exclamationmark.triangle.fill")
                .font(.headline)
                .foregroundStyle(Theme.caution)
            Text(message).font(.footnote).foregroundStyle(.secondary)
            if let link = community.indexLink {
                Link(destination: link) {
                    Label("Create the Firestore index (one tap)", systemImage: "wrench.and.screwdriver")
                }
                Text("Firestore needs a one-time index for this query. Open the link, tap Save, wait a minute, then pull down to refresh.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Button("Try again") {
                Task { await community.load(speciesID: speciesID, sample: sampleMode) }
            }
        }
        .card()
    }

    // MARK: Helpers

    /// Hard-shell / general minimum for the current state, drawn on the histogram.
    private var legalMinimum: Double? {
        guard let rule = regulations.rule(species: speciesID, state: stateCode) else { return nil }
        let general = rule.sizeLimits.filter { limit in
            limit.regions == nil && limit.start == nil &&
            (limit.shells == nil || limit.shells?.contains(ShellStage.hard.rawValue) == true)
        }
        return general.compactMap(\.min).max()
    }

    private func radius(for count: Int) -> CLLocationDistance {
        min(9_000, 1_500 + 1_100 * Double(count).squareRoot())
    }

    private func color(for value: Double, low: Double, high: Double) -> Color {
        let span = max(high - low, 0.0001)
        let t = min(1, max(0, (value - low) / span))
        // blue (small) → green → orange/red (large)
        return Color(hue: 0.60 - 0.58 * t, saturation: 0.75, brightness: 0.88)
    }
}
