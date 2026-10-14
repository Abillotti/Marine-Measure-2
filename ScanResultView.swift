import SwiftUI
import SwiftData

/// Shows the measurement and the keep/release verdict, collects the details the
/// rules need (sex, shell, region...), and saves the catch to the journal.
struct ScanResultView: View {
    let species: Species
    let canRetake: Bool
    var onRetake: () -> Void
    var onFinished: () -> Void

    @Environment(\.modelContext) private var context
    @Environment(LocationService.self) private var location
    @Environment(RegulationStore.self) private var regulations
    @Environment(CommunityService.self) private var community
    @Environment(AppState.self) private var appState
    @Query private var allRecords: [CatchRecord]

    @AppStorage(SettingsKey.useMetric) private var useMetric = false
    @AppStorage(SettingsKey.shareCommunity) private var shareByDefault = false
    @AppStorage(SettingsKey.manualState) private var manualState = ""
    @AppStorage(SettingsKey.seenBadges) private var seenBadges = ""

    @State private var draft: ScanDraft
    @State private var shareThis = false
    @State private var showSexGuide = false
    @State private var confirmKeep = false
    @State private var gaugeText = ""
    @State private var aiSuggestion: SexClassifier.Suggestion? = nil
    @State private var prepared = false
    @State private var showAllRules = false

    init(species: Species, draft: ScanDraft, canRetake: Bool,
         onRetake: @escaping () -> Void, onFinished: @escaping () -> Void) {
        self.species = species
        self.canRetake = canRetake
        self.onRetake = onRetake
        self.onFinished = onFinished
        _draft = State(initialValue: draft)
    }

    private var verdict: Verdict {
        RuleEngine.evaluate(
            RuleInput(species: species,
                      stateCode: draft.stateCode,
                      regionID: draft.regionID,
                      county: draft.county,
                      date: draft.date,
                      sizeInches: draft.sizeInches,
                      uncertaintyInches: draft.method == .manual ? 0 : draft.uncertaintyInches,
                      attributes: draft.attributes,
                      metric: useMetric),
            store: regulations)
    }

    private var rule: SpeciesRule? {
        regulations.rule(species: species.id, state: draft.stateCode)
    }

