import SwiftUI
import SwiftData
import MapKit

/// One journal entry: photo, size, verdict, details, gauge comparison, map, sharing.
struct CatchDetailView: View {
    @Bindable var record: CatchRecord

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(CommunityService.self) private var community
    @AppStorage(SettingsKey.useMetric) private var useMetric = false

    @State private var gaugeText = ""
    @State private var confirmDelete = false
    @State private var shareMessage: String? = nil
    @State private var working = false
    @State private var showSexGuide = false

    var body: some View {
        List {
            Section {
                if let photo = record.photo {
                    MeasuredPhotoView(image: photo, markerA: record.markerA, markerB: record.markerB)
                        .frame(maxHeight: 340)
                        .frame(maxWidth: .infinity)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .listRowInsets(EdgeInsets(top: 8, leading: 8, bottom: 8, trailing: 8))
                }
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(Units.number(record.sizeInches, metric: useMetric))
                            .font(.system(size: 44, weight: .bold, design: .rounded).monospacedDigit())
                        Text(Units.unitLabel(metric: useMetric)).font(.title3.weight(.semibold))
                        if record.method != .manual {
                            Text(Units.uncertainty(record.uncertaintyInches, metric: useMetric))
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        if record.isTrophy {
                            Image(systemName: "trophy.fill").foregroundStyle(BadgeTier.gold.color).font(.title2)
                        }
                    }
                    HStack {
                        VerdictPill(kind: record.verdict)
                        Text(record.verdictHeadline).font(.subheadline.weight(.semibold))
                    }
                    if !record.verdictDetail.isEmpty {
                        Text(record.verdictDetail).font(.footnote).foregroundStyle(.secondary)
                    }
                    Text(record.date.formatted(date: .complete, time: .shortened))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Details") {
                LabeledContent("Species", value: record.speciesName)
                LabeledContent("Method", value: record.method.label)
                if let species = record.species {
                    switch species.sexMode {
                    case .apron:
                        Picker("Sex", selection: $record.sex) {
                            ForEach(CrabSex.allCases) { sex in
                                Text(sex.label).tag(sex)
                            }
                        }
                        Button("How to tell the sex") { showSexGuide = true }
                            .font(.footnote)
                    case .eggs:
                        Toggle("Carrying eggs", isOn: Binding(
                            get: { record.sex == .eggBearing },
                            set: { record.sex = $0 ? .eggBearing : .unknown }))
                    case .none:
                        EmptyView()
                    }
                    if species.askShell {
                        Picker("Shell", selection: $record.shell) {
                            ForEach(ShellStage.allCases) { shell in
                                Text(shell.label).tag(shell)
                            }
                        }
                    }
                }
                Picker("What you did", selection: $record.outcome) {
                    ForEach(CatchOutcome.allCases) { outcome in
                        Label(outcome.label, systemImage: outcome.symbol).tag(outcome)
                    }
                }
            }

            if record.method != .manual {
                Section {
                    HStack {
                        TextField("Gauge reading", text: $gaugeText)
                            .keyboardType(.decimalPad)
                            .onSubmit(saveGauge)
                        Text(Units.unitLabel(metric: useMetric)).foregroundStyle(.secondary)
                        Button("Save", action: saveGauge)
                            .disabled(gaugeText.isEmpty)
                    }
                    if let error = Calibration.percentError(record) {
                        LabeledContent("App vs. gauge", value: String(format: "%+.2f%%", error))
                    }
                } header: {
                    Text("Accuracy Lab")
                } footer: {
                    Text("Enter what a gauge or caliper read for this catch. The Accuracy Lab uses these comparisons to report the app's percent error and can calibrate future scans.")
                }
            }

            Section("Where") {
                LabeledContent("Place", value: record.locationLine)
                if !record.county.isEmpty { LabeledContent("County", value: record.county) }
                if !record.waterBody.isEmpty { LabeledContent("Water", value: record.waterBody) }
                if let coordinate = record.coordinate {
                    Map(initialPosition: .region(MKCoordinateRegion(center: coordinate,
                                                                    latitudinalMeters: 3000,
                                                                    longitudinalMeters: 3000))) {
                        Marker(record.speciesName, coordinate: coordinate)
                    }
                    .frame(height: 180)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .listRowInsets(EdgeInsets(top: 8, leading: 8, bottom: 8, trailing: 8))
                }
            }

            Section("Notes") {
                TextField("Bait, tide, weather…", text: $record.notes, axis: .vertical)
                    .lineLimit(2...6)
            }

            Section {
                if record.isShared {
                    Label("Shared with the community map", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(Theme.keep)
                    Button("Remove from community", role: .destructive) { unshare() }
                        .disabled(working)
                } else if community.isConfigured {
                    Button {
                        share()
                    } label: {
                        Label("Share with the community map", systemImage: "person.3.fill")
                    }
                    .disabled(working)
                } else {
                    Text("Set up the community database in Settings to share catches.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                if let shareMessage {
                    Text(shareMessage).font(.footnote).foregroundStyle(.secondary)
                }
            } header: {
                Text("Community")
            } footer: {
                Text("Shared catches are anonymous. The location is rounded to about 1 km.")
            }

            Section {
                Button("Delete catch", role: .destructive) { confirmDelete = true }
            }
        }
        .navigationTitle(record.speciesName)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            if let gauge = record.gaugeInches {
                gaugeText = Units.number(gauge, metric: useMetric)
            }
        }
        .onDisappear {
            try? context.save()
        }
        .sheet(isPresented: $showSexGuide) {
            SexGuideView { sex in record.sex = sex }
        }
        .confirmationDialog("Delete this catch?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) { deleteRecord() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(record.isShared ? "It will also be removed from the community map." : "This can't be undone.")
        }
    }

    private func saveGauge() {
        let text = gaugeText.replacingOccurrences(of: ",", with: ".").trimmingCharacters(in: .whitespaces)
        if text.isEmpty {
            record.gaugeInches = nil
        } else if let value = Double(text), value > 0 {
            record.gaugeInches = useMetric ? Units.inches(fromCentimeters: value) : value
        }
        try? context.save()
    }

    private func share() {
        working = true
        shareMessage = "Sharing…"
        Task { @MainActor in
            do {
                record.communityDocID = try await community.share(record)
                try? context.save()
                shareMessage = "Thanks for contributing!"
            } catch {
                shareMessage = error.localizedDescription
            }
            working = false
        }
    }

    private func unshare() {
        guard let documentID = record.communityDocID else { return }
        working = true
        Task { @MainActor in
            do {
                try await community.remove(documentID: documentID)
                record.communityDocID = nil
                try? context.save()
                shareMessage = "Removed from the community map."
            } catch {
                shareMessage = error.localizedDescription
            }
            working = false
        }
    }

    private func deleteRecord() {
        if let documentID = record.communityDocID, community.isConfigured {
            let service = community
            Task { @MainActor in
                try? await service.remove(documentID: documentID)
            }
        }
        // Leave the screen first so nothing reads the deleted object while it animates away.
        let target = record
        let modelContext = context
        dismiss()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
            modelContext.delete(target)
            try? modelContext.save()
        }
    }
}
