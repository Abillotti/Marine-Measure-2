import SwiftUI
import SwiftData

/// Your totals, badges, Accuracy Lab and settings.
struct ProfileView: View {
    @Query(sort: \CatchRecord.date, order: .reverse) private var records: [CatchRecord]
    @AppStorage(SettingsKey.useMetric) private var useMetric = false

    var body: some View {
        let badges = BadgeEngine.evaluate(records)
        let unlocked = badges.filter(\.isUnlocked)
        let speciesCount = Set(records.map(\.speciesID)).count
        let states = Set(records.map(\.stateCode).filter { !$0.isEmpty }).count
        let biggestCrab = records.filter { $0.speciesID == "blue_crab" }.map(\.sizeInches).max()
        let released = records.filter { $0.outcome == .released }.count

        NavigationStack {
            List {
                Section {
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                        StatTile(title: "Catches", value: "\(records.count)", symbol: "list.number")
                        StatTile(title: "Species", value: "\(speciesCount)", symbol: "fish.fill", tint: Theme.teal)
                        StatTile(title: "Released", value: "\(released)", symbol: "water.waves", tint: Theme.teal)
                        StatTile(title: "States", value: "\(states)", symbol: "map.fill", tint: Theme.info)
                        StatTile(title: "Biggest blue crab",
                                 value: biggestCrab.map { Units.format($0, metric: useMetric) } ?? "—",
                                 symbol: "trophy.fill", tint: BadgeTier.gold.color)
                        StatTile(title: "Badges", value: "\(unlocked.count)/\(badges.count)", symbol: "rosette", tint: BadgeTier.gold.color)
                    }
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                }

                Section {
                    NavigationLink {
                        BadgesView(statuses: badges)
                    } label: {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack(spacing: -8) {
                                ForEach(unlocked.suffix(6)) { status in
                                    BadgeMedal(status: status, size: 40)
                                }
                                if unlocked.isEmpty {
                                    Text("Log a catch to earn your first badge.")
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            if let next = badges.filter({ !$0.isUnlocked }).max(by: { $0.fraction < $1.fraction }) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Next: \(next.definition.title) — \(next.definition.detail)")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    ProgressView(value: next.fraction)
                                }
                            }
                        }
                        .padding(.vertical, 4)
                    }
                } header: {
                    Text("Badges")
                }

                Section("Tools") {
                    NavigationLink {
                        AccuracyLabView()
                    } label: {
                        Label("Accuracy Lab", systemImage: "testtube.2")
                    }
                    NavigationLink {
                        SettingsView()
                    } label: {
                        Label("Settings", systemImage: "gearshape.fill")
                    }
                    NavigationLink {
                        AboutView()
                    } label: {
                        Label("About MarineMeasure", systemImage: "info.circle.fill")
                    }
                }
            }
            .navigationTitle("Profile")
        }
    }
}

/// Round medal used for badges.
struct BadgeMedal: View {
    let status: BadgeStatus
    var size: CGFloat = 64

    var body: some View {
        let tier = status.definition.tier
        ZStack {
            Circle()
                .fill(status.isUnlocked
                      ? AnyShapeStyle(LinearGradient(colors: [tier.color.opacity(0.95), tier.color.opacity(0.65)],
                                                     startPoint: .topLeading, endPoint: .bottomTrailing))
                      : AnyShapeStyle(Color.gray.opacity(0.15)))
            Circle()
                .stroke(status.isUnlocked ? Color.white.opacity(0.8) : Color.gray.opacity(0.3), lineWidth: size * 0.05)
                .padding(size * 0.06)
            Image(systemName: status.definition.symbol)
                .font(.system(size: size * 0.38, weight: .bold))
                .foregroundStyle(status.isUnlocked ? Color.white : Color.gray.opacity(0.5))
        }
        .frame(width: size, height: size)
        .overlay(alignment: .bottomTrailing) {
            if !status.isUnlocked && status.fraction > 0 {
                Circle()
                    .trim(from: 0, to: status.fraction)
                    .stroke(tier.color, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .frame(width: size, height: size)
            }
        }
        .accessibilityLabel("\(status.definition.title), \(status.isUnlocked ? "unlocked" : "locked")")
    }
}

struct BadgesView: View {
    let statuses: [BadgeStatus]
    @State private var selected: BadgeStatus? = nil

    var body: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 100), spacing: 16)], spacing: 20) {
                ForEach(statuses) { status in
                    Button {
                        selected = status
                    } label: {
                        VStack(spacing: 8) {
                            BadgeMedal(status: status, size: 72)
                            Text(status.definition.title)
                                .font(.caption.weight(.semibold))
                                .multilineTextAlignment(.center)
                                .foregroundStyle(status.isUnlocked ? .primary : .secondary)
                            if !status.isUnlocked {
                                Text("\(status.progress)/\(status.definition.target)")
                                    .font(.caption2.monospacedDigit())
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding()
        }
        .background(Theme.screenBackground)
        .navigationTitle("Badges")
        .sheet(item: $selected) { status in
            VStack(spacing: 14) {
                BadgeMedal(status: status, size: 110)
                Text(status.definition.title).font(.title2.bold())
                Text(status.definition.detail).font(.body).multilineTextAlignment(.center)
                Text(status.definition.tier.label).font(.caption.weight(.semibold)).foregroundStyle(status.definition.tier.color)
                if let date = status.unlockedAt, status.isUnlocked {
                    Text("Unlocked \(date.formatted(date: .abbreviated, time: .omitted))")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else {
                    ProgressView(value: status.fraction) {
                        Text("\(status.progress) of \(status.definition.target)")
                            .font(.caption)
                    }
                    .padding(.horizontal, 40)
                }
            }
            .padding(30)
            .presentationDetents([.medium])
        }
    }
}

/// Celebration shown right after a badge is unlocked.
struct BadgeCelebrationView: View {
    let badge: BadgeDefinition
    @Environment(\.dismiss) private var dismiss
    @State private var appear = false

    var body: some View {
        VStack(spacing: 18) {
            Text("Badge unlocked!")
                .font(.headline)
                .foregroundStyle(.secondary)
            BadgeMedal(status: BadgeStatus(definition: badge, progress: badge.target, unlockedAt: Date()), size: 130)
                .scaleEffect(appear ? 1 : 0.4)
                .rotationEffect(.degrees(appear ? 0 : -25))
                .animation(.spring(response: 0.5, dampingFraction: 0.55), value: appear)
            Text(badge.title).font(.largeTitle.bold())
            Text(badge.detail)
                .font(.body)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            Button("Nice!") { dismiss() }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
        }
        .padding(30)
        .presentationDetents([.medium])
        .sensoryFeedback(.success, trigger: appear)
        .onAppear { appear = true }
    }
}
