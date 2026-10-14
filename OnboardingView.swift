import SwiftUI

/// Short animated splash (a nod to the original 3-second loading screen).
struct SplashView: View {
    @State private var appear = false

    var body: some View {
        ZStack {
            Theme.oceanGradient.ignoresSafeArea()
            VStack(spacing: 18) {
                Canvas { context, size in
                    let rect = CGRect(origin: .zero, size: size)
                    GlyphDrawing.draw(.crab, in: rect, context: &context, color: .white, detail: Theme.ocean)
                    var line = Path()
                    line.move(to: GlyphDrawing.point(rect, 0.06, 0.50))
                    line.addLine(to: GlyphDrawing.point(rect, 0.94, 0.50))
                    context.stroke(line, with: .color(Theme.measure), style: StrokeStyle(lineWidth: 4, lineCap: .round, dash: [8, 6]))
                }
                .frame(width: 190, height: 150)
                .scaleEffect(appear ? 1 : 0.7)
                .opacity(appear ? 1 : 0)

                Text("MarineMeasure")
                    .font(.system(size: 40, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)
                Text("Measure it. Check it. Release it right.")
                    .font(.headline)
                    .foregroundStyle(.white.opacity(0.85))
            }
            VStack {
                Spacer()
                Text("A MATES research project by Anthony Billotti")
                    .font(.footnote)
                    .foregroundStyle(.white.opacity(0.7))
                    .padding(.bottom, 24)
            }
        }
        .onAppear {
            withAnimation(.spring(response: 0.6, dampingFraction: 0.7)) { appear = true }
        }
    }
}

/// First-run walkthrough with permissions and the community opt-in.
struct OnboardingView: View {
    @Environment(LocationService.self) private var location
    @AppStorage(SettingsKey.hasOnboarded) private var hasOnboarded = false
    @AppStorage(SettingsKey.shareCommunity) private var shareCommunity = false
    @State private var page = 0

    private struct Page: Identifiable {
        let id: Int
        let symbol: String
        let title: String
        let text: String
    }

    private let pages: [Page] = [
        Page(id: 0, symbol: "camera.viewfinder", title: "Measure in seconds",
             text: "Lay your catch flat, aim, and capture. Drag two markers to the tips and MarineMeasure works out the real size with AR — LiDAR iPhones even measure depth directly."),
        Page(id: 1, symbol: "checkmark.seal.fill", title: "Know before you keep",
             text: "It checks the size, season, sex and egg-bearing rules for the state you're standing in, and tells you when a catch is too close to call."),
        Page(id: 2, symbol: "book.closed.fill", title: "Your catch journal",
             text: "Every catch is saved with its photo, size and place. Fill in the species journal, compare against a gauge in the Accuracy Lab, and earn badges."),
    ]

    var body: some View {
        VStack(spacing: 0) {
            TabView(selection: $page) {
                ForEach(pages) { item in
                    pageView(item).tag(item.id)
                }
                finalPage.tag(pages.count)
            }
            .tabViewStyle(.page(indexDisplayMode: .always))
            .indexViewStyle(.page(backgroundDisplayMode: .always))

            Button {
                if page < pages.count {
                    withAnimation { page += 1 }
                } else {
                    hasOnboarded = true
                }
            } label: {
                Text(page < pages.count ? "Next" : "Get started")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .padding()
        }
        .background(Theme.screenBackground)
    }

    private func pageView(_ item: Page) -> some View {
        VStack(spacing: 22) {
            Spacer()
            Image(systemName: item.symbol)
                .font(.system(size: 76, weight: .semibold))
                .foregroundStyle(Theme.oceanGradient)
            Text(item.title)
                .font(.largeTitle.bold())
                .multilineTextAlignment(.center)
            Text(item.text)
                .font(.title3)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 28)
            Spacer()
            Spacer()
        }
    }

    private var finalPage: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: "person.3.fill")
                .font(.system(size: 64, weight: .semibold))
                .foregroundStyle(Theme.oceanGradient)
            Text("Community science")
                .font(.largeTitle.bold())
            Text("Share scans anonymously to build a map of blue crab sizes across bays, counties and states. Locations are rounded to about 1 km.")
                .font(.body)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 28)

            Toggle("Share my scans", isOn: $shareCommunity)
                .padding()
                .background(Theme.cardBackground, in: RoundedRectangle(cornerRadius: 14))
                .padding(.horizontal, 28)

            Button {
                location.requestPermission()
            } label: {
                Label(location.isAuthorized ? "Location is on" : "Allow location for local rules",
                      systemImage: location.isAuthorized ? "checkmark.circle.fill" : "location.fill")
            }
            .buttonStyle(.bordered)
            .disabled(location.isAuthorized)

            Spacer()
            Spacer()
        }
    }
}
