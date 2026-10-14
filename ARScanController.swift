import ARKit
import SceneKit
import SwiftUI
import AVFoundation
import CoreImage
import Observation

/// Owns the AR camera view, reports whether it's ready to measure, and captures
/// snapshots (photo + camera geometry + surface + LiDAR depth).
@Observable
final class ARScanController: NSObject, ARSessionDelegate {
    enum Readiness: Equatable {
        case starting
        case searching
        case ready
        case tooClose
        case tooFar
        case limited(String)
        case failed(String)
    }

    let arView = ARSCNView(frame: .zero)
    private let coaching = ARCoachingOverlayView()
    private let ciContext = CIContext()

    var readiness: Readiness = .starting
    var distanceMeters: Float? = nil
    var tiltDegrees: Float? = nil
    var supportsLiDAR = false
    var torchOn = false

    @ObservationIgnored private var lastStatusTime: TimeInterval = 0
    @ObservationIgnored private var configured = false

    static var isSupported: Bool { ARWorldTrackingConfiguration.isSupported }

    override init() {
        super.init()
        supportsLiDAR = ARWorldTrackingConfiguration.supportsFrameSemantics(.smoothedSceneDepth)
    }

    var canCapture: Bool {
        switch readiness {
        case .ready, .tooClose, .tooFar: return true
        case .searching: return supportsLiDAR
        case .starting, .limited, .failed: return false
        }
    }

    var statusText: String {
        switch readiness {
        case .starting:
            return "Starting camera…"
        case .searching:
            return supportsLiDAR ? "Aim at the catch — LiDAR is measuring depth" : "Move the phone slowly so it can find the surface"
        case .ready:
            if let distanceMeters {
                return "Ready · \(Int((distanceMeters * 100).rounded())) cm away"
            }
            return "Ready"
        case .tooClose:
            return "Too close — raise the phone a little"
        case .tooFar:
            return "Too far — move closer to the catch"
        case .limited(let message):
            return message
        case .failed(let message):
            return message
        }
    }

    // MARK: Session control

    func start() {
        guard ARScanController.isSupported else {
            readiness = .failed("This device can't run AR measuring. You can still enter sizes by hand.")
            return
        }
        if !configured {
            configured = true
            arView.session.delegate = self
            arView.automaticallyUpdatesLighting = false
            arView.debugOptions = [ARSCNDebugOptions.showFeaturePoints]
            coaching.session = arView.session
            coaching.goal = .horizontalPlane
            coaching.activatesAutomatically = true
            coaching.frame = arView.bounds
            coaching.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            arView.addSubview(coaching)
        }
        let configuration = ARWorldTrackingConfiguration()
        configuration.planeDetection = [.horizontal]
        if ARWorldTrackingConfiguration.supportsFrameSemantics(.smoothedSceneDepth) {
            configuration.frameSemantics.insert(.smoothedSceneDepth)
        }
        arView.session.run(configuration, options: [.resetTracking, .removeExistingAnchors])
        readiness = .starting
        distanceMeters = nil
    }

    func pause() {
        setTorch(false)
        arView.session.pause()
    }

    func setTorch(_ on: Bool) {
        guard let device = AVCaptureDevice.default(for: .video), device.hasTorch,
              device.isTorchModeSupported(on ? .on : .off) else {
            torchOn = false
            return
        }
        do {
            try device.lockForConfiguration()
            device.torchMode = on ? .on : .off
            device.unlockForConfiguration()
            torchOn = on
        } catch {
            torchOn = false
        }
    }

    // MARK: Capture

    func captureSnapshot() -> CaptureSnapshot? {
        guard let frame = arView.session.currentFrame else { return nil }
        let oriented = CIImage(cvPixelBuffer: frame.capturedImage).oriented(.right)
        guard let cgImage = ciContext.createCGImage(oriented, from: oriented.extent) else { return nil }
        let image = UIImage(cgImage: cgImage)

        var depth: DepthSample?
        if let sceneDepth = frame.smoothedSceneDepth ?? frame.sceneDepth {
            depth = DepthSample(depthMap: sceneDepth.depthMap, confidenceMap: sceneDepth.confidenceMap)
        }
        var trackingNormal = false
        if case .normal = frame.camera.trackingState { trackingNormal = true }

        return CaptureSnapshot(
            image: image,
            portraitPixelSize: CGSize(width: cgImage.width, height: cgImage.height),
            sensorResolution: frame.camera.imageResolution,
            intrinsics: frame.camera.intrinsics,
            cameraTransform: frame.camera.transform,
            planeY: supportSurfaceHeight(),
            depth: depth,
            trackingNormal: trackingNormal,
            capturedAt: Date())
    }

    /// Height of the surface under the catch: the median of hits on detected planes
    /// in a ring around the center of the screen (the catch itself hides the middle).
    private func supportSurfaceHeight() -> Float? {
        let bounds = arView.bounds
        guard bounds.width > 0, bounds.height > 0 else { return nil }
        let radius = min(bounds.width, bounds.height) * 0.38
        var heights: [Float] = []
        for step in 0..<12 {
            let angle = Double(step) / 12.0 * 2.0 * Double.pi
            let point = CGPoint(x: bounds.midX + radius * CGFloat(cos(angle)),
                                y: bounds.midY + radius * CGFloat(sin(angle)))
            if let y = raycastHeight(from: point, target: .existingPlaneGeometry) {
                heights.append(y)
            }
        }
        if heights.count >= 3 {
            heights.sort()
            return heights[heights.count / 2]
        }
        let center = CGPoint(x: bounds.midX, y: bounds.midY)
        if let y = raycastHeight(from: center, target: .existingPlaneInfinite) { return y }
        if let first = heights.first { return first }
        return raycastHeight(from: center, target: .estimatedPlane)
    }

