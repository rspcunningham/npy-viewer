import AppKit
import MetalKit
import NPYCore
import UniformTypeIdentifiers

final class ViewerViewController: NSViewController, ImageMetalViewDelegate {
    private let metalView = ImageMetalView(frame: .zero, device: nil)
    private let overlay = OverlayTextField(labelWithString: "")
    private let fileLoadQueue = DispatchQueue(label: "com.parasight.NPYViewer.file-load", qos: .userInitiated)
    private var renderer: MetalRenderer?
    private var currentURL: URL?
    private var hoverText: String?
    private var overlayText = ""
    private var openRequestID = 0
    private let overlayAttributes: [NSAttributedString.Key: Any] = {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = 3
        return [
            .font: NSFont.monospacedSystemFont(ofSize: 12, weight: .regular),
            .foregroundColor: NSColor.white,
            .paragraphStyle: paragraph
        ]
    }()

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
        openRequestID &+= 1
        let requestID = openRequestID
        setOverlayText("Opening \(url.lastPathComponent)...")

        fileLoadQueue.async { [weak self] in
            let result = Result {
                try NPYArray(contentsOf: url)
            }

            DispatchQueue.main.async { [weak self] in
                guard let self, self.openRequestID == requestID else {
                    return
                }

                switch result {
                case .success(let array):
                    self.finishOpen(array: array, url: url)
                case .failure(let error):
                    self.showError(error, title: "Could Not Open \(url.lastPathComponent)")
                    self.updateOverlay()
                }
            }
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
            setHoverText(nil)
            return
        }

        setHoverText("x \(coordinate.x)  y \(coordinate.y)  \(value.displayString)")
    }

    func imageMetalViewDidEndHover(_ view: ImageMetalView) {
        setHoverText(nil)
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
        guard overlayText != text else {
            return
        }

        overlayText = text
        overlay.attributedStringValue = NSAttributedString(
            string: text,
            attributes: overlayAttributes
        )
        overlay.invalidateIntrinsicContentSize()
        overlay.needsDisplay = true
    }

    private func setHoverText(_ text: String?) {
        guard hoverText != text else {
            return
        }

        hoverText = text
        updateOverlay()
    }

    private func finishOpen(array: NPYArray, url: URL) {
        let previousURL = currentURL
        let previousHoverText = hoverText
        currentURL = url
        hoverText = nil

        do {
            try renderer?.setArray(array)
            onTitleChanged?(url.lastPathComponent)
            updateOverlay()
        } catch {
            currentURL = previousURL
            hoverText = previousHoverText
            showError(error, title: "Could Not Open \(url.lastPathComponent)")
            updateOverlay()
        }
    }

    private func showError(_ error: Error, title: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        alert.alertStyle = .warning
        alert.runModal()
    }
}
