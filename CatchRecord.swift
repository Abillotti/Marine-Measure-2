import Foundation
import SwiftData
import CoreLocation
import UIKit

/// One scanned or logged catch — the personal database (journal).
@Model
final class CatchRecord {
    var uuid: UUID = UUID()
    var date: Date = Date()
    var speciesID: String = "blue_crab"

    // Size
    var sizeInches: Double = 0          // final size (after calibration)
    var rawSizeInches: Double = 0       // straight from the measurement
    var uncertaintyInches: Double = 0
    var methodRaw: String = "manual"
    var calibrationFactor: Double = 1
    var gaugeInches: Double? = nil      // optional gauge/caliper reading for the Accuracy Lab
    var cameraDistanceMeters: Double? = nil

    // Attributes
    var sexRaw: String = "unknown"
    var eggColorRaw: String = "unknown"
    var shellRaw: String = "hard"

    // Rule check at the time of the catch
    var verdictRaw: String = "noRules"
    var verdictHeadline: String = ""
    var verdictDetail: String = ""
    var outcomeRaw: String = "undecided"

    // Where
    var stateCode: String = ""
    var regionID: String = ""
    var county: String = ""
    var placeName: String = ""
    var waterBody: String = ""
    var latitude: Double? = nil
    var longitude: Double? = nil

    var notes: String = ""

    // Photo + measurement markers (normalized 0...1 in the portrait photo)
    @Attribute(.externalStorage) var photoData: Data? = nil
    var thumbnailData: Data? = nil
    var markerAX: Double? = nil
    var markerAY: Double? = nil
    var markerBX: Double? = nil
    var markerBY: Double? = nil

    // Community database document id, when shared
    var communityDocID: String? = nil

    init(speciesID: String, date: Date = Date()) {
        self.uuid = UUID()
        self.speciesID = speciesID
        self.date = date
    }
}

extension CatchRecord {
    var species: Species? { Catalog.species(speciesID) }

    var speciesName: String { species?.commonName ?? speciesID }

    var method: MeasureMethod {
        get { MeasureMethod(rawValue: methodRaw) ?? .manual }
        set { methodRaw = newValue.rawValue }
    }

    var sex: CrabSex {
        get { CrabSex(rawValue: sexRaw) ?? .unknown }
        set { sexRaw = newValue.rawValue }
    }

    var eggColor: EggColor {
        get { EggColor(rawValue: eggColorRaw) ?? .unknown }
        set { eggColorRaw = newValue.rawValue }
    }

    var shell: ShellStage {
        get { ShellStage(rawValue: shellRaw) ?? .hard }
        set { shellRaw = newValue.rawValue }
    }

    var verdict: VerdictKind {
        get { VerdictKind(rawValue: verdictRaw) ?? .noRules }
        set { verdictRaw = newValue.rawValue }
    }

    var outcome: CatchOutcome {
        get { CatchOutcome(rawValue: outcomeRaw) ?? .undecided }
        set { outcomeRaw = newValue.rawValue }
    }

    var attributes: CatchAttributes {
        CatchAttributes(sex: sex, eggColor: eggColor, shell: shell)
    }

    var coordinate: CLLocationCoordinate2D? {
        guard let latitude, let longitude else { return nil }
        return CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    var isShared: Bool { communityDocID != nil }

    var markerA: CGPoint? {
        guard let x = markerAX, let y = markerAY else { return nil }
        return CGPoint(x: x, y: y)
    }

    var markerB: CGPoint? {
        guard let x = markerBX, let y = markerBY else { return nil }
        return CGPoint(x: x, y: y)
    }

    var photo: UIImage? {
        guard let photoData else { return nil }
        return UIImage(data: photoData)
    }

    var thumbnail: UIImage? {
        if let thumbnailData, let image = UIImage(data: thumbnailData) { return image }
        return nil
    }

    var locationLine: String {
        var parts: [String] = []
        if !placeName.isEmpty { parts.append(placeName) }
        if !stateCode.isEmpty { parts.append(stateCode) }
        if parts.isEmpty, !county.isEmpty { parts.append(county) }
        return parts.isEmpty ? "Unknown location" : parts.joined(separator: ", ")
    }

    /// Percent difference between the app and a gauge, when both exist.
    var gaugeErrorPercent: Double? {
        guard let gaugeInches, gaugeInches > 0 else { return nil }
        return (sizeInches - gaugeInches) / gaugeInches * 100
    }

    var isTrophy: Bool {
        guard let species else { return false }
        return sizeInches >= species.trophyInches
    }

    func setPhoto(_ image: UIImage?) {
        guard let image else {
            photoData = nil
            thumbnailData = nil
            return
        }
        photoData = image.jpeg(maxDimension: 1800, quality: 0.8)
        thumbnailData = image.jpeg(maxDimension: 240, quality: 0.7)
    }
}
