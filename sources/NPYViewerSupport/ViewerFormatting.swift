import Foundation
import NPYCore

public enum ViewerFormatting {
    public static let hoverFieldWidth = 9

    public static func hoverText(
        array: NPYArray,
        coordinate: (x: Int, y: Int),
        value: NPYPixelValue
    ) -> String {
        let x = fixedWidth(coordinate.x, width: indexWidth(for: array.width))
        let y = fixedWidth(coordinate.y, width: indexWidth(for: array.height))
        return """
        \(paddedField("x")) \(x)
        \(paddedField("y")) \(y)
        \(sidebarDisplayString(for: value))
        """
    }

    public static func placeholderHoverText(for array: NPYArray) -> String {
        let x = String(repeating: "-", count: indexWidth(for: array.width))
        let y = String(repeating: "-", count: indexWidth(for: array.height))
        return """
        \(paddedField("x")) \(x)
        \(paddedField("y")) \(y)
        """
    }

    public static func indexWidth(for count: Int) -> Int {
        String(max(count - 1, 0)).count
    }

    public static func fixedWidth(_ value: Int, width: Int) -> String {
        let text = String(value)
        guard text.count < width else {
            return text
        }
        return String(repeating: " ", count: width - text.count) + text
    }

    public static func paddedField(_ field: String) -> String {
        field.padding(toLength: hoverFieldWidth, withPad: " ", startingAt: 0)
    }

    public static func controlValue(_ value: Float) -> String {
        String(format: "%.2f", Double(value))
    }

    public static func sidebarDisplayString(for value: NPYPixelValue) -> String {
        switch value {
        case .scalar(let value):
            return "\(paddedField("value")) \(format(value))"
        case .complex(let real, let imag):
            let magnitude = hypotf(real, imag)
            let intensity = real * real + imag * imag
            let phase = atan2f(imag, real)
            return """
            \(paddedField("real")) \(format(real))
            \(paddedField("imag")) \(format(imag))
            \(paddedField("abs")) \(format(magnitude))
            \(paddedField("intensity")) \(format(intensity))
            \(paddedField("phase")) \(format(phase))
            """
        }
    }

    private static func format(_ value: Float) -> String {
        String(format: "% .7f", Double(value))
    }
}
