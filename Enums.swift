import Foundation

/// How a size was obtained.
enum MeasureMethod: String, Codable, CaseIterable, Identifiable {
    case lidar      // AR + LiDAR depth (Pro iPhones)
    case surface    // AR + detected surface plane
    case manual     // typed in from a gauge, caliper or ruler

    var id: String { rawValue }

    var label: String {
        switch self {
        case .lidar: return "LiDAR depth"
        case .surface: return "AR surface"
        case .manual: return "Manual / gauge"
        }
    }

    var symbol: String {
        switch self {
        case .lidar: return "dot.radiowaves.left.and.right"
        case .surface: return "square.3.layers.3d.down.right"
        case .manual: return "ruler"
        }
    }
}

/// Sex / reproductive stage. Crab names in parentheses.
enum CrabSex: String, Codable, CaseIterable, Identifiable {
    case unknown
    case male               // jimmy
    case immatureFemale     // sally / she-crab, triangle apron
    case matureFemale       // sook, rounded apron
    case eggBearing         // sponge crab / berried female

    var id: String { rawValue }

    var isFemale: Bool {
        self == .immatureFemale || self == .matureFemale || self == .eggBearing
    }

    var isMatureFemale: Bool {
        self == .matureFemale || self == .eggBearing
    }

    var label: String {
        switch self {
        case .unknown: return "Not sure"
        case .male: return "Male"
        case .immatureFemale: return "Immature female"
        case .matureFemale: return "Mature female"
        case .eggBearing: return "Egg-bearing female"
        }
    }

    /// Blue-crab slang shown next to the label.
    var crabNickname: String? {
        switch self {
        case .unknown: return nil
        case .male: return "Jimmy"
        case .immatureFemale: return "Sally"
        case .matureFemale: return "Sook"
        case .eggBearing: return "Sponge"
        }
    }
}

/// Egg mass color matters in some states (dark sponges hatch soon).
enum EggColor: String, Codable, CaseIterable, Identifiable {
    case unknown, orange, dark
    var id: String { rawValue }
    var label: String {
        switch self {
        case .unknown: return "Not sure"
        case .orange: return "Bright orange"
        case .dark: return "Brown / black"
        }
    }
}

enum ShellStage: String, Codable, CaseIterable, Identifiable {
    case hard, peeler, soft
    var id: String { rawValue }
    var label: String {
        switch self {
        case .hard: return "Hard"
        case .peeler: return "Peeler"
        case .soft: return "Soft"
        }
    }
    var detail: String {
        switch self {
        case .hard: return "Firm shell"
        case .peeler: return "About to molt (red or pink line on the paddle fin)"
        case .soft: return "Just molted, shell is soft"
        }
    }
}

enum VerdictKind: String, Codable, CaseIterable {
    case keep, release, borderline, needsInfo, noRules
}

/// What the angler actually did.
enum CatchOutcome: String, Codable, CaseIterable, Identifiable {
    case undecided, kept, released
    var id: String { rawValue }
    var label: String {
        switch self {
        case .undecided: return "Not recorded"
        case .kept: return "Kept"
        case .released: return "Released"
        }
    }
    var symbol: String {
        switch self {
        case .undecided: return "circle.dashed"
        case .kept: return "bag.fill"
        case .released: return "water.waves"
        }
    }
}

/// Everything about the catch (besides size) that a rule can depend on.
struct CatchAttributes: Equatable {
    var sex: CrabSex = .unknown
    var eggColor: EggColor = .unknown
    var shell: ShellStage = .hard
}
