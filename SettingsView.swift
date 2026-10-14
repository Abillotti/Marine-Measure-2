import SwiftUI
import SwiftData

struct SettingsView: View {
    @Environment(\.modelContext) private var context
    @Environment(RegulationStore.self) private var regulations
    @Environment(CommunityService.self) private var community
    @Environment(LocationService.self) private var location

    @AppStorage(SettingsKey.useMetric) private var useMetric = false
    @AppStorage(SettingsKey.manualState) private var manualState = ""
    @AppStorage(SettingsKey.shareCommunity) private var shareCommunity = false
    @AppStorage(SettingsKey.applyCalibration) private var applyCalibration = false
    @AppStorage(SettingsKey.firebaseProjectID) private var projectID = ""
    @AppStorage(SettingsKey.firebaseAPIKey) private var apiKey = ""
    @AppStorage(SettingsKey.sampleCommunity) private var sampleCommunity = false
    @AppStorage(SettingsKey.regulationsURL) private var regulationsURL = AppConfig.regulationsUpdateURL
    @AppStorage(SettingsKey.hasOnboarded) private var hasOnboarded = true
    @AppStorage(SettingsKey.flatTestMode) private var flatTestMode = false

    @State private var connectionMessage: String? = nil
    @State private var testing = false
    @State private var updating = false
    @State private var confirmWipe = false

    var body: some View {
        Form {
            Section("Units") {
                Toggle("Show sizes in centimeters", isOn: $useMetric)
            }

            Section {
                Picker("State for rules", selection: $manualState) {
                    Text("Automatic (GPS)").tag("")
                    ForEach(regulations.states) { state in
                        Text(state.name).tag(state.code)
                    }
                }
                LabeledContent("GPS says", value: location.summary)
                if location.isDenied {
                    Button("Open iPhone Settings to allow location") {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            UIApplication.shared.open(url)
                        }
                    }
                }
            } header: {
                Text("Location")
            }

            Section {
                LabeledContent("Rules verified", value: regulations.file.lastVerified)
                LabeledContent("Rules on file", value: "\(regulations.file.rules.count) (\(regulations.file.states.count) states)")
                LabeledContent("Source", value: regulations.source)
                TextField("Regulations.json update URL", text: $regulationsURL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
                Button {
                    updating = true
                    Task {
                        await regulations.update(from: regulationsURL)
                        updating = false
                    }
                } label: {
                    if updating { ProgressView() } else { Text("Check for rule updates") }
                }
                .disabled(regulationsURL.isEmpty || updating)
                if regulations.source != "Bundled with the app" {
                    Button("Go back to the bundled rules", role: .destructive) { regulations.resetToBundled() }
                }
                if let message = regulations.lastUpdateMessage {
                    Text(message).font(.footnote).foregroundStyle(.secondary)
                }
            } header: {
                Text("Regulations")
            } footer: {
                Text("Point this at a raw Regulations.json (for example in your GitHub repo) to update rules without rebuilding the app.")
            }

            Section {
                Toggle("Share new catches by default", isOn: $shareCommunity)
                TextField("Firebase project ID", text: $projectID)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                TextField("Firebase Web API key", text: $apiKey)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                Button {
                    testing = true
                    connectionMessage = nil
                    Task {
                        connectionMessage = await community.testConnection()
                        testing = false
                    }
                } label: {
                    if testing { ProgressView() } else { Text("Test connection") }
                }
                .disabled(!community.isConfigured || testing)
                if let connectionMessage {
                    Text(connectionMessage).font(.footnote).foregroundStyle(.secondary)
                }
            } header: {
                Text("Community database")
            } footer: {
                Text(AppConfig.firebaseProjectID.isEmpty
                     ? "Leave blank to keep the community map off. Setup steps are in the README."
                     : "Using the project in AppConfig.swift unless you enter a different one here.")
            }

            Section {
                Toggle("Apply calibration to new scans", isOn: $applyCalibration)
                NavigationLink("Open the Accuracy Lab") { AccuracyLabView() }
            } header: {
                Text("Accuracy")
            }

            Section {
                Toggle("Sample community data", isOn: $sampleCommunity)
                Toggle("Flat-object test mode", isOn: $flatTestMode)
                Button("Show the welcome screens again") { hasOnboarded = false }
                Button("Delete all journal entries", role: .destructive) { confirmWipe = true }
            } header: {
                Text("Developer")
            } footer: {
                Text("Sample data fills the Community tab with clearly labeled fake scans so you can test it before Firebase is set up. Flat-object test mode turns off the catch-height correction so you can check accuracy against a ruler or credit card (3.37 in / 85.6 mm long).")
            }

            Section("About") {
                LabeledContent("Version", value: AppConfig.appVersion)
                NavigationLink("About MarineMeasure") { AboutView() }
            }
        }
        .navigationTitle("Settings")
        .confirmationDialog("Delete every catch in your journal?", isPresented: $confirmWipe, titleVisibility: .visible) {
            Button("Delete everything", role: .destructive) { wipeJournal() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes all catches, photos and badges progress from this iPhone. Shared community scans stay online.")
        }
    }

    private func wipeJournal() {
        if let all = try? context.fetch(FetchDescriptor<CatchRecord>()) {
            for record in all { context.delete(record) }
            try? context.save()
        }
        UserDefaults.standard.removeObject(forKey: SettingsKey.seenBadges)
    }
}

struct AboutView: View {
    @Environment(RegulationStore.self) private var regulations

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 14) {
                    if let crab = Catalog.blueCrab {
                        SpeciesGlyph(species: crab, size: 72)
                    }
                    VStack(alignment: .leading) {
                        Text("MarineMeasure").font(.title.bold())
                        Text("Version \(AppConfig.appVersion)").foregroundStyle(.secondary)
                    }
                }

                Text("Measure a catch with your iPhone, check it against the rules where you're standing, and keep a journal of everything you scan. Shared scans build a community map of blue crab sizes along the coast.")

                VStack(alignment: .leading, spacing: 8) {
                    Text("Research").font(.headline)
                    Text("MarineMeasure grew out of Anthony Billotti's research at the Marine Academy of Technology and Environmental Science (MATES): the Junior Research Project (\"Catch or Release\"), the New Jersey Southern Research Project, and the Senior Capstone. The original study compared app measurements with calipers on blue crabs and found an average percent error of about 2.5% across sizes and backgrounds.")
                        .foregroundStyle(.secondary)
                }
                .card()

                VStack(alignment: .leading, spacing: 8) {
                    Text("Why size limits matter").font(.headline)
                    Text("Possession of undersized crabs is the most common recreational crabbing violation. Size limits protect juveniles until they can reproduce, which keeps blue crab populations — and everything in the food web that depends on them — healthy.")
                        .foregroundStyle(.secondary)
                }
                .card()

                VStack(alignment: .leading, spacing: 8) {
                    Text("Important").font(.headline)
                    Text(regulations.file.disclaimer)
                        .foregroundStyle(.secondary)
                    Text("Measurements from a phone camera have an error margin. When a catch is close to a limit, MarineMeasure says so — check it with a gauge.")
                        .foregroundStyle(.secondary)
                }
                .card()
            }
            .padding()
        }
        .background(Theme.screenBackground)
        .navigationTitle("About")
        .navigationBarTitleDisplayMode(.inline)
    }
}
