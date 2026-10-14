import Foundation
import CoreGraphics
import simd
import UIKit

/// LiDAR depth copied out of an ARFrame (meters, same orientation as the camera sensor).
struct DepthSample {
    let width: Int
    let height: Int
    let depths: [Float]
    /// ARConfidenceLevel raw values: 0 low, 1 medium, 2 high.
    let confidence: [UInt8]?

    func value(x: Int, y: Int, minConfidence: UInt8) -> Float? {
        guard x >= 0, y >= 0, x < width, y < height else { return nil }
        let index = y * width + x
        if let confidence, index < confidence.count, confidence[index] < minConfidence { return nil }
        let depth = depths[index]
        guard depth.isFinite, depth > 0.05, depth < 5 else { return nil }
        return depth
    }
}

/// Everything captured at the moment the shutter is pressed. The AR session can be
/// paused afterwards; measuring only needs this snapshot.
struct CaptureSnapshot {
    /// Upright portrait photo (the sensor image rotated 90° clockwise).
    let image: UIImage
    /// Pixel size of `image` (width = sensor height, height = sensor width).
    let portraitPixelSize: CGSize
    /// Camera sensor resolution the intrinsics refer to (landscape, e.g. 1920 × 1440).
    let sensorResolution: CGSize
    let intrinsics: simd_float3x3
    /// Camera-to-world transform.
    let cameraTransform: simd_float4x4
    /// World-space height (y) of the surface the catch is lying on, if one was found.
    let planeY: Float?
    let depth: DepthSample?
    let trackingNormal: Bool
    let capturedAt: Date
}

struct MeasurementResult: Equatable {
    /// Length straight from the geometry, before any user calibration.
    var inches: Double
    var uncertaintyInches: Double
    var method: MeasureMethod
    var cameraDistanceMeters: Double?
    var warnings: [String]
}

enum MeasurementError: Error, Equatable {
    case noSurface
    case pointingAway
    case tooClose
    case tooShort

    var message: String {
        switch self {
        case .noSurface:
            return "No surface was locked in this photo. Retake it after the scanner says it's ready."
        case .pointingAway:
            return "One of the markers isn't on the surface. Keep both markers on the catch."
        case .tooClose:
            return "The phone was too close to the surface. Hold it 25–60 cm (10–24 in) above the catch."
        case .tooShort:
            return "Drag the two markers apart to the ends of the catch."
        }
    }
}

/// Turns two marker positions on a captured photo into a real-world length.
///
/// Geometry: each marker defines a ray from the camera through that pixel
/// (pinhole model, ARKit intrinsics). With LiDAR, the ray is cut at the measured
/// depth of the catch next to the marker. Without LiDAR, the ray is intersected
/// with the detected surface raised by the height of the measured points
/// (species `heightRatio` × length, solved iteratively), because the spine tips of
/// a crab sit above the table and would otherwise read too long.
enum MeasurementEngine {
    static let inchesPerMeter = 39.37007874

    /// Normalized point (0...1) in the portrait photo → pixel in the landscape sensor image.
    static func sensorPixel(fromNormalized point: CGPoint, snapshot: CaptureSnapshot) -> SIMD2<Float> {
        let portraitX = Float(point.x) * Float(snapshot.portraitPixelSize.width)
        let portraitY = Float(point.y) * Float(snapshot.portraitPixelSize.height)
        // The portrait image is the sensor image rotated 90° clockwise (UIImage.Orientation.right):
        // sensor column u = portrait row, sensor row v = sensorHeight - portrait column.
        let sensorHeight = Float(snapshot.sensorResolution.height)
        return SIMD2<Float>(portraitY, sensorHeight - portraitX)
    }

    /// World-space ray through a sensor pixel. The direction is scaled so that
    /// origin + direction * d is the point at camera depth d (meters).
    static func ray(through pixel: SIMD2<Float>, snapshot: CaptureSnapshot) -> (origin: SIMD3<Float>, direction: SIMD3<Float>) {
        let k = snapshot.intrinsics
        let fx = k.columns.0.x
        let fy = k.columns.1.y
        let cx = k.columns.2.x
        let cy = k.columns.2.y
        // ARKit camera space: +x right, +y up, camera looks down -z.
        let localX = (pixel.x - cx) / fx
        let localY = -(pixel.y - cy) / fy
        let t = snapshot.cameraTransform
        let axisX = SIMD3<Float>(t.columns.0.x, t.columns.0.y, t.columns.0.z)
        let axisY = SIMD3<Float>(t.columns.1.x, t.columns.1.y, t.columns.1.z)
        let axisZ = SIMD3<Float>(t.columns.2.x, t.columns.2.y, t.columns.2.z)
        var direction: SIMD3<Float> = axisX * localX
        direction += axisY * localY
        direction -= axisZ
        let origin = SIMD3<Float>(t.columns.3.x, t.columns.3.y, t.columns.3.z)
        return (origin, direction)
    }

    static func intersect(origin: SIMD3<Float>, direction: SIMD3<Float>, planeY: Float) -> SIMD3<Float>? {
        guard abs(direction.y) > 1e-6 else { return nil }
        let distance = (planeY - origin.y) / direction.y
        guard distance > 0 else { return nil }
        return origin + direction * distance
    }

