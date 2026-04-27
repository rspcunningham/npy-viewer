import AppKit
import MetalKit
import NPYCore
import UniformTypeIdentifiers

final class ViewerViewController: NSViewController, ImageMetalViewDelegate {
    private let metalView = ImageMetalView(frame: .zero, device: nil)
    private let modePopUp = NSPopUpButton(frame: .zero, pullsDown: false)
    private let colorMapPopUp = NSPopUpButton(frame: .zero, pullsDown: false)
    private let fileLabel = NSTextField(labelWithString: "Drop a .npy file or use File > Open")
    private let shapeLabel = NSTextField(labelWithString: "shape -")
    private let dtypeLabel = NSTextField(labelWithString: "dtype -")
    private let cursorLabel = NSTextField(labelWithString: "x -  y -")
    private let sidebarWidth: CGFloat = 248
    private let fileLoadQueue = DispatchQueue(label: "com.parasight.NPYViewer.file-load", qos: .userInitiated)
    private var renderer: MetalRenderer?
    private var currentURL: URL?
    private var hoverText: String?
    private var openRequestID = 0

    var onTitleChanged: ((String) -> Void)?

    override func loadView() {
        view = NSView()
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.black.cgColor

        metalView.translatesAutoresizingMaskIntoConstraints = false
        metalView.interactionDelegate = self
        view.addSubview(metalView)

        let sidebar = makeSidebar()
        sidebar.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(sidebar)

        let divider = makeDivider()
        divider.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(divider)

        NSLayoutConstraint.activate([
            metalView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            metalView.trailingAnchor.constraint(equalTo: divider.leadingAnchor),
            metalView.topAnchor.constraint(equalTo: view.topAnchor),
            metalView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            divider.trailingAnchor.constraint(equalTo: sidebar.leadingAnchor),
            divider.topAnchor.constraint(equalTo: view.topAnchor),
            divider.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            divider.widthAnchor.constraint(equalToConstant: 1),

            sidebar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            sidebar.topAnchor.constraint(equalTo: view.topAnchor),
            sidebar.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            sidebar.widthAnchor.constraint(equalToConstant: sidebarWidth)
        ])
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        do {
            let renderer = try MetalRenderer(view: metalView)
            renderer.onDisplayChanged = { [weak self] in
                self?.updateInspector()
            }
            self.renderer = renderer
        } catch {
            showError(error, title: "Metal Setup Failed")
        }

        updateInspector()
    }

