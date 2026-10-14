import Foundation

/// Everything the rule engine needs to judge one catch.
struct RuleInput {
    var species: Species
    var stateCode: String?
    var regionID: String?
    var county: String?
    var date: Date
    var sizeInches: Double?
    var uncertaintyInches: Double
    var attributes: CatchAttributes
    var metric: Bool = false
}

/// The answer shown to the user: keep, release, borderline, check something, or no rules.
struct Verdict: Equatable {
    var kind: VerdictKind
    var headline: String
    var detail: String
    var reasons: [String] = []
    var confirmations: [String] = []
    var hints: [String] = []
    var notes: [String] = []
    var limitText: String?
    var bagLimit: String?
    var rule: SpeciesRule?
    var stateName: String?
    var region: RegionInfo?
    var needsRegion: Bool = false
    var seasonOpen: Bool?
}

/// "MM-DD" helpers.
enum MonthDay {
    static func value(_ text: String?) -> Int? {
        guard let text else { return nil }
        let parts = text.split(separator: "-")
        guard parts.count == 2, let month = Int(parts[0]), let day = Int(parts[1]) else { return nil }
        return month * 100 + day
    }

    static func value(of date: Date) -> Int {
        let comps = Calendar.current.dateComponents([.month, .day], from: date)
        return (comps.month ?? 1) * 100 + (comps.day ?? 1)
    }

    /// True when `date` falls in the inclusive window. No window means "always".
    static func contains(start: String?, end: String?, date: Date) -> Bool {
        guard let startValue = value(start), let endValue = value(end) else { return true }
        let today = value(of: date)
        if startValue <= endValue {
            return today >= startValue && today <= endValue
        }
        return today >= startValue || today <= endValue
    }

    static func label(_ text: String) -> String {
        guard let combined = value(text) else { return text }
        let months = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
        let month = combined / 100
        let day = combined % 100
        guard month >= 1, month <= 12 else { return text }
        if month == 2 && day == 29 { return "end of Feb" }
        return "\(months[month - 1]) \(day)"
    }

    static func range(_ start: String, _ end: String) -> String {
        "\(label(start)) – \(label(end))"
    }
}

/// Plain-language summary of a rule, used by the species guide and the Scan tab.
struct RuleSummary {
    var sizes: [String] = []
    var seasons: [String] = []
    var restrictions: [String] = []
    var bag: String?
    var notes: [String] = []
}

enum RuleEngine {

    // MARK: Evaluate a catch

    static func evaluate(_ input: RuleInput, store: RegulationStore) -> Verdict {
        guard let code = input.stateCode, !code.isEmpty else {
            return Verdict(kind: .noRules,
                           headline: "Where are you?",
                           detail: "Turn on location or choose a state so MarineMeasure can check the rules.")
        }
        let stateName = store.state(code)?.name ?? code
        guard let rule = store.rule(species: input.species.id, state: code) else {
            return Verdict(kind: .noRules,
                           headline: "No rules on file",
                           detail: "MarineMeasure doesn't have \(input.species.commonName) rules for \(stateName) yet. Check the official regulations before you keep it.",
                           stateName: stateName)
        }
        return evaluate(input, rule: rule, stateName: stateName)
    }

