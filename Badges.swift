import Foundation
import SwiftUI

enum BadgeTier: Int {
    case bronze, silver, gold, special

    var color: Color {
        switch self {
        case .bronze: return Color(red: 0.80, green: 0.50, blue: 0.25)
        case .silver: return Color(red: 0.55, green: 0.60, blue: 0.66)
        case .gold: return Color(red: 0.93, green: 0.70, blue: 0.10)
        case .special: return Theme.teal
        }
    }

    var label: String {
        switch self {
        case .bronze: return "Bronze"
        case .silver: return "Silver"
        case .gold: return "Gold"
        case .special: return "Special"
        }
    }
}

/// How progress toward a badge is counted.
enum BadgeRule {
    /// Number of catches that pass the test.
    case count((CatchRecord) -> Bool)
    /// Number of different values (species, states, days...).
    case distinct((CatchRecord) -> String?)
}

struct BadgeDefinition: Identifiable, Equatable {
    let id: String
    let title: String
    let detail: String
    let symbol: String
    let tier: BadgeTier
    let target: Int
    let rule: BadgeRule

    static func == (lhs: BadgeDefinition, rhs: BadgeDefinition) -> Bool { lhs.id == rhs.id }
}

struct BadgeStatus: Identifiable {
    let definition: BadgeDefinition
    let progress: Int
    let unlockedAt: Date?

    var id: String { definition.id }
    var isUnlocked: Bool { progress >= definition.target }
    var fraction: Double {
        guard definition.target > 0 else { return 1 }
        return min(1, Double(progress) / Double(definition.target))
    }
}

