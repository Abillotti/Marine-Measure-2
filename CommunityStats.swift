import Foundation
import CoreLocation

struct SizeBin: Identifiable {
    let id: Int
    let lower: Double
    let upper: Double
    let count: Int
}

struct AreaStat: Identifiable {
    let id: String
    let state: String
    let county: String
    let count: Int
    let average: Double
    let legalPercent: Double?
}

struct GridCell: Identifiable {
    let id: String
    let center: CLLocationCoordinate2D
    let count: Int
    let average: Double
}

struct MonthStat: Identifiable {
    let month: Date
    let count: Int
    let average: Double
    var id: Date { month }
}

/// Summary statistics for a set of community scans (one species).
struct CommunityStats {
    let count: Int
    let average: Double
    let median: Double
    let largest: Double
    let standardDeviation: Double
    let legalPercent: Double?
    let malePercent: Double?
    let femalePercent: Double?
    let spongePercent: Double?
    let bins: [SizeBin]
    let binWidth: Double
    let areas: [AreaStat]
    let cells: [GridCell]
    let months: [MonthStat]

    init(scans: [CommunityScan]) {
        let sizes = scans.map(\.sizeInches).sorted()
        count = sizes.count
        let total = sizes.reduce(0, +)
        average = sizes.isEmpty ? 0 : total / Double(sizes.count)
        median = sizes.isEmpty ? 0 : sizes[sizes.count / 2]
        largest = sizes.last ?? 0
        if sizes.count > 1 {
            let mean = average
            let variance = sizes.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / Double(sizes.count - 1)
            standardDeviation = variance.squareRoot()
        } else {
            standardDeviation = 0
        }

        let judged = scans.filter { [.keep, .release, .borderline].contains($0.verdictValue) }
        legalPercent = judged.isEmpty ? nil
            : Double(judged.filter { $0.verdictValue == .keep }.count) / Double(judged.count) * 100

        let sexed = scans.filter { $0.sexValue != .unknown }
        if sexed.isEmpty {
            malePercent = nil
            femalePercent = nil
            spongePercent = nil
        } else {
            let n = Double(sexed.count)
            malePercent = Double(sexed.filter { $0.sexValue == .male }.count) / n * 100
            femalePercent = Double(sexed.filter { $0.sexValue.isFemale }.count) / n * 100
            spongePercent = Double(sexed.filter { $0.sexValue == .eggBearing }.count) / n * 100
        }

        // Histogram
        let low = sizes.first ?? 0
        let high = sizes.last ?? 0
        let rawWidth = max((high - low) / 16, 0.25)
        let width = (rawWidth / 0.25).rounded(.up) * 0.25
        binWidth = width
        var bins: [SizeBin] = []
        if !sizes.isEmpty {
            let start = (low / width).rounded(.down) * width
            var counts: [Int: Int] = [:]
            for size in sizes {
                let index = Int(((size - start) / width).rounded(.down))
                counts[index, default: 0] += 1
            }
            let lastIndex = counts.keys.max() ?? 0
            for index in 0...lastIndex {
                let lower = start + Double(index) * width
                bins.append(SizeBin(id: index, lower: lower, upper: lower + width, count: counts[index] ?? 0))
            }
        }
        self.bins = bins

        // By area (state + county)
        var groups: [String: [CommunityScan]] = [:]
        for scan in scans {
            let key = scan.stateCode + "|" + scan.county
            groups[key, default: []].append(scan)
        }
        areas = groups.map { key, members in
            let judgedMembers = members.filter { [.keep, .release, .borderline].contains($0.verdictValue) }
            let legal: Double? = judgedMembers.isEmpty ? nil
                : Double(judgedMembers.filter { $0.verdictValue == .keep }.count) / Double(judgedMembers.count) * 100
            return AreaStat(id: key,
                            state: members.first?.stateCode ?? "",
                            county: members.first?.county ?? "",
                            count: members.count,
                            average: members.map(\.sizeInches).reduce(0, +) / Double(members.count),
                            legalPercent: legal)
        }
        .sorted { $0.count > $1.count }

        // Map grid (0.1° cells, about 11 km)
        var cellGroups: [String: (lat: Int, lon: Int, sizes: [Double])] = [:]
        for scan in scans {
            guard let latitude = scan.latitude, let longitude = scan.longitude else { continue }
            let latIndex = Int((latitude * 10).rounded(.down))
            let lonIndex = Int((longitude * 10).rounded(.down))
            let key = "\(latIndex)_\(lonIndex)"
            var entry = cellGroups[key] ?? (lat: latIndex, lon: lonIndex, sizes: [])
            entry.sizes.append(scan.sizeInches)
            cellGroups[key] = entry
        }
        cells = cellGroups.map { key, entry in
            GridCell(id: key,
                     center: CLLocationCoordinate2D(latitude: (Double(entry.lat) + 0.5) / 10,
                                                    longitude: (Double(entry.lon) + 0.5) / 10),
                     count: entry.sizes.count,
                     average: entry.sizes.reduce(0, +) / Double(entry.sizes.count))
        }

        // Monthly averages
        var monthGroups: [Date: [Double]] = [:]
        for scan in scans where scan.takenAt > Date.distantPast {
            monthGroups[scan.takenAt.monthStart, default: []].append(scan.sizeInches)
        }
        months = monthGroups.map { month, values in
            MonthStat(month: month, count: values.count, average: values.reduce(0, +) / Double(values.count))
        }
        .sorted { $0.month < $1.month }
    }
}
