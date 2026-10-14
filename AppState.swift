import SwiftUI
import Observation

/// Small piece of shared UI state: the selected tab and any badges waiting to be celebrated.
@Observable
final class AppState {
    enum Tab: Hashable {
        case scan, journal, species, community, profile
    }

    var selectedTab: Tab = .scan
    /// Badges unlocked by the most recent save, shown one after another.
    var pendingBadges: [BadgeDefinition] = []

    /// Species chosen on the Scan tab (shared so the species guide can start a scan).
    var scanSpeciesID: String = UserDefaults.standard.string(forKey: SettingsKey.favoriteSpecies) ?? "blue_crab"

    func celebrate(_ badges: [BadgeDefinition]) {
        guard !badges.isEmpty else { return }
        pendingBadges.append(contentsOf: badges)
    }
}