    static func evaluate(_ input: RuleInput, rule: SpeciesRule, stateName: String) -> Verdict {
        let species = input.species
        let date = input.date
        let metric = input.metric
        let region = resolveRegion(rule: rule, preferred: input.regionID, county: input.county)

        var violations: [String] = []
        var confirmations: [String] = []
        var hints: [String] = []
        var notes: [String] = []
        var needsRegion = false
        var borderline: String?
        var seasonOpen: Bool?

        // Season ------------------------------------------------------------
        if let windows = rule.openSeasons, !windows.isEmpty {
            var unknownRegion = false
            var open = false
            var relevant: [DateWindow] = []
            for window in windows {
                switch applies(regions: window.regions, region: region) {
                case .some(true):
                    relevant.append(window)
                    if MonthDay.contains(start: window.start, end: window.end, date: date) { open = true }
                case .some(false):
                    break
                case .none:
                    unknownRegion = true
                }
            }
            if unknownRegion && !open {
                needsRegion = true
                hints.append("The season depends on the area — choose your region.")
            } else {
                seasonOpen = open
                if open {
                    var text = "Season is open"
                    if let current = relevant.first(where: { MonthDay.contains(start: $0.start, end: $0.end, date: date) }) {
                        text += " (\(MonthDay.range(current.start, current.end)))"
                        if let note = current.note { text += " · \(note)" }
                    }
                    confirmations.append(text + ".")
                } else {
                    let list = relevant.map { MonthDay.range($0.start, $0.end) }.joined(separator: ", ")
                    violations.append(list.isEmpty ? "The season is closed." : "The season is closed. Open: \(list).")
                }
            }
        }

        if let year = rule.year {
            let currentYear = Calendar.current.component(.year, from: date)
            if currentYear != year {
                notes.append("Season dates on file were set for \(year). Check for \(currentYear) changes.")
            }
        }

        // Size --------------------------------------------------------------
        var minLimit: Double?
        var maxLimit: Double?
        var minInclusive = true
        var maxInclusive = true
        var overMaxNote: String?
        var sizeRegionUnknown = false
        var sexDependent = false

        for limit in rule.sizeLimits {
            guard shellMatches(limit, attributes: input.attributes, species: species) else { continue }
            guard MonthDay.contains(start: limit.start, end: limit.end, date: date) else { continue }
            guard sexMatches(limit, attributes: input.attributes) else { continue }
            switch applies(regions: limit.regions, region: region) {
            case .some(true):
                break
            case .some(false):
                continue
            case .none:
                sizeRegionUnknown = true
                continue
            }
            if limit.sexes != nil && input.attributes.sex == .unknown { sexDependent = true }
            if let low = limit.min, low > (minLimit ?? -Double.infinity) {
                minLimit = low
                minInclusive = limit.minInclusive ?? true
            }
            if let high = limit.max, high < (maxLimit ?? Double.infinity) {
                maxLimit = high
                maxInclusive = limit.maxInclusive ?? true
                overMaxNote = limit.overMaxNote
            }
        }

        let hasSizeRule = minLimit != nil || maxLimit != nil
        let limitText: String? = hasSizeRule
            ? describe(min: minLimit, max: maxLimit, minInclusive: minInclusive, maxInclusive: maxInclusive, metric: metric)
            : nil
        var failedMinimum = false

        if let size = input.sizeInches {
            let error = max(0, input.uncertaintyInches)
            if let low = minLimit {
                let lowText = Units.ruleValue(low, metric: metric)
                func meetsMinimum(_ value: Double) -> Bool { minInclusive ? value >= low : value > low }
                if !meetsMinimum(size) {
                    if meetsMinimum(size + error) {
                        borderline = "It's within measurement error of the \(lowText) minimum."
                    } else {
                        failedMinimum = true
                        violations.append("Undersized: \(Units.format(size, metric: metric)) is below the \(lowText) minimum.")
                    }
                } else if !meetsMinimum(size - error) {
                    borderline = "It's only \(Units.format(max(0, size - low), metric: metric)) over the \(lowText) minimum, inside the measurement error."
                } else {
                    confirmations.append("Meets the \(lowText) minimum.")
                }
            }
            if let high = maxLimit {
                let highText = Units.ruleValue(high, metric: metric)
                func meetsMaximum(_ value: Double) -> Bool { maxInclusive ? value <= high : value < high }
                if !meetsMaximum(size) {
                    if meetsMaximum(size - error) {
                        borderline = "It's within measurement error of the \(highText) maximum."
                    } else {
                        violations.append("Over the slot: \(Units.format(size, metric: metric)) is above the \(highText) maximum.")
                        if let note = overMaxNote { hints.append(note) }
                    }
                } else if !meetsMaximum(size + error) {
                    borderline = "It's right at the \(highText) maximum, inside the measurement error."
                } else {
                    confirmations.append("Under the \(highText) maximum.")
                }
            }
            if !hasSizeRule && !sizeRegionUnknown {
                confirmations.append(rule.sizeLimits.isEmpty
                                     ? "\(stateName) has no minimum size for \(species.commonName.lowercased())."
                                     : "No size limit applies to this catch.")
            }
        }

        if sizeRegionUnknown && !hasSizeRule {
            needsRegion = true
            hints.append("The size limit depends on the area — choose your region.")
        }
        if sexDependent && failedMinimum {
            hints.append("Size limits here depend on sex. If this is a mature female, it may be exempt — set the sex for an exact answer.")
        }

        // Prohibitions ---------------------------------------------------------
        for prohibition in rule.prohibitions ?? [] {
            guard MonthDay.contains(start: prohibition.start, end: prohibition.end, date: date) else { continue }
            switch applies(regions: prohibition.regions, region: region) {
            case .some(true):
                break
            case .some(false):
                continue
            case .none:
                needsRegion = true
                hints.append("Some areas have extra restrictions — choose your region.")
                continue
            }
            switch check(condition: prohibition.condition, attributes: input.attributes) {
            case .violated:
                violations.append(prohibition.message)
            case .question(let question):
                hints.append("\(question) \(prohibition.message)")
            case .reminder:
                notes.append("If it's carrying eggs: \(prohibition.message)")
            case .clear:
                break
            }
        }

        notes.append(contentsOf: rule.notes ?? [])

        // Combine --------------------------------------------------------------
        var verdict: Verdict
        if !violations.isEmpty {
            verdict = Verdict(kind: .release, headline: "Release it", detail: violations[0])
        } else if let borderline {
            verdict = Verdict(kind: .borderline, headline: "Too close to call",
                              detail: borderline + " Check it with a gauge before you keep it.")
        } else if needsRegion || !hints.isEmpty {
            verdict = Verdict(kind: .needsInfo, headline: "One more check",
                              detail: hints.first ?? "Choose your region to finish the check.")
        } else {
            verdict = Verdict(kind: .keep, headline: "Legal to keep",
                              detail: "Meets \(stateName) rules for \(species.commonName).")
        }
        verdict.reasons = violations
        verdict.confirmations = confirmations
        verdict.hints = uniqued(hints)
        verdict.notes = uniqued(notes)
        verdict.limitText = limitText
        verdict.bagLimit = rule.bagLimit
        verdict.rule = rule
        verdict.stateName = stateName
        verdict.region = region
        verdict.needsRegion = needsRegion
        verdict.seasonOpen = seasonOpen
        return verdict
    }

