import AppKit
import MetalKit

protocol ImageMetalViewDelegate: AnyObject {
    func imageMetalView(_ view: ImageMetalView, didRequestOpen url: URL)
    func imageMetalView(_ view: ImageMetalView, didHoverAt point: CGPoint)
    func imageMetalViewDidEndHover(_ view: ImageMetalView)
    func imageMetalView(_ view: ImageMetalView, didZoomBy factor: CGFloat, around point: CGPoint)
    func imageMetalView(_ view: ImageMetalView, didPanBy delta: CGSize)
}

final class ImageMetalView: MTKView {
    weak var interactionDelegate: ImageMetalViewDelegate?

    private var trackingAreaRef: NSTrackingArea?
    private var lastDragPoint: CGPoint?

    override init(frame frameRect: NSRect, device: MTLDevice?) {
        super.init(frame: frameRect, device: device)
        commonInit()
    }

    required init(coder: NSCoder) {
        super.init(coder: coder)
        commonInit()
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingAreaRef {
            removeTrackingArea(trackingAreaRef)
        }

        let area = NSTrackingArea(
            rect: bounds,
            options: [.activeAlways, .inVisibleRect, .mouseMoved, .mouseEnteredAndExited],
            owner: self
        )
        addTrackingArea(area)
        trackingAreaRef = area
    }

    override func scrollWheel(with event: NSEvent) {
        let point = topLeftPoint(for: event)
        let factor = pow(1.0025, event.scrollingDeltaY)
        interactionDelegate?.imageMetalView(self, didZoomBy: factor, around: point)
        interactionDelegate?.imageMetalView(self, didHoverAt: point)
    }

    override func mouseDown(with event: NSEvent) {
        lastDragPoint = topLeftPoint(for: event)
    }

    override func mouseDragged(with event: NSEvent) {
        let point = topLeftPoint(for: event)
        if let lastDragPoint {
            interactionDelegate?.imageMetalView(
                self,
                didPanBy: CGSize(width: point.x - lastDragPoint.x, height: point.y - lastDragPoint.y)
            )
        }
        lastDragPoint = point
        interactionDelegate?.imageMetalView(self, didHoverAt: point)
    }

    override func mouseUp(with event: NSEvent) {
        lastDragPoint = nil
        interactionDelegate?.imageMetalView(self, didHoverAt: topLeftPoint(for: event))
    }

    override func mouseMoved(with event: NSEvent) {
        interactionDelegate?.imageMetalView(self, didHoverAt: topLeftPoint(for: event))
    }

    override func mouseExited(with event: NSEvent) {
        interactionDelegate?.imageMetalViewDidEndHover(self)
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        npyURL(from: sender.draggingPasteboard) == nil ? [] : .copy
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard let url = npyURL(from: sender.draggingPasteboard) else {
            return false
        }
        interactionDelegate?.imageMetalView(self, didRequestOpen: url)
        return true
    }

    private func commonInit() {
        wantsLayer = true
        registerForDraggedTypes([.fileURL])
    }

    private func topLeftPoint(for event: NSEvent) -> CGPoint {
        let point = convert(event.locationInWindow, from: nil)
        return CGPoint(x: point.x, y: bounds.height - point.y)
    }

    private func npyURL(from pasteboard: NSPasteboard) -> URL? {
        guard
            let text = pasteboard.string(forType: .fileURL),
            let url = URL(string: text),
            url.pathExtension.lowercased() == "npy"
        else {
            return nil
        }
        return url
    }
}
