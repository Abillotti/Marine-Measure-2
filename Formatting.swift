import SwiftUI
import UIKit

enum Units {
    static let centimetersPerInch = 2.54

    static func centimeters(_ inches: Double) -> Double { inches * centimetersPerInch }
    static func inches(fromCentimeters cm: Double) -> Double { cm / centimetersPerInch }

    /// "5.25 in" or "13.3 cm".
    static func format(_ inches: Double, metric: Bool, decimals: Int? = nil) -> String {
        if metric {
            return String(format: "%.\(decimals ?? 1)f cm", centimeters(inches))
        }
        return String(format: "%.\(decimals ?? 2)f in", inches)
    }

    /// Just the number, no unit ("5.25").
    static func number(_ inches: Double, metric: Bool, decimals: Int? = nil) -> String {
        if metric {
            return String(format: "%.\(decimals ?? 1)f", centimeters(inches))
        }
        return String(format: "%.\(decimals ?? 2)f", inches)
    }

    static func unitLabel(metric: Bool) -> String { metric ? "cm" : "in" }

    /// "± 0.12 in"
    static func uncertainty(_ inches: Double, metric: Bool) -> String {
        "± " + format(inches, metric: metric)
    }

    /// Compact rule value: 5 -> "5", 5.25 -> "5.25", 2.875 -> "2.875"
    static func ruleNumber(_ inches: Double) -> String {
        var text = String(format: "%.3f", inches)
        while text.hasSuffix("0") { text.removeLast() }
        if text.hasSuffix(".") { text.removeLast() }
        return text
    }

    static func ruleValue(_ inches: Double, metric: Bool) -> String {
        if metric { return String(format: "%.1f cm", centimeters(inches)) }
        return ruleNumber(inches) + " in"
    }
}

extension Date {
    /// "yyyy-MM-dd" in the current time zone; used to count distinct days.
    var dayKey: String {
        let comps = Calendar.current.dateComponents([.year, .month, .day], from: self)
        return String(format: "%04d-%02d-%02d", comps.year ?? 0, comps.month ?? 0, comps.day ?? 0)
    }

    var monthStart: Date {
        let comps = Calendar.current.dateComponents([.year, .month], from: self)
        return Calendar.current.date(from: comps) ?? self
    }
}

extension UIImage {
    /// Returns a copy scaled so the longest side is at most `maxDimension` points (scale 1).
    func scaled(maxDimension: CGFloat) -> UIImage {
        let longest = max(size.width, size.height)
        guard longest > maxDimension, longest > 0 else { return self }
        let ratio = maxDimension / longest
        let newSize = CGSize(width: (size.width * ratio).rounded(), height: (size.height * ratio).rounded())
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: newSize, format: format)
        return renderer.image { _ in
            self.draw(in: CGRect(origin: .zero, size: newSize))
        }
    }

    func jpeg(maxDimension: CGFloat, quality: CGFloat) -> Data? {
        scaled(maxDimension: maxDimension).jpegData(compressionQuality: quality)
    }
}

/// Fits an image of `imageSize` inside `container` (aspect fit) and returns the drawn rect.
func aspectFitRect(imageSize: CGSize, in container: CGSize) -> CGRect {
    guard imageSize.width > 0, imageSize.height > 0, container.width > 0, container.height > 0 else {
        return CGRect(origin: .zero, size: container)
    }
    let imageAspect = imageSize.width / imageSize.height
    let containerAspect = container.width / container.height
    var width = container.width
    var height = container.height
    if imageAspect > containerAspect {
        height = width / imageAspect
    } else {
        width = height * imageAspect
    }
    return CGRect(x: (container.width - width) / 2, y: (container.height - height) / 2, width: width, height: height)
}
