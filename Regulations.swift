import Foundation
import Observation

// MARK: - File format (Regulations.json)

struct RegulationsFile: Codable {
    let schemaVersion: Int
    let dataVersion: String
    let lastVerified: String
    let disclaimer: String
    let states: [StateInfo]
    let rules: [SpeciesRule]
}

struct StateInfo: Codable, Identifiable, Hashable {
    let code: String
    let name: String
    let agency: String
    let regulationsURL: String
    var id: String { code }
}

/// A management area inside a state (Florida's nine fishing regions, Maryland's
/// Chesapeake Bay vs. coastal bays, ...). `counties` lets the app pre-select it.
struct RegionInfo: Codable, Identifiable, Hashable {
    let id: String
    let name: String
    let detail: String?
    let counties: [String]?
}

struct SpeciesRule: Codable, Identifiable, Hashable {
    let species: String
    let state: String
    let lastVerified: String
    let sourceName: String
    let sourceURL: String
    let sizeLimits: [SizeLimit]
    let openSeasons: [DateWindow]?
    let prohibitions: [Prohibition]?
    let bagLimit: String?
    let notes: [String]?
    let regions: [RegionInfo]?
    let year: Int?

    var id: String { species + "_" + state }

    var hasRegions: Bool { !(regions ?? []).isEmpty }

    func region(_ id: String?) -> RegionInfo? {
        guard let id else { return nil }
        return regions?.first { $0.id == id }
    }
}

/// "MM-DD" to "MM-DD", inclusive. A window whose end is before its start wraps
/// over New Year (e.g. 08-06 → 03-31).
struct DateWindow: Codable, Hashable {
    let start: String
    let end: String
    let regions: [String]?
    let note: String?
}

struct SizeLimit: Codable, Hashable {
    let min: Double?
    let max: Double?
    let minInclusive: Bool?
    let maxInclusive: Bool?
    let shells: [String]?
    let sexes: [String]?
    let regions: [String]?
    let start: String?
    let end: String?
    let note: String?
    let overMaxNote: String?
}

struct Prohibition: Codable, Hashable {
    /// always | eggBearing | darkSponge | female | immatureFemale | matureFemale
    let condition: String
    let message: String
    let regions: [String]?
    let start: String?
    let end: String?
}

// MARK: - Store

/// Holds the active regulations: the bundled file, or a newer downloaded copy.
@Observable
final class RegulationStore {
    private(set) var file: RegulationsFile
    private(set) var source: String = "Bundled with the app"
    var lastUpdateMessage: String? = nil

    private var ruleIndex: [String: SpeciesRule] = [:]

    init() {
        let bundled = RegulationStore.loadBundled()
        var chosen = bundled
        var sourceText = "Bundled with the app"
        if let cached = RegulationStore.loadCached(),
           cached.schemaVersion == bundled.schemaVersion,
           cached.dataVersion > bundled.dataVersion {
            chosen = cached
            sourceText = "Downloaded update"
        }
        file = chosen
        source = sourceText
        rebuildIndex()
    }

    var states: [StateInfo] { file.states }

    func state(_ code: String?) -> StateInfo? {
        guard let code, !code.isEmpty else { return nil }
        return file.states.first { $0.code == code }
    }

    func rule(species: String, state: String?) -> SpeciesRule? {
        guard let state, !state.isEmpty else { return nil }
        return ruleIndex[species + "_" + state]
    }

    func rules(forSpecies species: String) -> [SpeciesRule] {
        file.rules.filter { $0.species == species }.sorted { $0.state < $1.state }
    }

    func rules(forState state: String) -> [SpeciesRule] {
        file.rules.filter { $0.state == state }
    }

    private func rebuildIndex() {
        var index: [String: SpeciesRule] = [:]
        for rule in file.rules { index[rule.id] = rule }
        ruleIndex = index
    }

    // MARK: Remote update

    /// Downloads a newer Regulations.json from `urlString` and keeps it if it is valid.
    @MainActor
    func update(from urlString: String) async {
        let trimmed = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed), url.scheme?.hasPrefix("http") == true else {
            lastUpdateMessage = "Enter a valid https:// link to a Regulations.json file."
            return
        }
        do {
            var request = URLRequest(url: url)
            request.cachePolicy = .reloadIgnoringLocalCacheData
            request.timeoutInterval = 20
            let (data, response) = try await URLSession.shared.data(for: request)
            if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                lastUpdateMessage = "Download failed (HTTP \(http.statusCode))."
                return
            }
            let downloaded = try JSONDecoder().decode(RegulationsFile.self, from: data)
            guard downloaded.schemaVersion == file.schemaVersion else {
                lastUpdateMessage = "That file uses a different format (schema \(downloaded.schemaVersion))."
                return
            }
            if downloaded.dataVersion < file.dataVersion {
                lastUpdateMessage = "You already have newer rules (\(file.dataVersion))."
                return
            }
            try data.write(to: RegulationStore.cacheURL, options: .atomic)
            file = downloaded
            source = "Downloaded update"
            rebuildIndex()
            lastUpdateMessage = "Updated to rules verified \(downloaded.lastVerified) (\(downloaded.rules.count) rules)."
        } catch let error as DecodingError {
            lastUpdateMessage = "That file isn't valid Regulations.json (\(error.localizedDescription))."
        } catch {
            lastUpdateMessage = "Couldn't download the update: \(error.localizedDescription)"
        }
    }

    /// Removes a downloaded update and goes back to the rules shipped with the app.
    func resetToBundled() {
        try? FileManager.default.removeItem(at: RegulationStore.cacheURL)
        file = RegulationStore.loadBundled()
        source = "Bundled with the app"
        rebuildIndex()
        lastUpdateMessage = "Using the rules bundled with the app."
    }

    // MARK: Loading

    private static var cacheURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base.appendingPathComponent("Regulations-cache.json")
    }

    private static func loadCached() -> RegulationsFile? {
        guard let data = try? Data(contentsOf: cacheURL) else { return nil }
        return try? JSONDecoder().decode(RegulationsFile.self, from: data)
    }

    private static func loadBundled() -> RegulationsFile {
        if let url = Bundle.main.url(forResource: "Regulations", withExtension: "json"),
           let data = try? Data(contentsOf: url) {
            do {
                return try JSONDecoder().decode(RegulationsFile.self, from: data)
            } catch {
                assertionFailure("Regulations.json could not be decoded: \(error)")
            }
        }
        return RegulationsFile(schemaVersion: 1, dataVersion: "0", lastVerified: "unknown",
                               disclaimer: "Regulations could not be loaded.", states: [], rules: [])
    }
}
