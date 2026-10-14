import Foundation
import Vision
import CoreML
import UIKit

/// Uses Vision's subject lifting (iOS 17) to find the two farthest-apart points of
/// the main subject. That's the snout-to-tail line for a fish lying flat, so the
/// markers start in the right place and only need fine tuning.
enum SubjectEndpointFinder {
    static func endpoints(in cgImage: CGImage) -> (CGPoint, CGPoint)? {
        let request = VNGenerateForegroundInstanceMaskRequest()
        let handler = VNImageRequestHandler(cgImage: cgImage, orientation: .up, options: [:])
        do {
            try handler.perform([request])
        } catch {
            return nil
        }
        guard let observation = request.results?.first else { return nil }
        let mask = observation.instanceMask

        CVPixelBufferLockBaseAddress(mask, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(mask, .readOnly) }
        let width = CVPixelBufferGetWidth(mask)
        let height = CVPixelBufferGetHeight(mask)
        let rowBytes = CVPixelBufferGetBytesPerRow(mask)
        guard width > 2, height > 2, let base = CVPixelBufferGetBaseAddress(mask) else { return nil }

        // Largest instance label.
        var counts: [UInt8: Int] = [:]
        for y in stride(from: 0, to: height, by: 2) {
            let row = base.advanced(by: y * rowBytes).assumingMemoryBound(to: UInt8.self)
            for x in stride(from: 0, to: width, by: 2) where row[x] != 0 {
                counts[row[x], default: 0] += 1
            }
        }
        guard let label = counts.max(by: { $0.value < $1.value })?.key else { return nil }

        // Leftmost and rightmost pixel of the subject in each row (enough for the convex hull).
        let aspect = Double(cgImage.width) / Double(max(cgImage.height, 1))
        var points: [SIMD2<Double>] = []
        for y in 0..<height {
            let row = base.advanced(by: y * rowBytes).assumingMemoryBound(to: UInt8.self)
            var first = -1
            var last = -1
            for x in 0..<width where row[x] == label {
                if first < 0 { first = x }
                last = x
            }
            guard first >= 0 else { continue }
            let ny = (Double(y) + 0.5) / Double(height)
            points.append(SIMD2((Double(first) + 0.5) / Double(width) * aspect, ny))
            if last != first {
                points.append(SIMD2((Double(last) + 0.5) / Double(width) * aspect, ny))
            }
        }
        let hull = convexHull(points)
        guard hull.count >= 2 else { return nil }

        var best = (0, 1)
        var bestDistance = -1.0
        for i in 0..<hull.count {
            for j in (i + 1)..<hull.count {
                let delta = hull[i] - hull[j]
                let distance = delta.x * delta.x + delta.y * delta.y
                if distance > bestDistance {
                    bestDistance = distance
                    best = (i, j)
                }
            }
        }
        let a = hull[best.0]
        let b = hull[best.1]
        return (CGPoint(x: a.x / aspect, y: a.y), CGPoint(x: b.x / aspect, y: b.y))
    }

    /// Andrew's monotone chain.
    private static func convexHull(_ input: [SIMD2<Double>]) -> [SIMD2<Double>] {
        let points = input.sorted { $0.x == $1.x ? $0.y < $1.y : $0.x < $1.x }
        guard points.count > 2 else { return points }
        func cross(_ o: SIMD2<Double>, _ a: SIMD2<Double>, _ b: SIMD2<Double>) -> Double {
            (a.x - o.x) * (b.y - o.y) - (a.y - o.y) * (b.x - o.x)
        }
        var lower: [SIMD2<Double>] = []
        for point in points {
            while lower.count >= 2 && cross(lower[lower.count - 2], lower[lower.count - 1], point) <= 0 {
                lower.removeLast()
            }
            lower.append(point)
        }
        var upper: [SIMD2<Double>] = []
        for point in points.reversed() {
            while upper.count >= 2 && cross(upper[upper.count - 2], upper[upper.count - 1], point) <= 0 {
                upper.removeLast()
            }
            upper.append(point)
        }
        lower.removeLast()
        upper.removeLast()
        return lower + upper
    }
}

/// Optional on-device sex classifier. Train an Image Classifier in Create ML with
/// folders named "male" and "female" (for example the claw photos from the
/// capstone project), export it as CrabSexClassifier.mlmodel and drag it into the
/// Xcode project. The app picks it up automatically; without it this does nothing.
enum SexClassifier {
    private static var modelURL: URL? {
        Bundle.main.url(forResource: "CrabSexClassifier", withExtension: "mlmodelc")
    }

    static var isAvailable: Bool { modelURL != nil }

    struct Suggestion: Equatable {
        let sex: CrabSex
        let label: String
        let confidence: Double
    }

    static func classify(_ cgImage: CGImage) -> Suggestion? {
        guard let url = modelURL,
              let model = try? MLModel(contentsOf: url),
              let visionModel = try? VNCoreMLModel(for: model) else { return nil }
        let request = VNCoreMLRequest(model: visionModel)
        request.imageCropAndScaleOption = .centerCrop
        let handler = VNImageRequestHandler(cgImage: cgImage, orientation: .up, options: [:])
        do {
            try handler.perform([request])
        } catch {
            return nil
        }
        guard let best = (request.results as? [VNClassificationObservation])?.first else { return nil }
        let label = best.identifier.lowercased()
        let sex: CrabSex
        if label.contains("sponge") || label.contains("egg") {
            sex = .eggBearing
        } else if label.contains("female") || label.contains("sook") || label.contains("sally") {
            sex = .matureFemale
        } else if label.contains("male") || label.contains("jimmy") {
            sex = .male
        } else {
            return nil
        }
        return Suggestion(sex: sex, label: best.identifier, confidence: Double(best.confidence))
    }
}
