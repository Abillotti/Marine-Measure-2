import SwiftUI

/// Freeze-frame measuring: the captured photo with two draggable markers and a
/// magnifier, recomputing the real-world length live as the markers move.
struct MeasureEditorView: View {
    let snapshot: CaptureSnapshot
    let species: Species
    var calibrationFactor: Double = 1
    var onRetake: () -> Void
    var onConfirm: (MeasurementResult, CGPoint, CGPoint) -> Void

    @AppStorage(SettingsKey.useMetric) private var useMetric = false
    @AppStorage(SettingsKey.flatTestMode) private var flatTestMode = false
    @State private var markerA = CGPoint(x: 0.28, y: 0.5)
    @State private var markerB = CGPoint(x: 0.72, y: 0.5)
    @State private var dragging: Int? = nil
    @State private var dragStart: CGPoint = .zero
    @State private var result: Result<MeasurementResult, MeasurementError>? = nil
    @State private var autoPlaced = false
    @State private var showHelp = false

    private let loupeSize: CGFloat = 124
    private let loupeZoom: CGFloat = 3

    var body: some View {
        VStack(spacing: 0) {
            GeometryReader { geo in
                let fit = aspectFitRect(imageSize: snapshot.image.size, in: geo.size)
                ZStack(alignment: .topLeading) {
                    Color.black
                    Image(uiImage: snapshot.image)
                        .resizable()
                        .frame(width: fit.width, height: fit.height)
                        .position(x: fit.midX, y: fit.midY)

                    Path { path in
                        path.move(to: viewPoint(markerA, fit))
                        path.addLine(to: viewPoint(markerB, fit))
                    }
                    .stroke(Theme.measure, style: StrokeStyle(lineWidth: 3, lineCap: .round, dash: [8, 5]))
                    .shadow(color: .black.opacity(0.6), radius: 2)
                    .allowsHitTesting(false)

                    marker(index: 0, fit: fit)
                    marker(index: 1, fit: fit)

                    if let dragging {
                        loupe(center: dragging == 0 ? markerA : markerB, fit: fit)
                    }
                }
                .contentShape(Rectangle())
                .gesture(dragGesture(fit: fit))
            }

            bottomPanel
        }
        .background(Color.black)
        .navigationTitle("Place the markers")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Retake", action: onRetake)
            }
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showHelp = true
                } label: {
                    Image(systemName: "questionmark.circle")
                }
            }
        }
        .sheet(isPresented: $showHelp) {
            MeasureHelpSheet(species: species)
                .presentationDetents([.medium, .large])
        }
        .task {
            recompute()
            await autoPlaceIfPossible()
        }
    }

    // MARK: Markers

    private func viewPoint(_ normalized: CGPoint, _ fit: CGRect) -> CGPoint {
        CGPoint(x: fit.minX + normalized.x * fit.width, y: fit.minY + normalized.y * fit.height)
    }

    private func marker(index: Int, fit: CGRect) -> some View {
        let point = index == 0 ? markerA : markerB
        return ZStack {
            Circle()
                .fill(Theme.measure.opacity(dragging == index ? 0.05 : 0.22))
                .frame(width: 38, height: 38)
            Circle()
                .stroke(Theme.measure, lineWidth: 2.5)
                .frame(width: 38, height: 38)
            Image(systemName: "plus")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(Theme.measure)
            Text(index == 0 ? "A" : "B")
                .font(.caption2.bold())
                .foregroundStyle(.black)
                .padding(3)
                .background(Theme.measure, in: Circle())
                .offset(x: 18, y: -18)
        }
        .frame(width: 64, height: 64)
        .position(viewPoint(point, fit))
        .allowsHitTesting(false)
        .accessibilityLabel(index == 0 ? "Marker A" : "Marker B")
    }

    /// One drag gesture for the whole photo: it grabs the nearest marker. Touching
    /// far from both markers moves the nearest one to the finger first (tap to place).
    private func dragGesture(fit: CGRect) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                if dragging == nil {
                    let a = viewPoint(markerA, fit)
                    let b = viewPoint(markerB, fit)
                    let start = value.startLocation
                    let distanceA = hypot(start.x - a.x, start.y - a.y)
                    let distanceB = hypot(start.x - b.x, start.y - b.y)
                    let index = distanceA <= distanceB ? 0 : 1
                    dragging = index
                    if min(distanceA, distanceB) > 56 {
                        let placed = normalized(start, fit)
                        if index == 0 { markerA = placed } else { markerB = placed }
                        dragStart = placed
                    } else {
                        dragStart = index == 0 ? markerA : markerB
                    }
                }
                guard let index = dragging else { return }
                let dx = value.translation.width / max(fit.width, 1)
                let dy = value.translation.height / max(fit.height, 1)
                let moved = CGPoint(x: min(1, max(0, dragStart.x + dx)),
                                    y: min(1, max(0, dragStart.y + dy)))
                if index == 0 { markerA = moved } else { markerB = moved }
                recompute()
            }
            .onEnded { _ in
                dragging = nil
                recompute()
            }
    }

    private func normalized(_ point: CGPoint, _ fit: CGRect) -> CGPoint {
        CGPoint(x: min(1, max(0, (point.x - fit.minX) / max(fit.width, 1))),
                y: min(1, max(0, (point.y - fit.minY) / max(fit.height, 1))))
    }

    /// Magnified view of the photo around the marker, shown above the finger.
    private func loupe(center: CGPoint, fit: CGRect) -> some View {
        let imageWidth = fit.width * loupeZoom
        let imageHeight = fit.height * loupeZoom
        let offsetX = loupeSize / 2 - center.x * imageWidth
        let offsetY = loupeSize / 2 - center.y * imageHeight
        let anchor = viewPoint(center, fit)
        let half: CGFloat = loupeSize / 2
        let above: CGFloat = anchor.y - half - 56
        let below: CGFloat = anchor.y + half + 56
        let y: CGFloat = above > half + 8 ? above : below
        let lowestX: CGFloat = half + 8
        let highestX: CGFloat = max(lowestX, fit.maxX - half - 8)
        let x: CGFloat = min(max(anchor.x, lowestX), highestX)
        return ZStack(alignment: .topLeading) {
            Color.black
            Image(uiImage: snapshot.image)
                .resizable()
                .frame(width: imageWidth, height: imageHeight)
                .offset(x: offsetX, y: offsetY)
        }
        .frame(width: loupeSize, height: loupeSize, alignment: .topLeading)
        .clipShape(Circle())
        .overlay(Circle().stroke(.white, lineWidth: 3))
        .overlay {
            ZStack {
                Rectangle().fill(Theme.measure).frame(width: 1.5, height: 26)
                Rectangle().fill(Theme.measure).frame(width: 26, height: 1.5)
            }
        }
        .shadow(radius: 6)
        .position(x: x, y: y)
        .allowsHitTesting(false)
    }

    // MARK: Measurement

    private func recompute() {
        result = MeasurementEngine.measure(snapshot: snapshot, a: markerA, b: markerB,
                                          heightRatio: flatTestMode ? 0 : species.heightRatio)
    }

    private func autoPlaceIfPossible() async {
        guard !autoPlaced, species.group == .fish, let cgImage = snapshot.image.cgImage else { return }
        autoPlaced = true
        let found = await Task.detached(priority: .userInitiated) {
            SubjectEndpointFinder.endpoints(in: cgImage)
        }.value
        guard let found else { return }
        withAnimation(.easeInOut(duration: 0.35)) {
            markerA = found.0
            markerB = found.1
        }
        recompute()
    }

    // MARK: Bottom panel

    private var bottomPanel: some View {
        VStack(spacing: 12) {
            switch result {
            case .success(let measurement):
                let size = measurement.inches * calibrationFactor
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(Units.number(size, metric: useMetric))
                        .font(.system(size: 44, weight: .bold, design: .rounded).monospacedDigit())
                    Text(Units.unitLabel(metric: useMetric))
                        .font(.title3.weight(.semibold))
                    Text(Units.uncertainty(measurement.uncertaintyInches * calibrationFactor, metric: useMetric))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                HStack(spacing: 8) {
                    Label(measurement.method.label, systemImage: measurement.method.symbol)
                    if flatTestMode {
                        Label("Flat test mode", systemImage: "testtube.2")
                    }
                    if calibrationFactor != 1 {
                        Label("Calibrated ×\(String(format: "%.3f", calibrationFactor))", systemImage: "slider.horizontal.3")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                ForEach(measurement.warnings, id: \.self) { warning in
                    Label(warning, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(Theme.caution)
                }
            case .failure(let error):
                Label(error.message, systemImage: "exclamationmark.triangle.fill")
                    .font(.subheadline)
                    .foregroundStyle(Theme.caution)
                    .multilineTextAlignment(.center)
            case .none:
                ProgressView()
            }

            Text(species.measurement.markerHint)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            HStack(spacing: 12) {
                Button(action: onRetake) {
                    Label("Retake", systemImage: "camera.rotate")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)

                Button {
                    if case .success(let measurement) = result {
                        onConfirm(measurement, markerA, markerB)
                    }
                } label: {
                    Label("Check rules", systemImage: "checkmark.seal")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(!isSuccess)
            }
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(.regularMaterial)
    }

    private var isSuccess: Bool {
        if case .success = result { return true }
        return false
    }
}

/// Measuring tips for one species.
struct MeasureHelpSheet: View {
    let species: Species
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    MeasureDiagram(species: species, height: 170)
                        .card()
                    Text(species.measurementLabel).font(.headline)
                    Text(species.howToMeasure)
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Lay the catch flat on a surface with some texture (a cooler lid or dock board works well).", systemImage: "square.3.layers.3d")
                        Label("Hold the phone 25–60 cm (10–24 in) above it, pointing straight down.", systemImage: "iphone.gen3")
                        Label("Good light helps. At night, turn on the flashlight in the scanner.", systemImage: "flashlight.on.fill")
                        Label("Drag a marker and use the magnifier to put the crosshair exactly on the tip.", systemImage: "plus.magnifyingglass")
                        Label("Near the legal limit? Double-check with a gauge — the app shows its error margin.", systemImage: "ruler")
                    }
                    .font(.subheadline)
                }
                .padding()
            }
            .navigationTitle("How to measure")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
