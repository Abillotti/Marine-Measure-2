import Foundation

/// Project-wide configuration. Fill in the Firebase values once so every copy of
/// the app you install shares the same community database (see README).
enum AppConfig {
    /// Firebase project ID, e.g. "marinemeasure-1234". Leave empty to keep the
    /// community map off (it can also be set in Settings › Community database).
    static let firebaseProjectID = ""

    /// Firebase *Web API key* (Project settings › General). It identifies the
    /// project; your Firestore security rules are what protect the data.
    static let firebaseWebAPIKey = ""

    /// Optional: a URL to a newer copy of Regulations.json (for example the raw
    /// GitHub URL of the file in your repo). The app checks it from Settings so
    /// you can fix a rule without rebuilding the app.
    static let regulationsUpdateURL = ""

    /// Firestore collection that stores shared scans.
    static let communityCollection = "scans"

    static var appVersion: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "2.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(version) (\(build))"
    }
}

/// UserDefaults keys used with @AppStorage throughout the app.
enum SettingsKey {
    static let hasOnboarded = "mm.hasOnboarded"
    static let useMetric = "mm.useMetric"
    static let manualState = "mm.manualState"            // "" = use GPS
    static let shareCommunity = "mm.shareCommunity"
    static let applyCalibration = "mm.applyCalibration"
    static let favoriteSpecies = "mm.favoriteSpecies"
    static let firebaseProjectID = "mm.firebaseProjectID"
    static let firebaseAPIKey = "mm.firebaseAPIKey"
    static let sampleCommunity = "mm.sampleCommunity"
    static let seenBadges = "mm.seenBadges"
    static let regulationsURL = "mm.regulationsURL"
    static let flatTestMode = "mm.flatTestMode"
}

/// Remembers which management region the user picked for a state + species
/// (for example "Southeast" for Florida snook) so they only choose it once.
enum RegionMemory {
    private static let key = "mm.regionSelections"

    private static func load() -> [String: String] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let dict = try? JSONDecoder().decode([String: String].self, from: data) else { return [:] }
        return dict
    }

    static func region(state: String, species: String) -> String? {
        load()["\(state)|\(species)"]
    }

    static func set(_ region: String?, state: String, species: String) {
        var dict = load()
        dict["\(state)|\(species)"] = region
        if let data = try? JSONEncoder().encode(dict) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }
}