enum BadgeEngine {
    static let all: [BadgeDefinition] = [
        BadgeDefinition(id: "first_catch", title: "First Catch", detail: "Log your first catch.",
                        symbol: "star.fill", tier: .bronze, target: 1, rule: .count { _ in true }),
        BadgeDefinition(id: "getting_hooked", title: "Getting Hooked", detail: "Log 10 catches.",
                        symbol: "flame.fill", tier: .bronze, target: 10, rule: .count { _ in true }),
        BadgeDefinition(id: "dock_regular", title: "Dock Regular", detail: "Log 50 catches.",
                        symbol: "figure.fishing", tier: .silver, target: 50, rule: .count { _ in true }),
        BadgeDefinition(id: "century_club", title: "Century Club", detail: "Log 100 catches.",
                        symbol: "rosette", tier: .gold, target: 100, rule: .count { _ in true }),
        BadgeDefinition(id: "crab_cadet", title: "Crab Cadet", detail: "Scan 25 blue crabs.",
                        symbol: "shield.fill", tier: .bronze, target: 25, rule: .count { $0.speciesID == "blue_crab" }),
        BadgeDefinition(id: "crab_captain", title: "Crab Captain", detail: "Scan 100 blue crabs.",
                        symbol: "shield.lefthalf.filled", tier: .silver, target: 100, rule: .count { $0.speciesID == "blue_crab" }),
        BadgeDefinition(id: "crab_legend", title: "Crab Legend", detail: "Scan 500 blue crabs.",
                        symbol: "crown.fill", tier: .gold, target: 500, rule: .count { $0.speciesID == "blue_crab" }),
        BadgeDefinition(id: "jumbo", title: "Jumbo", detail: "Measure a blue crab 6 inches or bigger.",
                        symbol: "arrow.up.left.and.arrow.down.right", tier: .silver, target: 1,
                        rule: .count { $0.speciesID == "blue_crab" && $0.sizeInches >= 6.0 }),
        BadgeDefinition(id: "colossal", title: "Colossal", detail: "Measure a blue crab 7 inches or bigger.",
                        symbol: "sparkles", tier: .gold, target: 1,
                        rule: .count { $0.speciesID == "blue_crab" && $0.sizeInches >= 7.0 }),
        BadgeDefinition(id: "trophy_hunter", title: "Trophy Hunter", detail: "Catch any species at its trophy size.",
                        symbol: "trophy.fill", tier: .gold, target: 1, rule: .count { $0.isTrophy }),
        BadgeDefinition(id: "species_explorer", title: "Species Explorer", detail: "Log 3 different species.",
                        symbol: "binoculars.fill", tier: .bronze, target: 3, rule: .distinct { $0.speciesID }),
        BadgeDefinition(id: "naturalist", title: "Naturalist", detail: "Log 8 different species.",
                        symbol: "leaf.fill", tier: .gold, target: 8, rule: .distinct { $0.speciesID }),
        BadgeDefinition(id: "state_hopper", title: "State Hopper", detail: "Log catches in 2 states.",
                        symbol: "map.fill", tier: .silver, target: 2,
                        rule: .distinct { $0.stateCode.isEmpty ? nil : $0.stateCode }),
        BadgeDefinition(id: "coastal_traveler", title: "Coastal Traveler", detail: "Log catches in 4 states.",
                        symbol: "globe.americas.fill", tier: .gold, target: 4,
                        rule: .distinct { $0.stateCode.isEmpty ? nil : $0.stateCode }),
        BadgeDefinition(id: "conservationist", title: "Conservationist",
                        detail: "Release 10 catches that MarineMeasure said to release.",
                        symbol: "hand.raised.fill", tier: .silver, target: 10,
                        rule: .count { $0.verdict == .release && $0.outcome == .released }),
        BadgeDefinition(id: "sponge_saver", title: "Sponge Saver", detail: "Release an egg-bearing female.",
                        symbol: "heart.fill", tier: .special, target: 1,
                        rule: .count { $0.sex == .eggBearing && $0.outcome == .released }),
        BadgeDefinition(id: "apron_expert", title: "Apron Expert", detail: "Record the sex of 25 crabs.",
                        symbol: "eye.fill", tier: .silver, target: 25,
                        rule: .count { $0.species?.group == .crab && $0.sex != .unknown }),
        BadgeDefinition(id: "lab_scientist", title: "Lab Scientist", detail: "Compare 10 scans with a gauge reading.",
                        symbol: "testtube.2", tier: .silver, target: 10,
                        rule: .count { $0.gaugeInches != nil && $0.method != .manual }),
        BadgeDefinition(id: "citizen_scientist", title: "Citizen Scientist", detail: "Share 10 catches with the community map.",
                        symbol: "person.3.fill", tier: .silver, target: 10, rule: .count { $0.isShared }),
        BadgeDefinition(id: "tide_regular", title: "Tide Regular", detail: "Log catches on 10 different days.",
                        symbol: "calendar", tier: .silver, target: 10, rule: .distinct { $0.date.dayKey }),
        BadgeDefinition(id: "early_bird", title: "Early Bird", detail: "Log a catch before 6 AM.",
                        symbol: "sunrise.fill", tier: .special, target: 1,
                        rule: .count { Calendar.current.component(.hour, from: $0.date) < 6 }),
        BadgeDefinition(id: "night_crabber", title: "Night Crabber", detail: "Log a catch after 9 PM.",
                        symbol: "moon.stars.fill", tier: .special, target: 1,
                        rule: .count { Calendar.current.component(.hour, from: $0.date) >= 21 }),
    ]

    static func evaluate(_ records: [CatchRecord]) -> [BadgeStatus] {
        let sorted = records.sorted { $0.date < $1.date }
        return all.map { definition in
            var progress = 0
            var unlockedAt: Date?
            switch definition.rule {
            case .count(let qualifies):
                for record in sorted where qualifies(record) {
                    progress += 1
                    if progress == definition.target { unlockedAt = record.date }
                }
            case .distinct(let key):
                var seen = Set<String>()
                for record in sorted {
                    guard let value = key(record), seen.insert(value).inserted else { continue }
                    if seen.count == definition.target { unlockedAt = record.date }
                }
                progress = seen.count
            }
            return BadgeStatus(definition: definition, progress: min(progress, definition.target), unlockedAt: unlockedAt)
        }
    }

    static func unlockedIDs(_ records: [CatchRecord]) -> Set<String> {
        Set(evaluate(records).filter(\.isUnlocked).map(\.id))
    }

    static func definition(_ id: String) -> BadgeDefinition? {
        all.first { $0.id == id }
    }
}
