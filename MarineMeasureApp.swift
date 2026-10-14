import SwiftUI
import SwiftData

/// MarineMeasure — measure a catch with the iPhone camera, check it against the
/// rules where you are standing, and keep a journal of everything you scan.
///
/// Originally a MATES research project (Junior Research Project, NJ Southern
/// Research Project and Senior Capstone) by Anthony Billotti.
@main
struct MarineMeasureApp: App {
    @State private var location = LocationService()
    @State private var regulations = RegulationStore()
    @State private var community = CommunityService()
    @State private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(location)
                .environment(regulations)
                .environment(community)
                .environment(appState)
                .tint(Theme.accent)
        }
        .modelContainer(for: CatchRecord.self)
    }
}