    private func raycastHeight(from point: CGPoint, target: ARRaycastQuery.Target) -> Float? {
        guard let query = arView.raycastQuery(from: point, allowing: target, alignment: .horizontal),
              let hit = arView.session.raycast(query).first else { return nil }
        return hit.worldTransform.columns.3.y
    }

    // MARK: ARSessionDelegate

    func session(_ session: ARSession, didUpdate frame: ARFrame) {
        let now = frame.timestamp
        guard now - lastStatusTime > 0.25 else { return }
        lastStatusTime = now
        updateStatus(with: frame)
    }

    func session(_ session: ARSession, didFailWithError error: Error) {
        if let arError = error as? ARError, arError.code == .cameraUnauthorized {
            readiness = .failed("Camera access is off. Turn it on in Settings › MarineMeasure.")
        } else {
            readiness = .failed("The AR session stopped: \(error.localizedDescription)")
        }
    }

    func sessionWasInterrupted(_ session: ARSession) {
        readiness = .limited("Camera paused")
    }

    func sessionInterruptionEnded(_ session: ARSession) {
        readiness = .searching
    }

    private func updateStatus(with frame: ARFrame) {
        switch frame.camera.trackingState {
        case .notAvailable:
            readiness = .starting
            return
        case .limited(let reason):
            readiness = .limited(ARScanController.message(for: reason))
            return
        case .normal:
            break
        }

        let transform = frame.camera.transform
        let cameraPosition = SIMD3<Float>(transform.columns.3.x, transform.columns.3.y, transform.columns.3.z)
        let forward = -SIMD3<Float>(transform.columns.2.x, transform.columns.2.y, transform.columns.2.z)
        let cosine = max(-1, min(1, simd_dot(simd_normalize(forward), SIMD3<Float>(0, -1, 0))))
        tiltDegrees = acos(cosine) * 180 / Float.pi

        let center = CGPoint(x: arView.bounds.midX, y: arView.bounds.midY)
        var hitPoint: SIMD3<Float>?
        for target in [ARRaycastQuery.Target.existingPlaneInfinite, .estimatedPlane] {
            if let query = arView.raycastQuery(from: center, allowing: target, alignment: .horizontal),
               let hit = arView.session.raycast(query).first {
                let t = hit.worldTransform
                hitPoint = SIMD3<Float>(t.columns.3.x, t.columns.3.y, t.columns.3.z)
                break
            }
        }

        guard let hitPoint else {
            distanceMeters = nil
            readiness = .searching
            return
        }
        let distance = simd_distance(cameraPosition, hitPoint)
        distanceMeters = distance
        if distance < 0.18 {
            readiness = .tooClose
        } else if distance > 1.3 {
            readiness = .tooFar
        } else {
            readiness = .ready
        }
    }

    private static func message(for reason: ARCamera.TrackingState.Reason) -> String {
        switch reason {
        case .initializing: return "Getting ready — move the phone slowly"
        case .excessiveMotion: return "Slow down — hold the phone steadier"
        case .insufficientFeatures: return "Too dark or too plain — add light or texture"
        case .relocalizing: return "Re-finding the surface…"
        @unknown default: return "Tracking is limited"
        }
    }
}

extension DepthSample {
    /// Copies an ARKit depth map (Float32) and optional confidence map (UInt8).
    init?(depthMap: CVPixelBuffer, confidenceMap: CVPixelBuffer?) {
        CVPixelBufferLockBaseAddress(depthMap, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(depthMap, .readOnly) }
        let width = CVPixelBufferGetWidth(depthMap)
        let height = CVPixelBufferGetHeight(depthMap)
        let rowBytes = CVPixelBufferGetBytesPerRow(depthMap)
        guard width > 0, height > 0, let base = CVPixelBufferGetBaseAddress(depthMap) else { return nil }

        var depths = [Float](repeating: 0, count: width * height)
        for y in 0..<height {
            let row = base.advanced(by: y * rowBytes).assumingMemoryBound(to: Float32.self)
            for x in 0..<width {
                depths[y * width + x] = row[x]
            }
        }

        var confidence: [UInt8]?
        if let confidenceMap,
           CVPixelBufferGetWidth(confidenceMap) == width,
           CVPixelBufferGetHeight(confidenceMap) == height {
            CVPixelBufferLockBaseAddress(confidenceMap, .readOnly)
            defer { CVPixelBufferUnlockBaseAddress(confidenceMap, .readOnly) }
            if let confidenceBase = CVPixelBufferGetBaseAddress(confidenceMap) {
                let confidenceRowBytes = CVPixelBufferGetBytesPerRow(confidenceMap)
                var values = [UInt8](repeating: 0, count: width * height)
                for y in 0..<height {
                    let row = confidenceBase.advanced(by: y * confidenceRowBytes).assumingMemoryBound(to: UInt8.self)
                    for x in 0..<width {
                        values[y * width + x] = row[x]
                    }
                }
                confidence = values
            }
        }
        self.init(width: width, height: height, depths: depths, confidence: confidence)
    }
}

/// SwiftUI wrapper around the controller's ARSCNView.
struct ARCameraView: UIViewRepresentable {
    let controller: ARScanController

    func makeUIView(context: Context) -> ARSCNView {
        controller.arView
    }

    func updateUIView(_ uiView: ARSCNView, context: Context) {}
}