    func open(url: URL) {
        openRequestID &+= 1
        let requestID = openRequestID
        fileLabel.stringValue = "Opening \(url.lastPathComponent)..."
        shapeLabel.stringValue = "shape -"
        dtypeLabel.stringValue = "dtype -"
        cursorLabel.stringValue = "x -  y -"

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
                    self.updateInspector()
                }
            }
        }
    }

    func resetZoom() {
        renderer?.resetView()
        renderer?.requestDraw()
        updateInspector()
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

        setHoverText(formatHoverText(array: array, coordinate: coordinate, value: value))
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

    @objc private func modeChanged(_ sender: NSPopUpButton) {
        guard let mode = DisplayMode(rawValue: UInt32(sender.selectedTag())) else {
            return
        }

        renderer?.setDisplayMode(mode)
        updateInspector()
    }

    @objc private func colorMapChanged(_ sender: NSPopUpButton) {
        guard let colorMap = ColorMap(rawValue: UInt32(sender.selectedTag())) else {
            return
        }

        renderer?.setColorMap(colorMap)
        updateInspector()
    }

    private func makeSidebar() -> NSView {
        let sidebar = NSView()
        sidebar.wantsLayer = true
        sidebar.appearance = NSAppearance(named: .darkAqua)
        sidebar.layer?.backgroundColor = NSColor(
            calibratedRed: 0.105,
            green: 0.108,
            blue: 0.116,
            alpha: 1
        ).cgColor

        configurePopUps()
        configureMetadataLabels()

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        sidebar.addSubview(stack)

        stack.addArrangedSubview(makeControlGroup(title: "Mode", control: modePopUp))
        stack.addArrangedSubview(makeControlGroup(title: "Colormap", control: colorMapPopUp))
        stack.addArrangedSubview(makeSpacer(height: 12))
        stack.addArrangedSubview(fileLabel)
        stack.addArrangedSubview(shapeLabel)
        stack.addArrangedSubview(dtypeLabel)
        stack.addArrangedSubview(makeSpacer(height: 8))
        stack.addArrangedSubview(cursorLabel)

        for arrangedSubview in stack.arrangedSubviews {
            arrangedSubview.translatesAutoresizingMaskIntoConstraints = false
            arrangedSubview.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        }

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: sidebar.leadingAnchor, constant: 18),
            stack.trailingAnchor.constraint(equalTo: sidebar.trailingAnchor, constant: -18),
            stack.topAnchor.constraint(equalTo: sidebar.topAnchor, constant: 18)
        ])

        return sidebar
    }

    private func makeDivider() -> NSView {
        let divider = NSView()
        divider.wantsLayer = true
        divider.layer?.backgroundColor = NSColor(
            calibratedRed: 0.19,
            green: 0.20,
            blue: 0.22,
            alpha: 1
        ).cgColor
        return divider
    }

    private func configurePopUps() {
        modePopUp.target = self
        modePopUp.action = #selector(modeChanged(_:))
        modePopUp.controlSize = .regular
        modePopUp.font = .systemFont(ofSize: 13)

        colorMapPopUp.target = self
        colorMapPopUp.action = #selector(colorMapChanged(_:))
        colorMapPopUp.controlSize = .regular
        colorMapPopUp.font = .systemFont(ofSize: 13)
        colorMapPopUp.removeAllItems()
        for colorMap in ColorMap.allCases {
            colorMapPopUp.addItem(withTitle: colorMap.label)
            colorMapPopUp.lastItem?.tag = Int(colorMap.rawValue)
        }
    }

    private func configureMetadataLabels() {
        for label in [fileLabel, shapeLabel, dtypeLabel, cursorLabel] {
            label.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
            label.textColor = NSColor(white: 0.70, alpha: 1)
            label.maximumNumberOfLines = 2
            label.lineBreakMode = .byTruncatingMiddle
        }

        fileLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        fileLabel.textColor = NSColor(white: 0.92, alpha: 1)
        cursorLabel.maximumNumberOfLines = 6
        cursorLabel.lineBreakMode = .byWordWrapping
        cursorLabel.textColor = NSColor(white: 0.82, alpha: 1)
    }

    private func makeControlGroup(title: String, control: NSControl) -> NSView {
        let titleLabel = NSTextField(labelWithString: title.uppercased())
        titleLabel.font = .systemFont(ofSize: 10, weight: .medium)
        titleLabel.textColor = NSColor(white: 0.54, alpha: 1)
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        control.translatesAutoresizingMaskIntoConstraints = false
        control.setContentHuggingPriority(.defaultLow, for: .horizontal)
        control.heightAnchor.constraint(equalToConstant: 28).isActive = true

        let group = NSStackView(views: [titleLabel, control])
        group.orientation = .vertical
        group.alignment = .leading
        group.spacing = 5
        group.distribution = .fill

        NSLayoutConstraint.activate([
            titleLabel.widthAnchor.constraint(equalTo: group.widthAnchor),
            control.widthAnchor.constraint(equalTo: group.widthAnchor)
        ])

        return group
    }

    private func makeSpacer(height: CGFloat) -> NSView {
        let spacer = NSView()
        spacer.translatesAutoresizingMaskIntoConstraints = false
        spacer.heightAnchor.constraint(equalToConstant: height).isActive = true
        return spacer
    }

    private func updateInspector() {
        updateModePopUp()
        updateColorMapPopUp()

        guard let array = renderer?.array else {
            fileLabel.stringValue = "Drop a .npy file or use File > Open"
            shapeLabel.stringValue = "shape -"
            dtypeLabel.stringValue = "dtype -"
            cursorLabel.stringValue = "x -  y -"
            return
        }

        let file = currentURL?.lastPathComponent ?? array.url.lastPathComponent
        fileLabel.stringValue = file
        shapeLabel.stringValue = "shape \(array.height)x\(array.width)"
        dtypeLabel.stringValue = "dtype \(array.elementType.dtypeName)"
        updateCursorText()
    }

    private func updateModePopUp() {
        let array = renderer?.array
        let modes: [DisplayMode]
        if array?.elementType == .complex64 {
            modes = [.complexAbs, .complexPhase, .complexReal, .complexImag]
        } else {
            modes = [.scalar]
        }

        modePopUp.removeAllItems()
        for mode in modes {
            modePopUp.addItem(withTitle: mode.menuLabel)
            modePopUp.lastItem?.tag = Int(mode.rawValue)
        }

        let selectedMode = renderer?.displayMode ?? .scalar
        modePopUp.selectItem(withTag: Int(selectedMode.rawValue))
        modePopUp.isEnabled = array != nil && modes.count > 1
    }

    private func updateColorMapPopUp() {
        let selectedColorMap = renderer?.colorMap ?? .gray
        colorMapPopUp.selectItem(withTag: Int(selectedColorMap.rawValue))
        colorMapPopUp.isEnabled = renderer?.array != nil
    }

    private func updateCursorText() {
        guard let array = renderer?.array else {
            cursorLabel.stringValue = "x -  y -"
            return
        }

        cursorLabel.stringValue = hoverText ?? placeholderHoverText(for: array)
    }

    private func formatHoverText(
        array: NPYArray,
        coordinate: (x: Int, y: Int),
        value: NPYPixelValue
    ) -> String {
        let x = fixedWidth(coordinate.x, width: indexWidth(for: array.width))
        let y = fixedWidth(coordinate.y, width: indexWidth(for: array.height))
        return """
        \(paddedField("x")) \(x)
        \(paddedField("y")) \(y)
        \(value.sidebarDisplayString)
        """
    }

    private func placeholderHoverText(for array: NPYArray) -> String {
        let x = String(repeating: "-", count: indexWidth(for: array.width))
        let y = String(repeating: "-", count: indexWidth(for: array.height))
        return """
        \(paddedField("x")) \(x)
        \(paddedField("y")) \(y)
        """
    }

    private func indexWidth(for count: Int) -> Int {
        String(max(count - 1, 0)).count
    }

    private func fixedWidth(_ value: Int, width: Int) -> String {
        let text = String(value)
        guard text.count < width else {
            return text
        }
        return String(repeating: " ", count: width - text.count) + text
    }

    private func paddedField(_ field: String) -> String {
        field.padding(toLength: 5, withPad: " ", startingAt: 0)
    }

    private func setHoverText(_ text: String?) {
        guard hoverText != text else {
            return
        }

        hoverText = text
        updateCursorText()
    }

    private func finishOpen(array: NPYArray, url: URL) {
        let previousURL = currentURL
        let previousHoverText = hoverText
        currentURL = url
        hoverText = nil

        do {
            try renderer?.setArray(array)
            onTitleChanged?(url.lastPathComponent)
            updateInspector()
        } catch {
            currentURL = previousURL
            hoverText = previousHoverText
            showError(error, title: "Could Not Open \(url.lastPathComponent)")
            updateInspector()
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

private extension NPYPixelValue {
    var sidebarDisplayString: String {
        switch self {
        case .scalar(let value):
            return "\(Self.paddedField("value")) \(Self.format(value))"
        case .complex(let real, let imag):
            let magnitude = hypotf(real, imag)
            let phase = atan2f(imag, real)
            return """
            \(Self.paddedField("real")) \(Self.format(real))
            \(Self.paddedField("imag")) \(Self.format(imag))
            \(Self.paddedField("abs")) \(Self.format(magnitude))
            \(Self.paddedField("phase")) \(Self.format(phase))
            """
        }
    }

    static func format(_ value: Float) -> String {
        String(format: "% .7f", Double(value))
    }

    static func paddedField(_ field: String) -> String {
        field.padding(toLength: 5, withPad: " ", startingAt: 0)
    }
}