    /// Median LiDAR depth of the catch a little inside the marker (the marker itself
    /// often sits on a thin spine or fin tip that the depth sensor can't resolve).
    static func depthNear(endpoint: SIMD2<Float>, toward other: SIMD2<Float>,
                          snapshot: CaptureSnapshot, depth: DepthSample) -> Float? {
        let scaleX = Float(depth.width) / Float(snapshot.sensorResolution.width)
        let scaleY = Float(depth.height) / Float(snapshot.sensorResolution.height)
        var samples: [Float] = []
        var fraction: Float = 0.12
        while fraction <= 0.345 {
            let step: SIMD2<Float> = (other - endpoint) * fraction
            let point: SIMD2<Float> = endpoint + step
            let dx = Int((point.x * scaleX).rounded())
            let dy = Int((point.y * scaleY).rounded())
            for oy in -1...1 {
                for ox in -1...1 {
                    if let value = depth.value(x: dx + ox, y: dy + oy, minConfidence: 1) {
                        samples.append(value)
                    }
                }
            }
            fraction += 0.02
        }
        guard samples.count >= 6 else { return nil }
        samples.sort()
        return samples[samples.count / 2]
    }

    /// Length on a horizontal surface at `planeY`, raised by heightRatio × length.
    static func lengthOnSurface(rayA: (origin: SIMD3<Float>, direction: SIMD3<Float>),
                                rayB: (origin: SIMD3<Float>, direction: SIMD3<Float>),
                                planeY: Float, heightRatio: Float) -> (length: Float, height: Float)? {
        var height: Float = 0
        var length: Float = 0
        for _ in 0..<8 {
            guard let a = intersect(origin: rayA.origin, direction: rayA.direction, planeY: planeY + height),
                  let b = intersect(origin: rayB.origin, direction: rayB.direction, planeY: planeY + height) else {
                return nil
            }
            length = simd_distance(a, b)
            height = heightRatio * length
        }
        return (length, height)
    }

    static func measure(snapshot: CaptureSnapshot, a: CGPoint, b: CGPoint,
                        heightRatio: Double) -> Result<MeasurementResult, MeasurementError> {
        let pixelA = sensorPixel(fromNormalized: a, snapshot: snapshot)
        let pixelB = sensorPixel(fromNormalized: b, snapshot: snapshot)
        guard simd_distance(pixelA, pixelB) > 12 else { return .failure(.tooShort) }

        let rayA = ray(through: pixelA, snapshot: snapshot)
        let rayB = ray(through: pixelB, snapshot: snapshot)
        var warnings: [String] = []
        var extraError: Float = 0
        if !snapshot.trackingNormal {
            warnings.append("AR tracking was limited when you captured, so accuracy may be lower.")
            extraError += 0.03
        }

        // 1) LiDAR depth (iPhone Pro models)
        if let depth = snapshot.depth,
           let depthA = depthNear(endpoint: pixelA, toward: pixelB, snapshot: snapshot, depth: depth),
           let depthB = depthNear(endpoint: pixelB, toward: pixelA, snapshot: snapshot, depth: depth) {
            let pointA: SIMD3<Float> = rayA.origin + rayA.direction * depthA
            let pointB: SIMD3<Float> = rayB.origin + rayB.direction * depthB
            let length = simd_distance(pointA, pointB)
            let distance = (depthA + depthB) / 2
            var relative: Float = 0.025 + extraError
            if distance < 0.15 {
                warnings.append("Very close to the catch. Hold the phone 25–60 cm (10–24 in) away.")
                relative += 0.02
            } else if distance > 1.0 {
                warnings.append("Far from the catch. Move closer for better accuracy.")
                relative += 0.02
            }
            return .success(MeasurementResult(
                inches: Double(length) * inchesPerMeter,
                uncertaintyInches: Double(length * relative) * inchesPerMeter + 0.03,
                method: .lidar,
                cameraDistanceMeters: Double(distance),
                warnings: warnings))
        }

        // 2) Detected surface
        guard let planeY = snapshot.planeY else { return .failure(.noSurface) }
        let cameraHeight = rayA.origin.y - planeY
        guard cameraHeight > 0.08 else { return .failure(.tooClose) }
        guard let solved = lengthOnSurface(rayA: rayA, rayB: rayB, planeY: planeY,
                                           heightRatio: Float(heightRatio)) else {
            return .failure(.pointingAway)
        }
        let clearance = max(cameraHeight - solved.height, 0.05)
        // ±50% uncertainty in how high the measured points sit above the surface.
        var relative: Float = 0.02 + extraError + (0.5 * solved.height) / clearance
        if cameraHeight < 0.2 {
            warnings.append("Very close to the surface. Hold the phone higher (25–60 cm).")
            relative += 0.02
        } else if cameraHeight > 1.2 {
            warnings.append("Far from the catch. Move closer for better accuracy.")
            relative += 0.02
        }
        return .success(MeasurementResult(
            inches: Double(solved.length) * inchesPerMeter,
            uncertaintyInches: Double(solved.length * relative) * inchesPerMeter + 0.03,
            method: .surface,
            cameraDistanceMeters: Double(cameraHeight),
            warnings: warnings))
    }
}