    // MARK: Regions

    static func resolveRegion(rule: SpeciesRule, preferred: String?, county: String?) -> RegionInfo? {
        guard let regions = rule.regions, !regions.isEmpty else { return nil }
        if let preferred, let match = regions.first(where: { $0.id == preferred }) {
            return match
        }
        return suggestedRegion(rule: rule, county: county)
    }

    static func suggestedRegion(rule: SpeciesRule, county: String?) -> RegionInfo? {
        guard let target = normalizeCounty(county), let regions = rule.regions else { return nil }
        return regions.first { region in
            (region.counties ?? []).contains { normalizeCounty($0) == target }
        }
    }

    static func normalizeCounty(_ text: String?) -> String? {
        guard var value = text?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(), !value.isEmpty else {
            return nil
        }
        for suffix in [" county", " parish", " borough"] where value.hasSuffix(suffix) {
            value = String(value.dropLast(suffix.count))
        }
        value = value.replacingOccurrences(of: ".", with: "")
        value = value.replacingOccurrences(of: "saint ", with: "st ")
        return value
    }

    /// true / false, or nil when the item is limited to regions but no region is known yet.
    private static func applies(regions: [String]?, region: RegionInfo?) -> Bool? {
        guard let regions, !regions.isEmpty else { return true }
        guard let region else { return nil }
        return regions.contains(region.id)
    }

    // MARK: Matching

    private static func shellMatches(_ limit: SizeLimit, attributes: CatchAttributes, species: Species) -> Bool {
        guard let shells = limit.shells, !shells.isEmpty else { return true }
        let shell = species.askShell ? attributes.shell : .hard
        return shells.contains(shell.rawValue)
    }

    private static func sexMatches(_ limit: SizeLimit, attributes: CatchAttributes) -> Bool {
        guard let sexes = limit.sexes, !sexes.isEmpty else { return true }
        return sexes.contains(attributes.sex.rawValue)
    }

    private enum ConditionResult {
        case violated
        case clear
        case question(String)
        case reminder
    }

    private static func check(condition: String, attributes: CatchAttributes) -> ConditionResult {
        let sex = attributes.sex
        switch condition {
        case "always":
            return .violated
        case "eggBearing":
            if sex == .eggBearing { return .violated }
            return sex == .unknown ? .reminder : .clear
        case "darkSponge":
            guard sex == .eggBearing else { return sex == .unknown ? .reminder : .clear }
            switch attributes.eggColor {
            case .dark: return .violated
            case .orange: return .clear
            case .unknown: return .question("What color is the egg mass?")
            }
        case "female":
            if sex == .unknown { return .question("Is it a male or a female?") }
            return sex.isFemale ? .violated : .clear
        case "immatureFemale":
            if sex == .unknown { return .question("Check the apron — is it an immature female?") }
            return sex == .immatureFemale ? .violated : .clear
        case "matureFemale":
            if sex == .unknown { return .question("Check the apron — is it a mature female?") }
            return sex.isMatureFemale ? .violated : .clear
        default:
            return .clear
        }
    }

