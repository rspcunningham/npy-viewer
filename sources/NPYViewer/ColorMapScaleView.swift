import AppKit
import NPYViewerSupport

final class ColorMapScaleView: NSView {
    static let preferredHeight: CGFloat = 40

    private(set) var colorMap: ColorMap = .gray
    private(set) var displayMode: DisplayMode = .scalar
    private(set) var windowValue: Float = 1
    private(set) var levelValue: Float = 0.5
    private(set) var isScaleEnabled = false

    var tickLabels: [String] {
        guard isScaleEnabled else {
            return ["--", "--", "--"]
        }

        let values = [
            levelValue - windowValue * 0.5,
            levelValue,
            levelValue + windowValue * 0.5
        ]

        if displayMode == .complexPhase {
            return values.map(Self.phaseLabel)
        }

        return values.map(Self.valueLabel)
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: Self.preferredHeight)
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        toolTip = "Current colormap scale after window and level"
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        wantsLayer = true
        toolTip = "Current colormap scale after window and level"
    }

    func setState(
        colorMap: ColorMap,
        displayMode: DisplayMode,
        window: Float,
        level: Float,
        isScaleEnabled: Bool
    ) {
        let nextWindow = min(max(window, 0.01), 1)
        let nextLevel = min(max(level, 0), 1)
        guard
            self.colorMap != colorMap ||
            self.displayMode != displayMode ||
            self.windowValue != nextWindow ||
            self.levelValue != nextLevel ||
            self.isScaleEnabled != isScaleEnabled
        else {
            return
        }

        self.colorMap = colorMap
        self.displayMode = displayMode
        self.windowValue = nextWindow
        self.levelValue = nextLevel
        self.isScaleEnabled = isScaleEnabled
        toolTip = displayMode == .complexPhase
            ? "Current colormap scale after window and level; phase labels are radians"
            : "Current colormap scale after window and level"
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        let labelHeight: CGFloat = 15
        let labelGap: CGFloat = 5
        let gradientRect = NSRect(
            x: bounds.minX,
            y: bounds.minY + labelHeight + labelGap,
            width: bounds.width,
            height: 16
        )
        let labelRect = NSRect(
            x: bounds.minX,
            y: bounds.minY,
            width: bounds.width,
            height: labelHeight
        )

        drawScale(in: gradientRect)
        drawLabels(in: labelRect)
    }

    private func drawScale(in rect: NSRect) {
        guard rect.width > 0, rect.height > 0 else {
            return
        }

        let alpha: CGFloat = isScaleEnabled ? 1 : 0.42
        let clipPath = NSBezierPath(roundedRect: rect, xRadius: 4, yRadius: 4)

        NSGraphicsContext.saveGraphicsState()
        clipPath.addClip()

        let sampleCount = max(Int(ceil(rect.width * max(window?.backingScaleFactor ?? 1, 1))), 2)
        for index in 0..<sampleCount {
            let value = Float(index) / Float(sampleCount - 1)
            let x0 = rect.minX + CGFloat(index) * rect.width / CGFloat(sampleCount)
            let x1 = rect.minX + CGFloat(index + 1) * rect.width / CGFloat(sampleCount)
            Self.color(forNormalizedValue: value, colorMap: colorMap)
                .withAlphaComponent(alpha)
                .setFill()
            NSBezierPath(rect: NSRect(
                x: x0,
                y: rect.minY,
                width: max(1, x1 - x0 + 0.5),
                height: rect.height
            )).fill()
        }

        NSGraphicsContext.restoreGraphicsState()

        NSColor(white: 1, alpha: isScaleEnabled ? 0.18 : 0.08).setStroke()
        clipPath.lineWidth = 1
        clipPath.stroke()
    }

    private func drawLabels(in rect: NSRect) {
        guard rect.width > 0, rect.height > 0 else {
            return
        }

        let labels = tickLabels
        let color = NSColor(white: isScaleEnabled ? 0.68 : 0.38, alpha: 1)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 10, weight: .regular),
            .foregroundColor: color
        ]

        for (index, label) in labels.enumerated() {
            let size = label.size(withAttributes: attributes)
            let x: CGFloat
            switch index {
            case 0:
                x = rect.minX
            case 1:
                x = rect.midX - size.width * 0.5
            default:
                x = rect.maxX - size.width
            }
            let y = rect.minY + (rect.height - size.height) * 0.5
            label.draw(at: NSPoint(x: x, y: y), withAttributes: attributes)
        }
    }

    static func color(forNormalizedValue value: Float, colorMap: ColorMap) -> NSColor {
        let normalizedValue = CGFloat(min(max(value, 0), 1))
        let color: RGB

        switch colorMap {
        case .gray:
            color = RGB(normalizedValue, normalizedValue, normalizedValue)
        case .viridis:
            color = ramp(
                normalizedValue,
                colors: [
                    RGB(0.267, 0.005, 0.329),
                    RGB(0.231, 0.322, 0.545),
                    RGB(0.129, 0.569, 0.549),
                    RGB(0.369, 0.788, 0.384),
                    RGB(0.993, 0.906, 0.144)
                ]
            )
        case .magma:
            color = ramp(
                normalizedValue,
                colors: [
                    RGB(0.000, 0.000, 0.016),
                    RGB(0.231, 0.059, 0.439),
                    RGB(0.549, 0.161, 0.506),
                    RGB(0.871, 0.286, 0.408),
                    RGB(0.988, 0.992, 0.749)
                ]
            )
        case .hot:
            color = RGB(
                smoothstep(edge0: 0.00, edge1: 0.45, x: normalizedValue),
                smoothstep(edge0: 0.35, edge1: 0.75, x: normalizedValue),
                smoothstep(edge0: 0.70, edge1: 1.00, x: normalizedValue)
            )
        }

        return NSColor(
            calibratedRed: color.red,
            green: color.green,
            blue: color.blue,
            alpha: 1
        )
    }

    private typealias RGB = (red: CGFloat, green: CGFloat, blue: CGFloat)

    private static func ramp(_ value: CGFloat, colors: [RGB]) -> RGB {
        guard let first = colors.first, let last = colors.last else {
            return RGB(value, value, value)
        }
        guard value > 0 else {
            return first
        }
        guard value < 1 else {
            return last
        }

        let scaledValue = value * CGFloat(colors.count - 1)
        let lowerIndex = Int(floor(scaledValue))
        let fraction = scaledValue - CGFloat(lowerIndex)
        return mix(colors[lowerIndex], colors[lowerIndex + 1], fraction)
    }

    private static func mix(_ start: RGB, _ end: RGB, _ fraction: CGFloat) -> RGB {
        RGB(
            start.red + (end.red - start.red) * fraction,
            start.green + (end.green - start.green) * fraction,
            start.blue + (end.blue - start.blue) * fraction
        )
    }

    private static func smoothstep(edge0: CGFloat, edge1: CGFloat, x: CGFloat) -> CGFloat {
        let t = min(max((x - edge0) / (edge1 - edge0), 0), 1)
        return t * t * (3 - 2 * t)
    }

    private static func valueLabel(for value: Float) -> String {
        String(format: "%.2f", Double(value))
    }

    private static func phaseLabel(for normalizedValue: Float) -> String {
        let angle = Double(normalizedValue) * 2 * Double.pi - Double.pi
        if abs(angle + Double.pi) < 0.005 {
            return "-pi"
        }
        if abs(angle) < 0.005 {
            return "0"
        }
        if abs(angle - Double.pi) < 0.005 {
            return "+pi"
        }
        return String(format: "%.2f", angle)
    }
}