    var body: some View {
        let current = verdict
        ScrollView {
            VStack(spacing: 16) {
                if let photo = draft.photo {
                    MeasuredPhotoView(image: photo, markerA: draft.markerA, markerB: draft.markerB)
                        .frame(maxHeight: 300)
                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                }
                sizeCard
                VerdictCard(verdict: current, metric: useMetric)
                detailsCard(current)
                rulesCard(current)
                actionButtons(current)
            }
            .padding()
        }
        .background(Theme.screenBackground)
        .navigationTitle(species.commonName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Discard", role: .destructive) { onFinished() }
            }
            if canRetake {
                ToolbarItem(placement: .primaryAction) {
                    Button("Retake", action: onRetake)
                }
            }
        }
        .sheet(isPresented: $showSexGuide) {
            SexGuideView { sex in
                draft.attributes.sex = sex
            }
        }
        .confirmationDialog("MarineMeasure says to release this catch.", isPresented: $confirmKeep, titleVisibility: .visible) {
            Button("Save as kept anyway", role: .destructive) { save(outcome: .kept) }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Keeping an illegal catch can mean a fine. Double-check with a gauge and the official rules.")
        }
        .sensoryFeedback(trigger: current.kind) { _, newKind in
            switch newKind {
            case .keep: return .success
            case .release: return .warning
            default: return nil
            }
        }
        .onAppear(perform: prepare)
    }

    // MARK: Sections

    private var sizeCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(species.measurementLabel)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(Units.number(draft.sizeInches, metric: useMetric))
                    .font(.system(size: 52, weight: .bold, design: .rounded).monospacedDigit())
                Text(Units.unitLabel(metric: useMetric))
                    .font(.title2.weight(.semibold))
                if draft.method != .manual {
                    Text(Units.uncertainty(draft.uncertaintyInches, metric: useMetric))
                        .font(.headline)
                        .foregroundStyle(.secondary)
                }
            }
            HStack(spacing: 10) {
                Label(draft.method == .manual ? "Entered by hand" : draft.method.label, systemImage: draft.method.symbol)
                if draft.calibrationFactor != 1 {
                    Label("Calibrated", systemImage: "slider.horizontal.3")
                }
                if let distance = draft.cameraDistanceMeters {
                    Label("\(Int((distance * 100).rounded())) cm away", systemImage: "arrow.down.to.line")
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            ForEach(draft.warnings, id: \.self) { warning in
                Label(warning, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(Theme.caution)
            }
        }
        .card()
    }

    private func detailsCard(_ current: Verdict) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("About this catch").font(.headline)

            row("State") {
                Picker("State", selection: $draft.stateCode) {
                    Text("Choose…").tag(String?.none)
                    ForEach(regulations.states) { state in
                        Text(state.name).tag(Optional(state.code))
                    }
                }
                .pickerStyle(.menu)
            }

            if let rule, let regions = rule.regions, !regions.isEmpty {
                row("Region") {
                    Picker("Region", selection: regionBinding) {
                        Text("Choose…").tag(String?.none)
                        ForEach(regions) { region in
                            Text(region.name).tag(Optional(region.id))
                        }
                    }
                    .pickerStyle(.menu)
                }
                if let detail = current.region?.detail {
                    Text(detail).font(.caption).foregroundStyle(.secondary)
                }
            }

            switch species.sexMode {
            case .apron:
                row("Sex") {
                    Picker("Sex", selection: $draft.attributes.sex) {
                        ForEach(CrabSex.allCases) { sex in
                            Text(sexLabel(sex)).tag(sex)
                        }
                    }
                    .pickerStyle(.menu)
                }
                HStack {
                    Button {
                        showSexGuide = true
                    } label: {
                        Label("How to tell", systemImage: "questionmark.circle")
                    }
                    .font(.subheadline)
                    Spacer()
                    if let aiSuggestion {
                        Button {
                            draft.attributes.sex = aiSuggestion.sex
                        } label: {
                            Label("AI: \(aiSuggestion.label) \(Int(aiSuggestion.confidence * 100))%", systemImage: "sparkles")
                        }
                        .font(.subheadline)
                    }
                }
            case .eggs:
                Toggle("Carrying eggs", isOn: Binding(
                    get: { draft.attributes.sex == .eggBearing },
                    set: { draft.attributes.sex = $0 ? .eggBearing : .unknown }))
            case .none:
                EmptyView()
            }

            if draft.attributes.sex == .eggBearing && ruleMentions("darkSponge") {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Egg color").font(.subheadline)
                    Picker("Egg color", selection: $draft.attributes.eggColor) {
                        ForEach(EggColor.allCases) { color in
                            Text(color.label).tag(color)
                        }
                    }
                    .pickerStyle(.segmented)
                }
            }

            if species.askShell {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Shell").font(.subheadline)
                    Picker("Shell", selection: $draft.attributes.shell) {
                        ForEach(ShellStage.allCases) { shell in
                            Text(shell.label).tag(shell)
                        }
                    }
                    .pickerStyle(.segmented)
                    Text(draft.attributes.shell.detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if draft.method != .manual {
                VStack(alignment: .leading, spacing: 4) {
                    TextField("Gauge reading in \(Units.unitLabel(metric: useMetric)) (optional)", text: $gaugeText)
                        .keyboardType(.decimalPad)
                        .textFieldStyle(.roundedBorder)
                    Text("Measured it with a gauge or caliper too? Add it to track the app's accuracy in the Accuracy Lab.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            TextField("Notes (bait, tide, spot…)", text: $draft.notes, axis: .vertical)
                .lineLimit(1...4)
                .textFieldStyle(.roundedBorder)

            if community.isConfigured {
                Toggle(isOn: $shareThis) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Share with the community map")
                        Text("Anonymous · location rounded to about 1 km")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .card()
    }

    @ViewBuilder
    private func rulesCard(_ current: Verdict) -> some View {
        if let rule = current.rule {
            VStack(alignment: .leading, spacing: 10) {
                Text("\(current.stateName ?? rule.state) rules").font(.headline)
                if let bag = current.bagLimit {
                    Label(bag, systemImage: "bag")
                        .font(.subheadline)
                }
                ForEach(current.notes, id: \.self) { note in
                    Label(note, systemImage: "info.circle")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                DisclosureGroup("Full rule summary", isExpanded: $showAllRules) {
                    let summary = RuleEngine.summary(rule: rule, species: species, region: current.region, metric: useMetric)
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(summary.sizes + summary.seasons + summary.restrictions, id: \.self) { line in
                            Text("• " + line).font(.footnote)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 6)
                }
                .font(.subheadline)
                if let url = URL(string: rule.sourceURL) {
                    Link(destination: url) {
                        Label("Source: \(rule.sourceName)", systemImage: "link")
                            .font(.footnote)
                            .multilineTextAlignment(.leading)
                    }
                }
                Text("Verified \(rule.lastVerified). \(regulations.file.disclaimer)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .card()
        } else if let state = regulations.state(draft.stateCode), let url = URL(string: state.regulationsURL) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Check the official rules").font(.headline)
                Link(destination: url) {
                    Label(state.agency, systemImage: "link")
                }
            }
            .card()
        }
    }

    private func actionButtons(_ current: Verdict) -> some View {
        VStack(spacing: 10) {
            Button {
                save(outcome: .released)
            } label: {
                Label("I released it", systemImage: "water.waves")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(Theme.teal)
            .controlSize(.large)

            Button {
                if current.kind == .release || current.kind == .borderline {
                    confirmKeep = true
                } else {
                    save(outcome: .kept)
                }
            } label: {
                Label("I kept it", systemImage: "bag.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)

            Button("Save without choosing") { save(outcome: .undecided) }
                .font(.footnote)
                .padding(.top, 2)
        }
        .padding(.bottom, 20)
    }

    private func row<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        HStack {
            Text(title)
            Spacer()
            content()
        }
    }

    // MARK: Helpers

    private var regionBinding: Binding<String?> {
        Binding(
            get: { draft.regionID },
            set: { newValue in
                draft.regionID = newValue
                if let code = draft.stateCode {
                    RegionMemory.set(newValue, state: code, species: species.id)
                }
            })
    }

    private func sexLabel(_ sex: CrabSex) -> String {
        if species.id == "blue_crab", let nickname = sex.crabNickname {
            return "\(sex.label) (\(nickname))"
        }
        return sex.label
    }

    private func ruleMentions(_ condition: String) -> Bool {
        rule?.prohibitions?.contains { $0.condition == condition } ?? false
    }

    private var parsedGauge: Double? {
        let text = gaugeText.replacingOccurrences(of: ",", with: ".").trimmingCharacters(in: .whitespaces)
        guard let value = Double(text), value > 0 else { return nil }
        return useMetric ? Units.inches(fromCentimeters: value) : value
    }

    private func prepare() {
        guard !prepared else { return }
        prepared = true
        if draft.stateCode == nil {
            draft.stateCode = manualState.isEmpty ? location.stateCode : manualState
        }
        if draft.latitude == nil, let current = location.location {
            draft.latitude = current.coordinate.latitude
            draft.longitude = current.coordinate.longitude
        }
        if draft.county == nil { draft.county = location.county }
        if draft.placeName == nil { draft.placeName = location.placeName }
        if draft.waterBody == nil { draft.waterBody = location.waterBody }
        if draft.regionID == nil, let code = draft.stateCode {
            draft.regionID = RegionMemory.region(state: code, species: species.id)
            if draft.regionID == nil, let rule = regulations.rule(species: species.id, state: code) {
                draft.regionID = RuleEngine.suggestedRegion(rule: rule, county: draft.county)?.id
            }
        }
        shareThis = shareByDefault && community.isConfigured
        runAISuggestion()
    }

    private func runAISuggestion() {
        guard species.sexMode == .apron, SexClassifier.isAvailable, let cgImage = draft.photo?.cgImage else { return }
        Task {
            let suggestion = await Task.detached(priority: .userInitiated) {
                SexClassifier.classify(cgImage)
            }.value
            aiSuggestion = suggestion
        }
    }

    private func save(outcome: CatchOutcome) {
        let finalVerdict = verdict
        let unlockedBefore = BadgeEngine.unlockedIDs(allRecords)

        let record = CatchRecord(speciesID: species.id, date: draft.date)
        record.sizeInches = draft.sizeInches
        record.rawSizeInches = draft.rawInches
        record.uncertaintyInches = draft.method == .manual ? 0 : draft.uncertaintyInches
        record.method = draft.method
        record.calibrationFactor = draft.calibrationFactor
        record.gaugeInches = draft.method == .manual ? nil : parsedGauge
        record.cameraDistanceMeters = draft.cameraDistanceMeters
        record.sex = draft.attributes.sex
        record.eggColor = draft.attributes.eggColor
        record.shell = species.askShell ? draft.attributes.shell : .hard
        record.verdict = finalVerdict.kind
        record.verdictHeadline = finalVerdict.headline
        record.verdictDetail = finalVerdict.detail
        record.outcome = outcome
        record.stateCode = draft.stateCode ?? ""
        record.regionID = finalVerdict.region?.id ?? (draft.regionID ?? "")
        record.county = draft.county ?? ""
        record.placeName = draft.placeName ?? ""
        record.waterBody = draft.waterBody ?? ""
        record.latitude = draft.latitude
        record.longitude = draft.longitude
        record.notes = draft.notes.trimmingCharacters(in: .whitespacesAndNewlines)
        record.setPhoto(draft.photo)
        if let a = draft.markerA, let b = draft.markerB {
            record.markerAX = Double(a.x)
            record.markerAY = Double(a.y)
            record.markerBX = Double(b.x)
            record.markerBY = Double(b.y)
        }
        context.insert(record)
        try? context.save()

        // Badges unlocked by this catch
        var everything = allRecords
        if !everything.contains(where: { $0.uuid == record.uuid }) { everything.append(record) }
        let unlockedNow = BadgeEngine.unlockedIDs(everything)
        var seen = Set(seenBadges.split(separator: ",").map(String.init))
        let fresh = unlockedNow.subtracting(unlockedBefore).subtracting(seen)
        seen.formUnion(unlockedNow)
        seenBadges = seen.sorted().joined(separator: ",")
        let newBadges = BadgeEngine.all.filter { fresh.contains($0.id) }

        if shareThis && community.isConfigured {
            let service = community
            let modelContext = context
            Task { @MainActor in
                if let documentID = try? await service.share(record) {
                    record.communityDocID = documentID
                    try? modelContext.save()
                }
            }
        }

        onFinished()
        if !newBadges.isEmpty {
            let state = appState
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                state.celebrate(newBadges)
            }
        }
    }
}
