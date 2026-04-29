import Foundation

public struct ColorMapRGB: Equatable, Sendable {
    public let red: Float
    public let green: Float
    public let blue: Float

    public init(red: Float, green: Float, blue: Float) {
        self.red = red
        self.green = green
        self.blue = blue
    }
}

public enum ColorMap: UInt32, CaseIterable, Sendable {
    case gray = 0
    case viridis = 1
    case magma = 2
    case hot = 3

    public var label: String {
        switch self {
        case .gray:
            "Gray"
        case .viridis:
            "Viridis"
        case .magma:
            "Magma"
        case .hot:
            "Hot"
        }
    }

    public func color(forNormalizedValue value: Float) -> ColorMapRGB {
        let value = Self.clamp(value)
        switch self {
        case .gray:
            return ColorMapRGB(red: value, green: value, blue: value)
        case .viridis:
            return Self.ramp(value, colors: Self.viridisStops)
        case .magma:
            return Self.ramp(value, colors: Self.magmaStops)
        case .hot:
            return ColorMapRGB(
                red: Self.smoothstep(edge0: 0.00, edge1: 0.45, x: value),
                green: Self.smoothstep(edge0: 0.35, edge1: 0.75, x: value),
                blue: Self.smoothstep(edge0: 0.70, edge1: 1.00, x: value)
            )
        }
    }

    private static let viridisStops = [
        ColorMapRGB(red: 0.267, green: 0.005, blue: 0.329),
        ColorMapRGB(red: 0.231, green: 0.322, blue: 0.545),
        ColorMapRGB(red: 0.129, green: 0.569, blue: 0.549),
        ColorMapRGB(red: 0.369, green: 0.788, blue: 0.384),
        ColorMapRGB(red: 0.993, green: 0.906, blue: 0.144)
    ]

    private static let magmaStops = [
        ColorMapRGB(red: 0.000, green: 0.000, blue: 0.016),
        ColorMapRGB(red: 0.231, green: 0.059, blue: 0.439),
        ColorMapRGB(red: 0.549, green: 0.161, blue: 0.506),
        ColorMapRGB(red: 0.871, green: 0.286, blue: 0.408),
        ColorMapRGB(red: 0.988, green: 0.992, blue: 0.749)
    ]

    private static func ramp(_ value: Float, colors: [ColorMapRGB]) -> ColorMapRGB {
        guard let first = colors.first, let last = colors.last else {
            return ColorMapRGB(red: value, green: value, blue: value)
        }
        guard value > 0 else {
            return first
        }
        guard value < 1 else {
            return last
        }

        let scaledValue = value * Float(colors.count - 1)
        let lowerIndex = Int(floorf(scaledValue))
        let fraction = scaledValue - Float(lowerIndex)
        return mix(colors[lowerIndex], colors[lowerIndex + 1], fraction)
    }

    private static func mix(_ start: ColorMapRGB, _ end: ColorMapRGB, _ fraction: Float) -> ColorMapRGB {
        ColorMapRGB(
            red: start.red + (end.red - start.red) * fraction,
            green: start.green + (end.green - start.green) * fraction,
            blue: start.blue + (end.blue - start.blue) * fraction
        )
    }

    private static func smoothstep(edge0: Float, edge1: Float, x: Float) -> Float {
        let t = clamp((x - edge0) / (edge1 - edge0))
        return t * t * (3 - 2 * t)
    }

    private static func clamp(_ value: Float) -> Float {
        min(max(value, 0), 1)
    }
}
