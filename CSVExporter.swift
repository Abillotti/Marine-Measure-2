import Foundation

/// Exports the journal to a CSV file (opens in Excel, Numbers, Google Sheets, R, Python...).
enum CSVExporter {
    static func export(_ records: [CatchRecord]) throws -> URL {
        var lines: [String] = [[
            "date", "species", "scientific_name", "size_in", "size_cm", "uncertainty_in", "method",
            "raw_size_in", "calibration_factor", "gauge_in", "gauge_error_percent", "sex", "egg_color",
            "shell", "verdict", "outcome", "state", "region", "county", "place", "water_body",
            "latitude", "longitude", "camera_distance_m", "shared", "notes",
        ].joined(separator: ",")]

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]

        for record in records.sorted(by: { $0.date < $1.date }) {
            let fields: [String] = [
                formatter.string(from: record.date),
                record.speciesName,
                record.species?.scientificName ?? "",
                String(format: "%.3f", record.sizeInches),
                String(format: "%.2f", Units.centimeters(record.sizeInches)),
                String(format: "%.3f", record.uncertaintyInches),
                record.methodRaw,
                String(format: "%.3f", record.rawSizeInches),
                String(format: "%.4f", record.calibrationFactor),
                record.gaugeInches.map { String(format: "%.3f", $0) } ?? "",
                record.gaugeErrorPercent.map { String(format: "%.2f", $0) } ?? "",
                record.sexRaw,
                record.eggColorRaw,
                record.shellRaw,
                record.verdictRaw,
                record.outcomeRaw,
                record.stateCode,
                record.regionID,
                record.county,
                record.placeName,
                record.waterBody,
                record.latitude.map { String(format: "%.5f", $0) } ?? "",
                record.longitude.map { String(format: "%.5f", $0) } ?? "",
                record.cameraDistanceMeters.map { String(format: "%.3f", $0) } ?? "",
                record.isShared ? "yes" : "no",
                record.notes,
            ]
            lines.append(fields.map(escape).joined(separator: ","))
        }

        let stamp = Date().dayKey
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("MarineMeasure-journal-\(stamp).csv")
        try lines.joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    static func escape(_ field: String) -> String {
        if field.contains(",") || field.contains("\"") || field.contains("\n") || field.contains("\r") {
            return "\"" + field.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        }
        return field
    }
}
