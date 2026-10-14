import Foundation
import SwiftUI

enum SpeciesGroup: String, Codable, CaseIterable, Identifiable {
    case crab, lobster, fish
    var id: String { rawValue }
    var label: String {
        switch self {
        case .crab: return "Crabs"
        case .lobster: return "Lobsters"
        case .fish: return "Fish"
        }
    }
}

enum MeasurementKind: String, Codable {
    case carapaceWidth, carapaceLength, clawLength, totalLength, forkLength

    var markerHint: String {
        switch self {
        case .carapaceWidth: return "Drag the markers to the tips of the two long side spines."
        case .carapaceLength: return "Drag one marker between the eye horns and the other to the back edge of the body shell."
        case .clawLength: return "Drag the markers to the tip of the lower (fixed) finger and to the claw's first joint."
        case .totalLength: return "Drag the markers to the tip of the snout and the tip of the tail."
        case .forkLength: return "Drag the markers to the tip of the snout and the fork of the tail."
        }
    }
}

/// How the app asks about sex for a species.
enum SexMode: String, Codable {
    case apron   // full blue-crab style picker (male / immature / mature / sponge)
    case eggs    // only "is it carrying eggs?"
    case none
}

struct Species: Codable, Identifiable, Hashable {
    let id: String
    let commonName: String
    let scientificName: String
    let group: SpeciesGroup
    let waterType: String
    let measurement: MeasurementKind
    let measurementLabel: String
    let howToMeasure: String
    /// Height of the measured points above the surface, as a fraction of the
    /// measured length. Used to correct the AR-surface method (no LiDAR).
    let heightRatio: Double
    let trophyInches: Double
    let typicalMinInches: Double
    let typicalMaxInches: Double
    let askShell: Bool
    let sexMode: SexMode
    let nicknames: [String]
    let identification: [String]
    let habitat: String
    let funFact: String
    let colorHex: String

    var color: Color { Color(hex: colorHex) }
    var isFreshwater: Bool { waterType == "freshwater" }
}

private struct SpeciesFile: Codable {
    let species: [Species]
}

/// The bundled species list (Species.json).
enum Catalog {
    static let all: [Species] = {
        guard let url = Bundle.main.url(forResource: "Species", withExtension: "json"),
              let data = try? Data(contentsOf: url) else {
            assertionFailure("Species.json is missing from the app bundle")
            return []
        }
        do {
            return try JSONDecoder().decode(SpeciesFile.self, from: data).species
        } catch {
            assertionFailure("Species.json could not be decoded: \(error)")
            return []
        }
    }()

    private static let byID: [String: Species] = {
        var dict: [String: Species] = [:]
        for item in all { dict[item.id] = item }
        return dict
    }()

    static func species(_ id: String) -> Species? { byID[id] }

    static var blueCrab: Species? { byID["blue_crab"] }

    /// Species list with a guaranteed fallback so pickers never break.
    static func speciesOrFirst(_ id: String) -> Species? {
        byID[id] ?? all.first
    }
}
