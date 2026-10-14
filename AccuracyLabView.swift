import SwiftUI
import SwiftData
import Charts

/// App vs. gauge comparisons — the percent-error analysis from the research
/// project, built into the app — plus optional calibration.
struct AccuracyLabView: View {
    @Query(sort: \CatchRecord.date, order: .reverse) private var records: [CatchRecord]
    @AppStorage(SettingsKey.applyCalibration) private var applyCalibration = false
    @AppStorage(SettingsKey.useMetric) private var useMetric = false

    var body: some View {
        let pairs = Calibration.pairs(records)
        let methodStats = [MeasureMethod.lidar, .surface].compactMap { Calibration.stats(for: $0, records: records) }

        List {
            Section {
                Text("Scan a catch, then measure it with a gauge or caliper and type the reading on the result screen (or in the journal). MarineMeasure tracks the percent error for each measuring method, just like the caliper comparison in the original research.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            if pairs.isEmpty {
                Section {
                    ContentUnavailableView {
                        Label("No comparisons yet", systemImage: "testtube.2")
                    } description: {
                        Text("Add a gauge reading to a scanned catch to start.")
                    }
                }
            } else {
                ForEach(methodStats, id: \.method) { stats in
                    Section(stats.method.label) {
                        LabeledContent("Comparisons", value: "\(stats.count)")
                        LabeledContent("Mean absolute error", value: String(format: "%.2f%%", stats.meanAbsolutePercentError))
                        LabeledContent("Bias (app − gauge)", value: String(format: "%+.2f%%", stats.meanSignedPercentError))
                        if stats.count > 1 {
                            LabeledContent("Std. deviation", value: String(format: "%.2f%%", stats.standardDeviation))
                            LabeledContent("95% CI of bias", value: String(format: "±%.2f%%", stats.confidence95))
                        }
                        if let factor = stats.suggestedFactor {
                            LabeledContent("Calibration factor", value: String(format: "×%.3f", factor))
                        } else {
                            Text("\(Calibration.minimumSamples) or more comparisons unlock a calibration factor.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Section {
                    Toggle("Apply calibration to new scans", isOn: $applyCalibration)
                } footer: {
                    Text("When on, new AR measurements are multiplied by the median gauge/app ratio for their method (limited to ±20%). Your saved catches keep both the raw and calibrated sizes.")
                }

                Section("App vs. gauge") {
                    let factor = useMetric ? Units.centimetersPerInch : 1
                    let values = pairs.compactMap { record -> (gauge: Double, app: Double)? in
                        guard let gauge = record.gaugeInches else { return nil }
                        return (gauge * factor, record.rawSizeInches * factor)
                    }
                    let low = (values.map { min($0.gauge, $0.app) }.min() ?? 0) * 0.95
                    let high = (values.map { max($0.gauge, $0.app) }.max() ?? 1) * 1.05
                    Chart {
                        ForEach(Array(values.enumerated()), id: \.offset) { item in
                            PointMark(x: .value("Gauge", item.element.gauge), y: .value("App", item.element.app))
                                .foregroundStyle(Theme.accent)
                        }
                        LineMark(x: .value("Gauge", low), y: .value("App", low), series: .value("Line", "Perfect"))
                            .foregroundStyle(.gray)
                        LineMark(x: .value("Gauge", high), y: .value("App", high), series: .value("Line", "Perfect"))
                            .foregroundStyle(.gray)
                    }
                    .chartXScale(domain: low...high)
                    .chartYScale(domain: low...high)
                    .chartXAxisLabel("Gauge (\(Units.unitLabel(metric: useMetric)))")
                    .chartYAxisLabel("App (\(Units.unitLabel(metric: useMetric)))")
                    .frame(height: 260)
                    Text("Points on the gray line are perfect matches. Points above it mean the app read long.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("Comparisons") {
                    ForEach(pairs) { record in
                        HStack {
                            VStack(alignment: .leading) {
                                Text(record.speciesName).font(.subheadline.weight(.semibold))
                                Text(record.date.formatted(date: .abbreviated, time: .shortened))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            VStack(alignment: .trailing) {
                                Text("App \(Units.format(record.rawSizeInches, metric: useMetric)) · Gauge \(Units.format(record.gaugeInches ?? 0, metric: useMetric))")
                                    .font(.caption.monospacedDigit())
                                if let error = Calibration.percentError(record) {
                                    Text(String(format: "%+.2f%%", error))
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(abs(error) <= 3 ? Theme.keep : Theme.caution)
                                }
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Accuracy Lab")
    }
}
