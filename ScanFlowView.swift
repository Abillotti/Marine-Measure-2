import SwiftUI
import SwiftData
import UIKit

/// A catch on its way to being saved.
struct ScanDraft {
    var speciesID: String
    var rawInches: Double
    var uncertaintyInches: Double
    var method: MeasureMethod
    var calibrationFactor: Double = 1
    var date = Date()
    var cameraDistanceMeters: Double? = nil
    var photo: UIImage? = nil
    var markerA: CGPoint? = nil
    var markerB: CGPoint? = nil
    var warnings: [String] = []
    var attributes = CatchAttributes()
    var stateCode: String? = nil
    var regionID: String? = nil
    var county: String? = nil
    var placeName: String? = nil
    var waterBody: String? = nil
    var latitude: Double? = nil
    var longitude: Double? = nil
    var notes = ""

    /// Final size after the optional calibration factor.
    var sizeInches: Double { rawInches * calibrationFactor }
}

/// Camera → markers → rules → save, presented full screen from the Scan tab.
struct ScanFlowView: View {
    enum Mode {
        case camera, manual
    }

    private enum Step {
        case camera
        case measure(CaptureSnapshot)
        case manual
        case result(ScanDraft)
    }

    let species: Species
    let mode: Mode

    @Environment(\.dismiss) private var dismiss
    @AppStorage(SettingsKey.applyCalibration) private var applyCalibration = false
    @Query private var records: [CatchRecord]
    /// Created once when the flow appears (not in the property initializer, which
    /// SwiftUI may run many times) because it owns the AR camera view.
    @State private var controller: ARScanController? = nil
    @State private var step: Step

    init(species: Species, mode: Mode) {
        self.species = species
        self.mode = mode
        _step = State(initialValue: mode == .camera ? Step.camera : Step.manual)
    }

    var body: some View {
        NavigationStack {
            Group {
                switch step {
                case .camera:
                    if let controller {
                        ScannerScreen(controller: controller,
                                      species: species,
                                      onCapture: { snapshot in
                                          controller.pause()
                                          step = .measure(snapshot)
                                      },
                                      onManual: {
                                          controller.pause()
                                          step = .manual
                                      },
                                      onClose: {
                                          controller.pause()
                                          dismiss()
                                      })
                        .toolbar(.hidden, for: .navigationBar)
                    } else {
                        Color.black.ignoresSafeArea()
                            .toolbar(.hidden, for: .navigationBar)
                    }

                case .measure(let snapshot):
                    MeasureEditorView(snapshot: snapshot,
                                      species: species,
                                      calibrationFactor: calibrationFactor(for: snapshot),
                                      onRetake: { step = .camera },
                                      onConfirm: { measurement, a, b in
                                          step = .result(makeDraft(measurement, snapshot: snapshot, a: a, b: b))
                                      })

                case .manual:
                    ManualEntryView(species: species,
                                    onCancel: { dismiss() },
                                    onContinue: { draft in step = .result(draft) })

                case .result(let draft):
                    ScanResultView(species: species,
                                   draft: draft,
                                   canRetake: mode == .camera,
                                   onRetake: { step = .camera },
                                   onFinished: { dismiss() })
                }
            }
        }
        .onAppear {
            if controller == nil && mode == .camera {
                controller = ARScanController()
            }
        }
    }

    /// The method isn't known until markers are placed, so use LiDAR's factor when
    /// depth exists and the surface factor otherwise.
    private func calibrationFactor(for snapshot: CaptureSnapshot) -> Double {
        guard applyCalibration else { return 1 }
        let method: MeasureMethod = snapshot.depth != nil ? .lidar : .surface
        return Calibration.factor(for: method, records: records) ?? 1
    }

    private func makeDraft(_ measurement: MeasurementResult, snapshot: CaptureSnapshot, a: CGPoint, b: CGPoint) -> ScanDraft {
        let factor = applyCalibration ? (Calibration.factor(for: measurement.method, records: records) ?? 1) : 1
        var draft = ScanDraft(speciesID: species.id,
                              rawInches: measurement.inches,
                              uncertaintyInches: measurement.uncertaintyInches * factor,
                              method: measurement.method)
        draft.calibrationFactor = factor
        draft.date = snapshot.capturedAt
        draft.cameraDistanceMeters = measurement.cameraDistanceMeters
        draft.photo = snapshot.image
        draft.markerA = a
        draft.markerB = b
        draft.warnings = measurement.warnings
        return draft
    }
}

/// Live AR camera with status, level hint and shutter.
struct ScannerScreen: View {
    let controller: ARScanController
    let species: Species
    var onCapture: (CaptureSnapshot) -> Void
    var onManual: () -> Void
    var onClose: () -> Void

    @State private var shutterCount = 0
    @State private var captureError: String? = nil
    @State private var showHelp = false