    // MARK: Describing rules

    static func describe(min low: Double?, max high: Double?, minInclusive: Bool, maxInclusive: Bool, metric: Bool) -> String {
        switch (low, high) {
        case let (lowValue?, highValue?):
            let upper = maxInclusive
                ? Units.ruleValue(highValue, metric: metric)
                : "under " + Units.ruleValue(highValue, metric: metric)
            return "Slot: \(Units.ruleValue(lowValue, metric: metric)) to \(upper)"
        case let (lowValue?, nil):
            return (minInclusive ? "Minimum " : "Larger than ") + Units.ruleValue(lowValue, metric: metric)
        case let (nil, highValue?):
            return "Maximum " + Units.ruleValue(highValue, metric: metric)
        default:
            return "No size limit"
        }
    }

    static func describe(limit: SizeLimit, metric: Bool) -> String {
        describe(min: limit.min, max: limit.max,
                 minInclusive: limit.minInclusive ?? true, maxInclusive: limit.maxInclusive ?? true, metric: metric)
    }

    /// A readable breakdown of a rule. If `region` is given, items for other regions are hidden.
    static func summary(rule: SpeciesRule, species: Species, region: RegionInfo?, metric: Bool) -> RuleSummary {
        var summary = RuleSummary()

        if rule.sizeLimits.isEmpty {
            summary.sizes.append("No minimum size")
        }
        for limit in rule.sizeLimits {
            if let region, let regions = limit.regions, !regions.contains(region.id) { continue }
            var text = describe(limit: limit, metric: metric)
            var qualifiers: [String] = []
            if let note = limit.note { qualifiers.append(note) }
            if let start = limit.start, let end = limit.end { qualifiers.append(MonthDay.range(start, end)) }
            if region == nil, let regions = limit.regions { qualifiers.append(regionNames(regions, rule: rule)) }
            if let sexes = limit.sexes, !sexes.contains(CrabSex.matureFemale.rawValue) {
                if limit.note == nil || !(limit.note ?? "").contains("female") {
                    qualifiers.append("mature females exempt")
                }
            }
            if !qualifiers.isEmpty { text += " (" + qualifiers.joined(separator: " · ") + ")" }
            if let overMax = limit.overMaxNote { text += ". " + overMax }
            summary.sizes.append(text)
        }

        if let windows = rule.openSeasons, !windows.isEmpty {
            for window in windows {
                if let region, let regions = window.regions, !regions.contains(region.id) { continue }
                var text = "Open " + MonthDay.range(window.start, window.end)
                if let note = window.note { text += " · \(note)" }
                if region == nil, let regions = window.regions { text += " (\(regionNames(regions, rule: rule)))" }
                summary.seasons.append(text)
            }
        } else {
            summary.seasons.append("Open year-round")
        }

        for prohibition in rule.prohibitions ?? [] {
            if let region, let regions = prohibition.regions, !regions.contains(region.id) { continue }
            var text = prohibition.message
            if let start = prohibition.start, let end = prohibition.end,
               !prohibition.message.contains(MonthDay.label(start)) {
                text += " (\(MonthDay.range(start, end)))"
            }
            summary.restrictions.append(text)
        }

        summary.bag = rule.bagLimit
        summary.notes = rule.notes ?? []
        return summary
    }

    /// Short one-line version for the Scan tab, e.g. "Minimum 4.5 in (hard shell) · Minimum 3 in (peeler/shedder)".
    static func shortSummary(rule: SpeciesRule, species: Species, region: RegionInfo?, metric: Bool) -> String {
        let parts = RuleEngine.summary(rule: rule, species: species, region: region, metric: metric)
        return parts.sizes.prefix(3).joined(separator: "\n")
    }

    private static func regionNames(_ ids: [String], rule: SpeciesRule) -> String {
        let names = ids.compactMap { id in rule.regions?.first(where: { $0.id == id })?.name }
        if names.count > 3 { return "\(names.count) regions" }
        return names.joined(separator: ", ")
    }

    private static func uniqued(_ items: [String]) -> [String] {
        var seen = Set<String>()
        return items.filter { seen.insert($0).inserted }
    }
}
