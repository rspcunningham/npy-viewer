import AppKit

final class OverlayTextField: NSTextField {
    private let insets = NSEdgeInsets(top: 7, left: 9, bottom: 7, right: 9)

    override var intrinsicContentSize: NSSize {
        let size = super.intrinsicContentSize
        return NSSize(width: size.width + insets.left + insets.right, height: size.height + insets.top + insets.bottom)
    }

    override func draw(_ dirtyRect: NSRect) {
        NSGraphicsContext.saveGraphicsState()
        let path = NSBezierPath(roundedRect: bounds, xRadius: 6, yRadius: 6)
        NSColor.black.withAlphaComponent(0.62).setFill()
        path.fill()
        NSGraphicsContext.restoreGraphicsState()

        let textRect = bounds.insetBy(dx: insets.left, dy: insets.top)
        attributedStringValue.draw(in: textRect)
    }
}
