import Foundation

/// Deterministic random numbers so sample data looks the same on every launch.
struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) { state = seed }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    static func seed(from text: String) -> UInt64 {
        var hash: UInt64 = 1_469_598_103_934_665_603
        for scalar in text.unicodeScalars {
            hash = (hash ^ UInt64(scalar.value)) &* 1_099_511_628_211
        }
        return hash
    }
}

/// Clearly-labeled fake community scans for testing the Community tab before
/// Firebase is set up (Settings › Developer). Never uploaded anywhere.
enum SampleCommunityData {
    private struct Hub {
        let state: String
        let county: String
        let water: String
        let latitude: Double
        let longitude: Double
        let sizeFactor: Double
    }

    private static let hubs: [Hub] = [
        Hub(state: "NJ", county: "Ocean County", water: "Barnegat Bay", latitude: 39.80, longitude: -74.15, sizeFactor: 0.97),
        Hub(state: "NJ", county: "Cape May County", water: "Delaware Bay", latitude: 39.00, longitude: -74.86, sizeFactor: 1.00),
        Hub(state: "NY", county: "Suffolk County", water: "Great South Bay", latitude: 40.70, longitude: -73.10, sizeFactor: 0.95),
        Hub(state: "DE", county: "Sussex County", water: "Indian River Bay", latitude: 38.60, longitude: -75.12, sizeFactor: 0.99),
        Hub(state: "MD", county: "Anne Arundel County", water: "Chesapeake Bay", latitude: 38.98, longitude: -76.48, sizeFactor: 1.04),
        Hub(state: "MD", county: "Dorchester County", water: "Choptank River", latitude: 38.45, longitude: -76.20, sizeFactor: 1.06),
        Hub(state: "VA", county: "Mathews County", water: "Mobjack Bay", latitude: 37.42, longitude: -76.33, sizeFactor: 1.05),
        Hub(state: "NC", county: "Dare County", water: "Pamlico Sound", latitude: 35.85, longitude: -75.67, sizeFactor: 1.03),
        Hub(state: "SC", county: "Charleston County", water: "Charleston Harbor", latitude: 32.76, longitude: -79.92, sizeFactor: 1.00),
        Hub(state: "GA", county: "Glynn County", water: "St. Simons Sound", latitude: 31.15, longitude: -81.43, sizeFactor: 0.98),
        Hub(state: "FL", county: "Duval County", water: "St. Johns River", latitude: 30.33, longitude: -81.50, sizeFactor: 1.02),
        Hub(state: "FL", county: "Broward County", water: "Intracoastal Waterway", latitude: 26.10, longitude: -80.12, sizeFactor: 0.96),
        Hub(state: "FL", county: "Pinellas County", water: "Tampa Bay", latitude: 27.80, longitude: -82.70, sizeFactor: 0.99),
        Hub(state: "LA", county: "Plaquemines Parish", water: "Barataria Bay", latitude: 29.45, longitude: -89.80, sizeFactor: 1.04),
        Hub(state: "TX", county: "Galveston County", water: "Galveston Bay", latitude: 29.35, longitude: -94.85, sizeFactor: 1.01),
    ]

    static func scans(speciesID: String, count: Int = 420) -> [CommunityScan] {
        var rng = SeededGenerator(seed: SeededGenerator.seed(from: speciesID))
        let species = Catalog.species(speciesID)
        let low = species?.typicalMinInches ?? 3
        let high = species?.typicalMaxInches ?? 9
        let mean = low + (high - low) * 0.42
        let spread = (high - low) * 0.12
        let legalCut = low + (high - low) * 0.33
        let isCrab = species?.group == .crab
        let now = Date()

        var result: [CommunityScan] = []
        for index in 0..<count {
            let hub = hubs[Int.random(in: 0..<hubs.count, using: &rng)]
            // Box-Muller normal sample
            let u1 = max(Double.random(in: 0..<1, using: &rng), 1e-9)
            let u2 = Double.random(in: 0..<1, using: &rng)
            let normal = sqrt(-2 * log(u1)) * cos(2 * Double.pi * u2)
            let raw: Double = (mean + normal * spread) * hub.sizeFactor
            let size = min(high, max(low, raw))
            let rounded = (size * 100).rounded() / 100

            var sex = CrabSex.unknown
            if isCrab {
                let roll = Double.random(in: 0..<1, using: &rng)
                if roll < 0.55 { sex = .male } else if roll < 0.80 { sex = .matureFemale } else if roll < 0.95 { sex = .immatureFemale } else { sex = .eggBearing }
            }
            let methodRoll = Double.random(in: 0..<1, using: &rng)
            let method: MeasureMethod = methodRoll < 0.3 ? .lidar : (methodRoll < 0.8 ? .surface : .manual)
            let verdict: VerdictKind = sex == .eggBearing ? .release : (rounded >= legalCut ? .keep : .release)
            let daysAgo = Double.random(in: 0..<365, using: &rng)
            let jitterLatitude = Double.random(in: -0.18...0.18, using: &rng)
            let jitterLongitude = Double.random(in: -0.18...0.18, using: &rng)
            let latitude: Double = ((hub.latitude + jitterLatitude) * 100).rounded() / 100
            let longitude: Double = ((hub.longitude + jitterLongitude) * 100).rounded() / 100
            let takenAt = now.addingTimeInterval(-daysAgo * 86_400)

            result.append(CommunityScan(
                id: "sample-\(index)",
                speciesID: speciesID,
                sizeInches: rounded,
                method: method.rawValue,
                sex: sex.rawValue,
                shell: ShellStage.hard.rawValue,
                verdict: verdict.rawValue,
                stateCode: hub.state,
                county: hub.county,
                waterBody: hub.water,
                latitude: latitude,
                longitude: longitude,
                takenAt: takenAt,
                uid: "sample"))
        }
        return result.sorted { $0.takenAt > $1.takenAt }
    }
}
