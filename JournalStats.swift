import Foundation

/// Per-species totals for the species journal.
struct SpeciesLogStats {
    var count = 0
    var largest: Double = 0
    var total: Double = 0
    var first: Date?
    var last: Date?
    var kept = 0
    var released = 0
    var bestRecordID: UUID?

    var average: Double { count > 0 ? total / Double(count) : 0 }

    static func build(_ records: [CatchRecord]) -> [String: SpeciesLogStats] {
        var result: [String: SpeciesLogStats] = [:]
        for record in records {
            var stats = result[record.speciesID] ?? SpeciesLogStats()
            stats.count += 1
            stats.total += record.sizeInches
            if record.sizeInches > stats.largest {
                stats.largest = record.sizeInches
                stats.bestRecordID = record.uuid
            }
            if stats.first == nil || record.date < stats.first! { stats.first = record.date }
            if stats.last == nil || record.date > stats.last! { stats.last = record.date }
            if record.outcome == .kept { stats.kept += 1 }
            if record.outcome == .released { stats.released += 1 }
            result[record.speciesID] = stats
        }
        return result
    }
}

/// App-vs-gauge comparisons (the Accuracy Lab) and the optional calibration factor.
enum Calibration {
    struct MethodStats {
        let method: MeasureMethod
        let count: Int
        let meanAbsolutePercentError: Double
        let meanSignedPercentError: Double
        let standardDeviation: Double
        let confidence95: Double
        let suggestedFactor: Double?
    }

    static let minimumSamples = 3

    /// Records with both an AR measurement and a gauge reading.
    static func pairs(_ records: [CatchRecord], method: MeasureMethod? = nil) -> [CatchRecord] {
        records.filter { record in
            guard record.method != .manual, record.rawSizeInches > 0, let gauge = record.gaugeInches, gauge > 0 else {
                return false
            }
            if let method { return record.method == method }
            return true
        }
    }

    /// Percent error of the raw (uncalibrated) app reading vs. the gauge.
    static func percentError(_ record: CatchRecord) -> Double? {
        guard let gauge = record.gaugeInches, gauge > 0, record.rawSizeInches > 0 else { return nil }
        return (record.rawSizeInches - gauge) / gauge * 100
    }

    /// Median gauge/app ratio, clamped to ±20%. Needs at least `minimumSamples` comparisons.
    static func factor(for method: MeasureMethod, records: [CatchRecord]) -> Double? {
        let ratios = pairs(records, method: method).compactMap { record -> Double? in
            guard let gauge = record.gaugeInches else { return nil }
            return gauge / record.rawSizeInches
        }.sorted()
        guard ratios.count >= minimumSamples else { return nil }
        let median = ratios[ratios.count / 2]
        return min(1.2, max(0.8, median))
    }

    static func stats(for method: MeasureMethod, records: [CatchRecord]) -> MethodStats? {
        let errors = pairs(records, method: method).compactMap(percentError)
        guard !errors.isEmpty else { return nil }
        let n = Double(errors.count)
        let meanSigned = errors.reduce(0, +) / n
        let meanAbsolute = errors.map { Swift.abs($0) }.reduce(0, +) / n
        var deviation = 0.0
        if errors.count > 1 {
            let variance = errors.reduce(0) { $0 + ($1 - meanSigned) * ($1 - meanSigned) } / (n - 1)
            deviation = variance.squareRoot()
        }
        return MethodStats(method: method,
                           count: errors.count,
                           meanAbsolutePercentError: meanAbsolute,
                           meanSignedPercentError: meanSigned,
                           standardDeviation: deviation,
                           confidence95: errors.count > 1 ? 1.96 * deviation / n.squareRoot() : 0,
                           suggestedFactor: factor(for: method, records: records))
    }
}
