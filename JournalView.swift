import SwiftUI
import SwiftData

/// The personal database: every catch, grouped by month, with filters and CSV export.
struct JournalView: View {
    @Environment(\.modelContext) private var context
    @Environment(CommunityService.self) private var community
    @Query(sort: \CatchRecord.date, order: .reverse) private var records: [CatchRecord]
    @AppStorage(SettingsKey.useMetric) private var useMetric = false

    @State private var speciesFilter = "all"
    @State private var verdictFilter = "all"
    @State private var searchText = ""
    @State private var shareFile: ShareFile? = nil
    @State private var exportError: String? = nil

    private var filtered: [CatchRecord] {
        records.filter { record in
            if speciesFilter != "all" && record.speciesID != speciesFilter { return false }
            if verdictFilter != "all" && record.verdictRaw != verdictFilter && record.outcomeRaw != verdictFilter { return false }
            if !searchText.isEmpty {
                let haystack = [record.speciesName, record.notes, record.placeName, record.county,
                                record.stateCode, record.waterBody].joined(separator: " ")
                if !haystack.localizedCaseInsensitiveContains(searchText) { return false }
            }
            return true
        }
    }

    private struct MonthGroup: Identifiable {
        let month: Date
        let items: [CatchRecord]
        var id: Date { month }
    }

    private var months: [MonthGroup] {
        let grouped = Dictionary(grouping: filtered) { $0.date.monthStart }
        return grouped.keys.sorted(by: >).map { MonthGroup(month: $0, items: grouped[$0] ?? []) }
    }

    private var loggedSpecies: [Species] {
        let ids = Set(records.map(\.speciesID))
        return Catalog.all.filter { ids.contains($0.id) }
    }

    var body: some View {
        NavigationStack {
            Group {
                if records.isEmpty {
                    ContentUnavailableView {
                        Label("No catches yet", systemImage: "book.closed")
                    } description: {
                        Text("Scan or type in a catch and it will be saved here with its photo, size, and place.")
                    }
                } else {
                    List {
                        Section {
                            summaryRow
                        }
                        if filtered.isEmpty {
                            Text("Nothing matches these filters.")
                                .foregroundStyle(.secondary)
                        }
                        ForEach(months) { group in
                            Section(group.month.formatted(.dateTime.month(.wide).year())) {
                                ForEach(group.items) { record in
                                    NavigationLink(value: record) {
                                        CatchRow(record: record, metric: useMetric)
                                    }
                                }
                                .onDelete { offsets in
                                    delete(offsets.map { group.items[$0] })
                                }
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .navigationTitle("Journal")
            .navigationDestination(for: CatchRecord.self) { record in
                CatchDetailView(record: record)
            }
            .searchable(text: $searchText, prompt: "Species, notes, place")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    filterMenu
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        export()
                    } label: {
                        Image(systemName: "square.and.arrow.up")
                    }
                    .disabled(records.isEmpty)
                    .accessibilityLabel("Export CSV")
                }
            }
            .sheet(item: $shareFile) { file in
                ActivityView(items: [file.url])
            }
            .alert("Export failed", isPresented: Binding(
                get: { exportError != nil },
                set: { if !$0 { exportError = nil } })) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(exportError ?? "")
            }
        }
    }

    private var summaryRow: some View {
        let kept = records.filter { $0.outcome == .kept }.count
        let released = records.filter { $0.outcome == .released }.count
        return HStack(spacing: 10) {
            StatTile(title: "Catches", value: "\(records.count)", symbol: "list.number")
            StatTile(title: "Kept", value: "\(kept)", symbol: "bag.fill", tint: Theme.keep)
            StatTile(title: "Released", value: "\(released)", symbol: "water.waves", tint: Theme.teal)
        }
        .listRowInsets(EdgeInsets())
        .listRowBackground(Color.clear)
    }

    private var filterMenu: some View {
        Menu {
            Picker("Species", selection: $speciesFilter) {
                Text("All species").tag("all")
                ForEach(loggedSpecies) { species in
                    Text(species.commonName).tag(species.id)
                }
            }
            Picker("Result", selection: $verdictFilter) {
                Text("Any result").tag("all")
                Text("Legal to keep").tag(VerdictKind.keep.rawValue)
                Text("Release").tag(VerdictKind.release.rawValue)
                Text("Borderline").tag(VerdictKind.borderline.rawValue)
                Text("Kept").tag(CatchOutcome.kept.rawValue)
                Text("Released").tag(CatchOutcome.released.rawValue)
            }
        } label: {
            Image(systemName: speciesFilter == "all" && verdictFilter == "all"
                  ? "line.3.horizontal.decrease.circle"
                  : "line.3.horizontal.decrease.circle.fill")
        }
        .accessibilityLabel("Filter")
    }

    private func delete(_ items: [CatchRecord]) {
        for record in items {
            if let documentID = record.communityDocID, community.isConfigured {
                let service = community
                Task { @MainActor in
                    try? await service.remove(documentID: documentID)
                }
            }
            context.delete(record)
        }
        try? context.save()
    }

    private func export() {
        do {
            let url = try CSVExporter.export(records)
            shareFile = ShareFile(url: url)
        } catch {
            exportError = error.localizedDescription
        }
    }
}