    var body: some View {
        ZStack {
            if ARScanController.isSupported {
                ARCameraView(controller: controller)
                    .ignoresSafeArea()
                ReticleView(ready: controller.canCapture)
            } else {
                Theme.oceanGradient.ignoresSafeArea()
                unsupportedMessage
            }

            VStack(spacing: 12) {
                topBar
                Spacer()
                if ARScanController.isSupported {
                    statusPill
                    if let tilt = controller.tiltDegrees, tilt > 28, controller.canCapture {
                        Label("Hold the phone flat, right above the catch", systemImage: "iphone.gen3.radiowaves.left.and.right")
                            .font(.footnote.weight(.semibold))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(.ultraThinMaterial, in: Capsule())
                    }
                }
                bottomBar
            }
            .padding()
        }
        .onAppear {
            if ARScanController.isSupported { controller.start() }
        }
        .onDisappear {
            controller.pause()
        }
        .sensoryFeedback(.impact, trigger: shutterCount)
        .alert("Couldn't capture", isPresented: Binding(
            get: { captureError != nil },
            set: { if !$0 { captureError = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(captureError ?? "")
        }
        .sheet(isPresented: $showHelp) {
            MeasureHelpSheet(species: species)
                .presentationDetents([.medium, .large])
        }
    }

    private var topBar: some View {
        HStack {
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.headline)
                    .frame(width: 40, height: 40)
                    .background(.ultraThinMaterial, in: Circle())
            }
            .accessibilityLabel("Close")

            Spacer()

            HStack(spacing: 8) {
                SpeciesGlyph(species: species, size: 26)
                Text(species.commonName).font(.subheadline.weight(.semibold))
                if controller.supportsLiDAR {
                    Text("LiDAR")
                        .font(.caption2.bold())
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Theme.teal, in: Capsule())
                        .foregroundStyle(.white)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(.ultraThinMaterial, in: Capsule())

            Spacer()

            Button {
                controller.setTorch(!controller.torchOn)
            } label: {
                Image(systemName: controller.torchOn ? "flashlight.on.fill" : "flashlight.off.fill")
                    .font(.headline)
                    .frame(width: 40, height: 40)
                    .background(.ultraThinMaterial, in: Circle())
            }
            .accessibilityLabel(controller.torchOn ? "Turn off flashlight" : "Turn on flashlight")
            .disabled(!ARScanController.isSupported)
        }
        .foregroundStyle(.primary)
    }

    private var statusColor: Color {
        switch controller.readiness {
        case .ready: return Theme.keep
        case .tooClose, .tooFar, .limited: return Theme.caution
        case .failed: return Theme.release
        case .starting, .searching: return controller.supportsLiDAR ? Theme.teal : .white
        }
    }

    private var statusPill: some View {
        HStack(spacing: 8) {
            Circle().fill(statusColor).frame(width: 10, height: 10)
            Text(controller.statusText)
                .font(.subheadline.weight(.semibold))
                .multilineTextAlignment(.leading)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial, in: Capsule())
        .animation(.easeInOut(duration: 0.2), value: controller.statusText)
    }

    private var bottomBar: some View {
        VStack(spacing: 10) {
            Text("Lay the \(species.commonName.lowercased()) flat, center it, then tap the shutter.")
                .font(.footnote)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))

            HStack {
                Button(action: onManual) {
                    VStack(spacing: 4) {
                        Image(systemName: "keyboard").font(.title3)
                        Text("Type size").font(.caption2)
                    }
                    .frame(width: 72, height: 60)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
                }

                Spacer()

                Button(action: capture) {
                    ZStack {
                        Circle().stroke(.white, lineWidth: 4).frame(width: 78, height: 78)
                        Circle().fill(controller.canCapture ? Color.white : Color.white.opacity(0.35)).frame(width: 64, height: 64)
                        Image(systemName: "ruler")
                            .font(.title2)
                            .foregroundStyle(controller.canCapture ? Theme.ocean : .gray)
                    }
                }
                .disabled(!controller.canCapture)
                .accessibilityLabel("Capture and measure")

                Spacer()

                Button {
                    showHelp = true
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: "questionmark.circle").font(.title3)
                        Text("Tips").font(.caption2)
                    }
                    .frame(width: 72, height: 60)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
                }
            }
        }
        .foregroundStyle(.primary)
    }

    private var unsupportedMessage: some View {
        VStack(spacing: 14) {
            Image(systemName: "arkit")
                .font(.system(size: 54))
                .foregroundStyle(.white)
            Text("AR measuring needs an iPhone camera")
                .font(.title3.bold())
                .foregroundStyle(.white)
            Text("The simulator (and a few older devices) can't run ARKit. You can still type in a size from a gauge or ruler to check the rules.")
                .font(.subheadline)
                .multilineTextAlignment(.center)
                .foregroundStyle(.white.opacity(0.85))
            Button("Enter a size", action: onManual)
                .buttonStyle(.borderedProminent)
        }
        .padding(30)
    }

    private func capture() {
        guard let snapshot = controller.captureSnapshot() else {
            captureError = "The camera wasn't ready. Try again in a second."
            return
        }
        if snapshot.planeY == nil && snapshot.depth == nil {
            captureError = "No surface found yet. Move the phone slowly over the surface until the status says Ready."
            return
        }
        shutterCount += 1
        onCapture(snapshot)
    }
}

/// Center crosshair; turns green when a surface is locked.
struct ReticleView: View {
    let ready: Bool

    var body: some View {
        ZStack {
            Circle()
                .stroke(ready ? Theme.keep : .white.opacity(0.8), style: StrokeStyle(lineWidth: 2, dash: ready ? [] : [6, 6]))
                .frame(width: 120, height: 120)
            Rectangle().fill(ready ? Theme.keep : .white).frame(width: 2, height: 22)
            Rectangle().fill(ready ? Theme.keep : .white).frame(width: 22, height: 2)
        }
        .shadow(color: .black.opacity(0.4), radius: 2)
        .allowsHitTesting(false)
        .animation(.easeInOut(duration: 0.25), value: ready)
    }
}
