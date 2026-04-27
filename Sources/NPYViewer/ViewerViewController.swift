import AppKit
import MetalKit
import NPYCore
import UniformTypeIdentifiers

final class ViewerViewController: NSViewController, ImageMetalViewDelegate {
    private let metalView = ImageMetalView(frame: .zero, device: nil)
    private let overlay = OverlayTextField(labelWithString: "")
    private var renderer: MetalRenderer?
    private var currentURL: URL?
    private var hoverText: String?

    var onTitleChanged: ((String) -> Void)?

    override func loadView() {
        view = NSView()
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.black.cgColor

        metalView.translatesAutoresizingMaskIntoConstraints = false
        metalView.interactionDelegate = self
        view.addSubview(metalView)

        overlay.translatesAutoresizingMaskIntoConstraints = false
        overlay.isEditable = false
        overlay.isSelectable = false
        overlay.isBordered = false
        overlay.drawsBackground = false
        overlay.textColor = .white
        overlay.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        overlay.maximumNumberOfLines = 6
        overlay.lineBreakMode = .byTruncatingTail
        view.addSubview(overlay)

        NSLayoutConstraint.activate([
            metalView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            metalView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            metalView.topAnchor.constraint(equalTo: view.topAnchor),
            metalView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            overlay.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12),
            overlay.topAnchor.constraint(equalTo: view.topAnchor, constant: 12),
            overlay.widthAnchor.constraint(lessThanOrEqualTo: view.widthAnchor, constant: -24)
        ])
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        do {
            let renderer = try MetalRenderer(view: metalView)
            renderer.onDisplayChanged = { [weak self] in
                self?.updateOverlay()
            }
            self.renderer = renderer
        } catch {
            showError(error, title: "Metal Setup Failed")
        }

        updateOverlay()
    }

    func open(url: URL) {
        do {
            let array = try NPYArray(contentsOf: url)
            try renderer?.setArray(array)
            currentURL = url
            hoverText = nil
            onTitleChanged?(url.lastPathComponent)
            updateOverlay()
        } catch {
            showError(error, title: "Could Not Open \(url.lastPathComponent)")
        }
    }

    func resetZoom() {
        renderer?.resetView()
        renderer?.requestDraw()
        updateOverlay()
    }

    func imageMetalView(_ view: ImageMetalView, didRequestOpen url: URL) {
        open(url: url)
    }

    func imageMetalView(_ view: ImageMetalView, didHoverAt point: CGPoint) {
        guard
            let renderer,
            let array = renderer.array,
            let coordinate = renderer.imageCoordinate(for: point),
            let value = array.pixelValue(x: coordinate.x, y: coordinate.y)
        else {
            hoverText = nil
            updateOverlay()
            return
        }

        hoverText = "x \(coordinate.x)  y \(coordinate.y)  \(value.displayString)"
        updateOverlay()
    }

    func imageMetalViewDidEndHover(_ view: ImageMetalView) {
        hoverText = nil
        updateOverlay()
    }

    func imageMetalView(_ view: ImageMetalView, didZoomBy factor: CGFloat, around point: CGPoint) {
        renderer?.zoom(by: factor, around: point)
    }

    func imageMetalView(_ view: ImageMetalView, didPanBy delta: CGSize) {
        renderer?.pan(by: delta)
    }

    func imageMetalView(_ view: ImageMetalView, didPress key: String) {
        guard let renderer else {
            return
        }

        switch key {
        case "a":
            renderer.setDisplayMode(.complexAbs)
        case "p":
            renderer.setDisplayMode(.complexPhase)
        case "r":
            renderer.setDisplayMode(.complexReal)
        case "i":
            renderer.setDisplayMode(.complexImag)
        case "m":
            renderer.cycleComplexMode()
        case "0":
            resetZoom()
        default:
            return
        }
    }

    private func updateOverlay() {
        guard let array = renderer?.array else {
            setOverlayText("Drop a .npy file or use File > Open")
            return
        }

        let file = currentURL?.lastPathComponent ?? array.url.lastPathComponent
        let shape = "\(array.height)x\(array.width)"
        let dtype = array.elementType.dtypeName
        let mode = renderer?.displayMode.label ?? "scalar"
        let hover = hoverText ?? "x -  y -"
        setOverlayText("\(file)\nshape \(shape)  dtype \(dtype)  mode \(mode)\n\(hover)")
    }

    private func setOverlayText(_ text: String) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = 3
        overlay.attributedStringValue = NSAttributedString(
            string: text,
            attributes: [
                .font: NSFont.monospacedSystemFont(ofSize: 12, weight: .regular),
                .foregroundColor: NSColor.white,
                .paragraphStyle: paragraph
            ]
        )
        overlay.invalidateIntrinsicContentSize()
        overlay.needsDisplay = true
    }

    private func showError(_ error: Error, title: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        alert.alertStyle = .warning
        alert.runModal()
    }
}
