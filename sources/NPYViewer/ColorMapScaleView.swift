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
        let color = colorMap.color(forNormalizedValue: value)

        return NSColor(
            calibratedRed: CGFloat(color.red),
            green: CGFloat(color.green),
            blue: CGFloat(color.blue),
            alpha: 1
        )
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
