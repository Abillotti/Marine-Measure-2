import SwiftUI
import SwiftData

/// Scan tab: where you are, what the rules are, and the big scan button.
struct HomeView: View {
    @Environment(LocationService.self) private var location
    @Environment(RegulationStore.self) private var regulations
    @Environment(AppState.self) private var appState
    @Query(sort: \CatchRecord.date, order: .reverse) private var records: [CatchRecord]

    @AppStorage(SettingsKey.manualState) private var manualState = ""
    @AppStorage(SettingsKey.useMetric) private var useMetric = false
    @AppStorage(SettingsKey.favoriteSpecies) private var favoriteSpecies = "blue_crab"

    @State private var showScanner = false
    @State private var showManual = false
    @State private var regionRefresh = 0

    private var species: Species? {
        Catalog.speciesOrFirst(appState.scanSpeciesID)
    }

    private var stateCode: String? {
        manualState.isEmpty ? location.stateCode : manualState
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    locationCard
                    if let species {
                        speciesPicker(species)
                        rulesCard(species)
                        scanButtons
                    }
                    recentSection
                    tipCard
                }
                .padding()
            }
            .background(Theme.screenBackground)
            .navigationTitle("MarineMeasure")
            .navigationDestination(for: CatchRecord.self) { record in
                CatchDetailView(record: record)
            }
            .fullScreenCover(isPresented: $showScanner) {
                if let species {
                    ScanFlowView(species: species, mode: .camera)
                }
            }
            .sheet(isPresented: $showManual) {
                if let species {
                    ScanFlowView(species: species, mode: .manual)
                }
            }
            .onAppear { location.requestPermission() }
        }
    }

    // MARK: Location

    private var locationCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(manualState.isEmpty ? "You're in" : "Rules for")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.8))
                    Text(locationTitle)
                        .font(.title2.bold())
                        .foregroundStyle(.white)
                    if let state = regulations.state(stateCode) {
                        Text(state.agency)
                            .font(.footnote)
                            .foregroundStyle(.white.opacity(0.8))
                    }
                }
                Spacer()
                Menu {
                    Picker("State", selection: $manualState) {
                        Label("Use my location", systemImage: "location.fill").tag("")
                        ForEach(regulations.states) { state in
                            Text(state.name).tag(state.code)
                        }
                    }
                } label: {
                    Image(systemName: "mappin.and.ellipse")
                        .font(.title3)
                        .foregroundStyle(.white)
                        .padding(10)
                        .background(.white.opacity(0.18), in: Circle())
                }
                .accessibilityLabel("Change state")
            }
            if manualState.isEmpty && location.isDenied {
                Label("Location is off. Pick a state with the pin button, or allow location in Settings.", systemImage: "location.slash")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.9))
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.oceanGradient, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private var locationTitle: String {
        if !manualState.isEmpty {
            return regulations.state(manualState)?.name ?? StateNames.name(for: manualState)
        }
        if location.stateCode != nil { return location.summary }
        if location.isAuthorized { return "Finding you…" }
        return "Location unknown"
    }

    // MARK: Species

    private func speciesPicker(_ species: Species) -> some View {
        Menu {
            ForEach(SpeciesGroup.allCases) { group in
                Section(group.label) {
                    ForEach(Catalog.all.filter { $0.group == group }) { item in
                        Button {
                            appState.scanSpeciesID = item.id
                            favoriteSpecies = item.id
                        } label: {
                            if item.id == species.id {
                                Label(item.commonName, systemImage: "checkmark")
                            } else {
                                Text(item.commonName)
                            }
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: 12) {
                SpeciesGlyph(species: species, size: 48)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Measuring")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(species.commonName)
                        .font(.headline)
                        .foregroundStyle(.primary)
                    Text(species.measurementLabel)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.up.chevron.down")
                    .foregroundStyle(.secondary)
            }
            .card(padding: 14)
        }
    }

    // MARK: Rules preview

    @ViewBuilder
    private func rulesCard(_ species: Species) -> some View {
        let today = RuleEngine.evaluate(
            RuleInput(species: species, stateCode: stateCode,
                      regionID: stateCode.flatMap { RegionMemory.region(state: $0, species: species.id) },
                      county: location.county, date: Date(), sizeInches: nil, uncertaintyInches: 0,
                      attributes: CatchAttributes(), metric: useMetric),
            store: regulations)

        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Today's rules").font(.headline)
                Spacer()
                if let open = today.seasonOpen {
                    Label(open ? "Season open" : "Season closed", systemImage: open ? "checkmark.circle.fill" : "xmark.octagon.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(open ? Theme.keep : Theme.release)
                }
            }

            if let rule = today.rule {
                if let regions = rule.regions, !regions.isEmpty, let code = stateCode {
                    Menu {
                        ForEach(regions) { region in
                            Button(region.name) {
                                RegionMemory.set(region.id, state: code, species: species.id)
                                regionRefresh += 1
                            }
                        }
                    } label: {
                        HStack {
                            Image(systemName: "map")
                            Text(today.region?.name ?? "Choose your region")
                            Image(systemName: "chevron.down").font(.caption)
                        }
                        .font(.subheadline.weight(.medium))
                    }
                    .id(regionRefresh)
                }
                let summary = RuleEngine.summary(rule: rule, species: species, region: today.region, metric: useMetric)
                ForEach(summary.sizes.prefix(4), id: \.self) { line in
                    Label(line, systemImage: "ruler")
                        .font(.subheadline)
                }
                ForEach(summary.restrictions.prefix(2), id: \.self) { line in
                    Label(line, systemImage: "exclamationmark.shield")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                if let bag = rule.bagLimit {
                    Label(bag, systemImage: "bag")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            } else {
                Text(today.detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                if let state = regulations.state(stateCode), let url = URL(string: state.regulationsURL) {
                    Link(destination: url) {
                        Label("Open \(state.agency)", systemImage: "link")
                            .font(.subheadline)
                    }
                }
            }
        }
        .card()
    }

    // MARK: Actions

    private var scanButtons: some View {
        VStack(spacing: 10) {
            Button {
                showScanner = true
            } label: {
                HStack {
                    Image(systemName: "camera.viewfinder")
                    Text("Scan with camera")
                }
                .font(.title3.bold())
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)

            Button {
                showManual = true
            } label: {
                Label("Enter a size from a gauge", systemImage: "keyboard")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
        }
    }

    @ViewBuilder
    private var recentSection: some View {
        if !records.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Recent catches").font(.headline)
                    Spacer()
                    Button("See all") { appState.selectedTab = .journal }
                        .font(.subheadline)
                }
                VStack(spacing: 0) {
                    ForEach(records.prefix(3)) { record in
                        NavigationLink(value: record) {
                            CatchRow(record: record, metric: useMetric)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                        }
                        .buttonStyle(.plain)
                        if record.uuid != records.prefix(3).last?.uuid {
                            Divider().padding(.leading, 76)
                        }
                    }
                }
                .background(Theme.cardBackground, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            }
        }
    }

    private var tipCard: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "lightbulb.max.fill")
                .font(.title2)
                .foregroundStyle(Theme.caution)
            VStack(alignment: .leading, spacing: 4) {
                Text("Measuring tip").font(.headline)
                Text("Set the catch on a cooler lid or dock board, hold the phone about 30–50 cm (a forearm's length) straight above it, and wait for the green Ready ring before you capture.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .card()
    }
}
