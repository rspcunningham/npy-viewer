import AppKit
import MetalKit
import NPYCore
import NPYViewerSupport
import UniformTypeIdentifiers

final class CanvasEmptyStateView: NSView {
    override func hitTest(_ point: NSPoint) -> NSView? {
        let hitView = super.hitTest(point)
        return hitView === self ? nil : hitView
    }
}

final class FileNavigatorTableView: NSTableView {
    weak var fallbackFirstResponder: NSResponder?

    override func mouseDown(with event: NSEvent) {
        let previousFirstResponder = window?.firstResponder
        super.mouseDown(with: event)
        restoreFirstResponder(previousFirstResponder)
    }

    private func restoreFirstResponder(_ previousFirstResponder: NSResponder?) {
        guard window?.firstResponder === self else {
            return
        }

        if let previousFirstResponder, previousFirstResponder !== self {
            window?.makeFirstResponder(previousFirstResponder)
        } else if let fallbackFirstResponder {
            window?.makeFirstResponder(fallbackFirstResponder)
        }
    }
}

private enum ViewerOpenError: LocalizedError {
    case unsupportedFile(URL)
    case noNPYFiles(URL)

    var errorDescription: String? {
        switch self {
        case .unsupportedFile(let url):
            "Unsupported file \(url.lastPathComponent). Open a .npy file or a directory containing .npy files."
        case .noNPYFiles(let url):
            "No .npy files found in \(url.lastPathComponent)."
        }
    }
}

final class ViewerViewController: NSViewController, ImageMetalViewDelegate, NSTableViewDataSource, NSTableViewDelegate {
    private struct ViewerItem {
        let url: URL
    }

    private static let emptyStatePrompt = "Open a .npy file or directory to begin"

    private struct WindowLevelState {
        let window: Float
        let level: Float
    }

    private let metalView = ImageMetalView(frame: .zero, device: nil)
    private let emptyStateView = CanvasEmptyStateView()
    private let emptyStateLabel = NSTextField(labelWithString: ViewerViewController.emptyStatePrompt)
    private let emptyStateButton = NSButton(title: "Open File or Directory...", target: nil, action: nil)
    private let fileNavigatorContainer = NSView()
    private let fileNavigatorTable = FileNavigatorTableView()
    private let fileNavigatorScrollView = NSScrollView()
    private let fileNavigatorDivider = NSView()
    private let modePopUp = NSPopUpButton(frame: .zero, pullsDown: false)
    private let colorMapPopUp = NSPopUpButton(frame: .zero, pullsDown: false)
    private let colorMapScaleView = ColorMapScaleView(frame: .zero)
    private let windowSlider = NSSlider(value: 1, minValue: 0.01, maxValue: 1, target: nil, action: nil)
    private let levelSlider = NSSlider(value: 0.5, minValue: 0, maxValue: 1, target: nil, action: nil)
    private let windowValueLabel = NSTextField(labelWithString: "1.00")
    private let levelValueLabel = NSTextField(labelWithString: "0.50")
    private let resetWindowLevelButton = NSButton(title: "Reset W/L", target: nil, action: nil)
    private let exportPNGButton = NSButton(title: "Export PNG...", target: nil, action: nil)
    private let homeButton = NSButton(frame: .zero)
    private let reloadFilesButton = NSButton(title: "Reload Files", target: nil, action: nil)
    private let preserveViewportButton = NSButton(checkboxWithTitle: "Preserve View", target: nil, action: nil)
    private let fileLabel = NSTextField(labelWithString: "No file")
    private let shapeLabel = NSTextField(labelWithString: "shape -")
    private let dtypeLabel = NSTextField(labelWithString: "dtype -")
    private let cursorLabel = NSTextField(labelWithString: "x -  y -")
    private let fileNavigatorWidth: CGFloat = 240
    private let sidebarWidth: CGFloat = 248
    private let fileLoadQueue = DispatchQueue(label: "com.parasight.NPYViewer.file-load", qos: .userInitiated)
    private let pngExportQueue = DispatchQueue(label: "com.parasight.NPYViewer.png-export", qos: .userInitiated)
    private var renderer: MetalRenderer?
    private var sessionDirectoryURL: URL?
    private var sessionItems: [ViewerItem] = []
    private var selectedSessionIndex: Int?
    private var displayedURL: URL?
    private var windowLevelByURL: [URL: WindowLevelState] = [:]
    private var displayModeByURL: [URL: DisplayMode] = [:]
    private var hoverText: String?
    private var openRequestID = 0
    private var fileNavigatorWidthConstraint: NSLayoutConstraint?
    private var fileNavigatorDividerWidthConstraint: NSLayoutConstraint?
    private var isSynchronizingNavigatorSelection = false
    private var isExportingPNG = false
    private var keyDownMonitor: Any?

    var onTitleChanged: ((String) -> Void)?

    override func loadView() {
        view = NSView()
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.black.cgColor

        fileNavigatorContainer.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(fileNavigatorContainer)
        configureFileNavigator()

        fileNavigatorDivider.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(fileNavigatorDivider)
        configureFileNavigatorDivider()

        metalView.translatesAutoresizingMaskIntoConstraints = false
        metalView.interactionDelegate = self
        view.addSubview(metalView)

        emptyStateView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(emptyStateView)
        configureEmptyState()

        let sidebar = makeSidebar()
        sidebar.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(sidebar)

        let divider = makeDivider()
        divider.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(divider)

        let fileNavigatorWidthConstraint = fileNavigatorContainer.widthAnchor.constraint(equalToConstant: 0)
        let fileNavigatorDividerWidthConstraint = fileNavigatorDivider.widthAnchor.constraint(equalToConstant: 0)
        self.fileNavigatorWidthConstraint = fileNavigatorWidthConstraint
        self.fileNavigatorDividerWidthConstraint = fileNavigatorDividerWidthConstraint

        NSLayoutConstraint.activate([
            fileNavigatorContainer.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            fileNavigatorContainer.topAnchor.constraint(equalTo: view.topAnchor),
            fileNavigatorContainer.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            fileNavigatorWidthConstraint,

            fileNavigatorDivider.leadingAnchor.constraint(equalTo: fileNavigatorContainer.trailingAnchor),
            fileNavigatorDivider.topAnchor.constraint(equalTo: view.topAnchor),
            fileNavigatorDivider.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            fileNavigatorDividerWidthConstraint,

            metalView.leadingAnchor.constraint(equalTo: fileNavigatorDivider.trailingAnchor),
            metalView.trailingAnchor.constraint(equalTo: divider.leadingAnchor),
            metalView.topAnchor.constraint(equalTo: view.topAnchor),
            metalView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            emptyStateView.leadingAnchor.constraint(equalTo: metalView.leadingAnchor),
            emptyStateView.trailingAnchor.constraint(equalTo: metalView.trailingAnchor),
            emptyStateView.topAnchor.constraint(equalTo: metalView.topAnchor),
            emptyStateView.bottomAnchor.constraint(equalTo: metalView.bottomAnchor),

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

    override func viewDidAppear() {
        super.viewDidAppear()
        installKeyDownMonitor()

        if view.window?.firstResponder == nil {
            view.window?.makeFirstResponder(metalView)
        }
    }

    deinit {
        if let keyDownMonitor {
            NSEvent.removeMonitor(keyDownMonitor)
        }
    }

    func openDocument() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = true
        panel.canChooseFiles = true
        if let npyType = UTType(filenameExtension: "npy") {
            panel.allowedContentTypes = [npyType]
        }

        guard panel.runModal() == .OK, let url = panel.url else {
            return
        }

        open(url: url)
    }

    func open(url: URL) {
        if NPYFileDiscovery.isDirectory(url) {
            openDirectory(url)
            return
        }

        guard NPYFileDiscovery.isNPYFile(url) else {
            showError(ViewerOpenError.unsupportedFile(url), title: "Could Not Open \(url.lastPathComponent)")
            return
        }

        openSession(directoryURL: nil, urls: [url], selectedIndex: 0)
    }

    private func openDirectory(_ url: URL) {
        do {
            let urls = try NPYFileDiscovery.npyFiles(in: url)
            guard !urls.isEmpty else {
                showError(ViewerOpenError.noNPYFiles(url), title: "Could Not Open \(url.lastPathComponent)")
                return
            }

            openSession(directoryURL: url, urls: urls, selectedIndex: 0)
        } catch {
            showError(error, title: "Could Not Open \(url.lastPathComponent)")
        }
    }

    private func openSession(
        directoryURL: URL?,
        urls: [URL],
        selectedIndex: Int,
        preservingViewSettings: Bool = false,
        preservingViewport: Bool = false
    ) {
        sessionDirectoryURL = directoryURL
        sessionItems = urls.map(ViewerItem.init(url:))
        selectedSessionIndex = nil
        displayedURL = nil
        if preservingViewSettings {
            let urls = Set(urls)
            windowLevelByURL = windowLevelByURL.filter { urls.contains($0.key) }
            displayModeByURL = displayModeByURL.filter { urls.contains($0.key) }
        } else {
            windowLevelByURL = [:]
            displayModeByURL = [:]
        }
        updateFileNavigator()
        selectSessionItem(at: selectedIndex, preservingCurrentViewport: preservingViewport)
    }

    func reloadSession() {
        saveCurrentWindowLevelState()
        saveCurrentDisplayModeState()

        if let sessionDirectoryURL {
            reloadDirectorySession(sessionDirectoryURL)
            return
        }

        guard let url = selectedURL ?? displayedURL ?? sessionItems.first?.url else {
            return
        }

        openSession(
            directoryURL: nil,
            urls: [url],
            selectedIndex: 0,
            preservingViewSettings: true,
            preservingViewport: true
        )
    }

    private func selectSessionItem(at index: Int, preservingCurrentViewport: Bool = false) {
        guard sessionItems.indices.contains(index) else {
            return
        }

        openRequestID &+= 1
        let requestID = openRequestID
        let shouldPreserveViewport = preservingCurrentViewport || shouldPreserveViewport(forSelectionAt: index)
        saveCurrentWindowLevelState()
        saveCurrentDisplayModeState()
        selectedSessionIndex = index
        displayedURL = nil
        hoverText = nil
        updateFileNavigatorSelection()

        let url = sessionItems[index].url
        emptyStateLabel.stringValue = "Opening \(url.lastPathComponent)..."
        emptyStateButton.isHidden = true
        fileLabel.stringValue = "Opening \(url.lastPathComponent)..."
        shapeLabel.stringValue = "shape -"
        dtypeLabel.stringValue = "dtype -"
        cursorLabel.stringValue = "x -  y -"
        updateExportControls()

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
                    self.finishOpen(array: array, url: url, preservingViewport: shouldPreserveViewport)
                case .failure(let error):
                    self.renderer?.clearArray()
                    self.displayedURL = nil
                    self.onTitleChanged?(self.title(for: url))
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
        refreshHoverFromCurrentMouseLocation()
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

        setHoverText(ViewerFormatting.hoverText(array: array, coordinate: coordinate, value: value))
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

    func numberOfRows(in tableView: NSTableView) -> Int {
        sessionItems.count
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard sessionItems.indices.contains(row) else {
            return nil
        }

        let identifier = NSUserInterfaceItemIdentifier("FileNavigatorCell")
        let label: NSTextField
        if let reusedLabel = tableView.makeView(withIdentifier: identifier, owner: self) as? NSTextField {
            label = reusedLabel
        } else {
            label = NSTextField(labelWithString: "")
            label.identifier = identifier
            label.font = .systemFont(ofSize: 13)
            label.lineBreakMode = .byTruncatingMiddle
            label.maximumNumberOfLines = 1
            label.textColor = NSColor(white: 0.86, alpha: 1)
        }

        label.stringValue = sessionItems[row].url.lastPathComponent
        return label
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        guard !isSynchronizingNavigatorSelection else {
            return
        }

        let row = fileNavigatorTable.selectedRow
        guard row >= 0 else {
            return
        }

        selectSessionItem(at: row)
    }

    @objc private func modeChanged(_ sender: NSPopUpButton) {
        guard let mode = DisplayMode(rawValue: UInt32(sender.selectedTag())) else {
            return
        }

        renderer?.setDisplayMode(mode)
        saveCurrentDisplayModeState()
        updateInspector()
    }

    @objc private func colorMapChanged(_ sender: NSPopUpButton) {
        guard let colorMap = ColorMap(rawValue: UInt32(sender.selectedTag())) else {
            return
        }

        renderer?.setColorMap(colorMap)
        updateInspector()
    }

    @objc private func windowLevelChanged(_ sender: NSSlider) {
        renderer?.setWindowLevel(
            window: Float(windowSlider.doubleValue),
            level: Float(levelSlider.doubleValue)
        )
        saveCurrentWindowLevelState()
        updateWindowLevelControls()
        updateColorMapScaleView()
    }

    @objc private func resetWindowLevelButtonPressed(_ sender: NSButton) {
        renderer?.resetWindowLevel()
        saveCurrentWindowLevelState()
        updateInspector()
    }

    @objc private func homeButtonPressed(_ sender: NSButton) {
        resetZoom()
    }

    @objc private func reloadFilesButtonPressed(_ sender: NSButton) {
        reloadSession()
    }

    @objc private func exportPNGButtonPressed(_ sender: NSButton) {
        guard let renderer, let sourceURL = displayedURL else {
            return
        }

        let snapshot: MetalRenderer.PNGExportSnapshot
        do {
            snapshot = try renderer.makePNGExportSnapshot()
        } catch {
            showError(error, title: "Could Not Export PNG")
            return
        }

        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        panel.canCreateDirectories = true
        panel.directoryURL = sourceURL.deletingLastPathComponent()
        panel.nameFieldStringValue = sourceURL.deletingPathExtension().lastPathComponent + ".png"
        panel.prompt = "Export"
        panel.title = "Export PNG"

        guard panel.runModal() == .OK, let destinationURL = panel.url else {
            return
        }

        setPNGExportInProgress(true)
        pngExportQueue.async { [weak self, renderer] in
            let result = Result {
                try renderer.writePNG(from: snapshot, to: destinationURL)
            }

            DispatchQueue.main.async { [weak self] in
                self?.setPNGExportInProgress(false)
                if case .failure(let error) = result {
                    self?.showError(error, title: "Could Not Export PNG")
                }
            }
        }
    }

    @objc private func emptyStateOpenButtonPressed(_ sender: NSButton) {
        openDocument()
    }

    private func installKeyDownMonitor() {
        guard keyDownMonitor == nil else {
            return
        }

        keyDownMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard self?.handleKeyDown(event) == true else {
                return event
            }

            return nil
        }
    }

    private func handleKeyDown(_ event: NSEvent) -> Bool {
        guard event.window === view.window else {
            return false
        }

        let navigationOffset: Int
        switch event.keyCode {
        case Self.upArrowKeyCode:
            navigationOffset = -1
        case Self.downArrowKeyCode:
            navigationOffset = 1
        default:
            return false
        }

        let ignoredModifiers: NSEvent.ModifierFlags = [.numericPad, .function, .capsLock]
        let activeModifiers = event.modifierFlags
            .intersection(.deviceIndependentFlagsMask)
            .subtracting(ignoredModifiers)
        guard activeModifiers.isEmpty else {
            return false
        }

        return navigateFileSelection(by: navigationOffset)
    }

    private func navigateFileSelection(by offset: Int) -> Bool {
        guard sessionItems.count > 1 else {
            return false
        }

        let previousFirstResponder = view.window?.firstResponder
        defer {
            restoreFirstResponderAfterFileNavigation(previousFirstResponder)
        }

        let currentIndex = selectedSessionIndex ?? fileNavigatorTable.selectedRow
        guard currentIndex >= 0 else {
            selectSessionItem(at: 0)
            return true
        }

        let nextIndex = min(max(currentIndex + offset, 0), sessionItems.count - 1)
        guard nextIndex != currentIndex else {
            return true
        }

        selectSessionItem(at: nextIndex)
        return true
    }

    private func restoreFirstResponderAfterFileNavigation(_ previousFirstResponder: NSResponder?) {
        guard let window = view.window, window.firstResponder === fileNavigatorTable else {
            return
        }

        if let previousFirstResponder, previousFirstResponder !== fileNavigatorTable {
            window.makeFirstResponder(previousFirstResponder)
        } else {
            window.makeFirstResponder(metalView)
        }
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
        configureWindowLevelControls()
        configureViewControls()
        configureExportControls()
        configureMetadataLabels()

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        sidebar.addSubview(stack)

        stack.addArrangedSubview(makeControlGroup(title: "Mode", control: modePopUp))
        stack.addArrangedSubview(makeColorMapGroup())
        stack.addArrangedSubview(makeWindowLevelGroup())
        stack.addArrangedSubview(makeExportGroup())
        stack.addArrangedSubview(makeViewGroup())
        stack.addArrangedSubview(makeSpacer(height: 10))
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

    private func configureEmptyState() {
        emptyStateView.wantsLayer = true
        emptyStateView.layer?.backgroundColor = NSColor.black.cgColor

        emptyStateLabel.font = .systemFont(ofSize: 15, weight: .medium)
        emptyStateLabel.textColor = NSColor(white: 0.74, alpha: 1)
        emptyStateLabel.alignment = .center

        emptyStateButton.target = self
        emptyStateButton.action = #selector(emptyStateOpenButtonPressed(_:))
        emptyStateButton.bezelStyle = .rounded
        emptyStateButton.controlSize = .regular
        emptyStateButton.font = .systemFont(ofSize: 13)

        let stack = NSStackView(views: [emptyStateLabel, emptyStateButton])
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        emptyStateView.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: emptyStateView.centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: emptyStateView.centerYAnchor)
        ])
    }

    private func configureFileNavigator() {
        fileNavigatorContainer.wantsLayer = true
        fileNavigatorContainer.appearance = NSAppearance(named: .darkAqua)
        fileNavigatorContainer.layer?.backgroundColor = NSColor(
            calibratedRed: 0.082,
            green: 0.086,
            blue: 0.094,
            alpha: 1
        ).cgColor
        fileNavigatorContainer.isHidden = true

        let titleLabel = makeSectionTitleLabel("Files")
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        fileNavigatorContainer.addSubview(titleLabel)

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("filename"))
        column.resizingMask = .autoresizingMask
        fileNavigatorTable.addTableColumn(column)
        fileNavigatorTable.headerView = nil
        fileNavigatorTable.rowHeight = 28
        fileNavigatorTable.intercellSpacing = NSSize(width: 0, height: 2)
        fileNavigatorTable.selectionHighlightStyle = .regular
        fileNavigatorTable.backgroundColor = .clear
        fileNavigatorTable.enclosingScrollView?.drawsBackground = false
        fileNavigatorTable.fallbackFirstResponder = metalView
        fileNavigatorTable.delegate = self
        fileNavigatorTable.dataSource = self

        fileNavigatorScrollView.translatesAutoresizingMaskIntoConstraints = false
        fileNavigatorScrollView.documentView = fileNavigatorTable
        fileNavigatorScrollView.hasVerticalScroller = true
        fileNavigatorScrollView.hasHorizontalScroller = false
        fileNavigatorScrollView.autohidesScrollers = true
        fileNavigatorScrollView.drawsBackground = false
        fileNavigatorContainer.addSubview(fileNavigatorScrollView)

        NSLayoutConstraint.activate([
            titleLabel.leadingAnchor.constraint(equalTo: fileNavigatorContainer.leadingAnchor, constant: 14),
            titleLabel.trailingAnchor.constraint(equalTo: fileNavigatorContainer.trailingAnchor, constant: -14),
            titleLabel.topAnchor.constraint(equalTo: fileNavigatorContainer.topAnchor, constant: 18),

            fileNavigatorScrollView.leadingAnchor.constraint(equalTo: fileNavigatorContainer.leadingAnchor, constant: 8),
            fileNavigatorScrollView.trailingAnchor.constraint(equalTo: fileNavigatorContainer.trailingAnchor, constant: -8),
            fileNavigatorScrollView.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 10),
            fileNavigatorScrollView.bottomAnchor.constraint(equalTo: fileNavigatorContainer.bottomAnchor, constant: -8)
        ])
    }

    private func configureFileNavigatorDivider() {
        fileNavigatorDivider.wantsLayer = true
        fileNavigatorDivider.layer?.backgroundColor = NSColor(
            calibratedRed: 0.19,
            green: 0.20,
            blue: 0.22,
            alpha: 1
        ).cgColor
        fileNavigatorDivider.isHidden = true
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

        colorMapScaleView.translatesAutoresizingMaskIntoConstraints = false
    }

    private func configureWindowLevelControls() {
        for slider in [windowSlider, levelSlider] {
            slider.target = self
            slider.action = #selector(windowLevelChanged(_:))
            slider.controlSize = .small
            slider.isContinuous = true
            slider.translatesAutoresizingMaskIntoConstraints = false
            slider.heightAnchor.constraint(equalToConstant: 18).isActive = true
        }

        for label in [windowValueLabel, levelValueLabel] {
            label.font = .monospacedDigitSystemFont(ofSize: 12, weight: .regular)
            label.textColor = NSColor(white: 0.76, alpha: 1)
            label.alignment = .right
        }

        resetWindowLevelButton.target = self
        resetWindowLevelButton.action = #selector(resetWindowLevelButtonPressed(_:))
        resetWindowLevelButton.bezelStyle = .rounded
        resetWindowLevelButton.controlSize = .small
        resetWindowLevelButton.font = .systemFont(ofSize: 12)
        resetWindowLevelButton.toolTip = "Reset window and level"
        resetWindowLevelButton.translatesAutoresizingMaskIntoConstraints = false
        resetWindowLevelButton.heightAnchor.constraint(equalToConstant: 24).isActive = true
    }

    private func configureViewControls() {
        preserveViewportButton.state = .on
        preserveViewportButton.controlSize = .small
        preserveViewportButton.font = .systemFont(ofSize: 13)
        preserveViewportButton.toolTip = "Keep zoom and center while switching files"
        preserveViewportButton.translatesAutoresizingMaskIntoConstraints = false
        preserveViewportButton.heightAnchor.constraint(equalToConstant: 22).isActive = true

        homeButton.title = "Reset View"
        homeButton.target = self
        homeButton.action = #selector(homeButtonPressed(_:))
        homeButton.bezelStyle = .rounded
        homeButton.controlSize = .regular
        homeButton.font = .systemFont(ofSize: 13)
        homeButton.image = nil
        homeButton.imagePosition = .noImage
        homeButton.toolTip = "Reset view"
        homeButton.translatesAutoresizingMaskIntoConstraints = false
        homeButton.heightAnchor.constraint(equalToConstant: 28).isActive = true

        reloadFilesButton.target = self
        reloadFilesButton.action = #selector(reloadFilesButtonPressed(_:))
        reloadFilesButton.bezelStyle = .rounded
        reloadFilesButton.controlSize = .regular
        reloadFilesButton.font = .systemFont(ofSize: 13)
        reloadFilesButton.toolTip = "Re-read the current file or directory from disk"
        reloadFilesButton.translatesAutoresizingMaskIntoConstraints = false
        reloadFilesButton.heightAnchor.constraint(equalToConstant: 28).isActive = true
    }

    private func configureExportControls() {
        exportPNGButton.target = self
        exportPNGButton.action = #selector(exportPNGButtonPressed(_:))
        exportPNGButton.bezelStyle = .rounded
        exportPNGButton.controlSize = .regular
        exportPNGButton.font = .systemFont(ofSize: 13)
        exportPNGButton.toolTip = "Export the selected image as a PNG using the current mode, colormap, window, and level"
        exportPNGButton.translatesAutoresizingMaskIntoConstraints = false
        exportPNGButton.heightAnchor.constraint(equalToConstant: 28).isActive = true
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
        cursorLabel.maximumNumberOfLines = 7
        cursorLabel.lineBreakMode = .byWordWrapping
        cursorLabel.textColor = NSColor(white: 0.82, alpha: 1)
    }

    private func makeControlGroup(title: String, control: NSControl) -> NSView {
        let titleLabel = makeSectionTitleLabel(title)

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

    private func makeColorMapGroup() -> NSView {
        let titleLabel = makeSectionTitleLabel("Colormap")

        colorMapPopUp.translatesAutoresizingMaskIntoConstraints = false
        colorMapPopUp.setContentHuggingPriority(.defaultLow, for: .horizontal)
        colorMapPopUp.heightAnchor.constraint(equalToConstant: 28).isActive = true
        colorMapScaleView.heightAnchor.constraint(equalToConstant: ColorMapScaleView.preferredHeight).isActive = true

        let group = NSStackView(views: [titleLabel, colorMapPopUp, colorMapScaleView])
        group.orientation = .vertical
        group.alignment = .leading
        group.spacing = 5
        group.distribution = .fill

        NSLayoutConstraint.activate([
            titleLabel.widthAnchor.constraint(equalTo: group.widthAnchor),
            colorMapPopUp.widthAnchor.constraint(equalTo: group.widthAnchor),
            colorMapScaleView.widthAnchor.constraint(equalTo: group.widthAnchor)
        ])

        return group
    }

    private func makeWindowLevelGroup() -> NSView {
        let titleLabel = makeSectionTitleLabel("Window / Level")
        let windowRow = makeSliderRow(title: "Window", valueLabel: windowValueLabel)
        let levelRow = makeSliderRow(title: "Level", valueLabel: levelValueLabel)

        let group = NSStackView(views: [
            titleLabel,
            windowRow,
            windowSlider,
            levelRow,
            levelSlider,
            resetWindowLevelButton
        ])
        group.orientation = .vertical
        group.alignment = .leading
        group.spacing = 5
        group.distribution = .fill

        NSLayoutConstraint.activate([
            titleLabel.widthAnchor.constraint(equalTo: group.widthAnchor),
            windowRow.widthAnchor.constraint(equalTo: group.widthAnchor),
            windowSlider.widthAnchor.constraint(equalTo: group.widthAnchor),
            levelRow.widthAnchor.constraint(equalTo: group.widthAnchor),
            levelSlider.widthAnchor.constraint(equalTo: group.widthAnchor),
            resetWindowLevelButton.widthAnchor.constraint(equalTo: group.widthAnchor)
        ])

        return group
    }

    private func makeExportGroup() -> NSView {
        let titleLabel = makeSectionTitleLabel("Export")

        let group = NSStackView(views: [
            titleLabel,
            exportPNGButton
        ])
        group.orientation = .vertical
        group.alignment = .leading
        group.spacing = 6
        group.distribution = .fill

        NSLayoutConstraint.activate([
            titleLabel.widthAnchor.constraint(equalTo: group.widthAnchor),
            exportPNGButton.widthAnchor.constraint(equalTo: group.widthAnchor)
        ])

        return group
    }

    private func makeViewGroup() -> NSView {
        let titleLabel = makeSectionTitleLabel("View")

        let group = NSStackView(views: [
            titleLabel,
            preserveViewportButton,
            reloadFilesButton,
            homeButton
        ])
        group.orientation = .vertical
        group.alignment = .leading
        group.spacing = 6
        group.distribution = .fill

        NSLayoutConstraint.activate([
            titleLabel.widthAnchor.constraint(equalTo: group.widthAnchor),
            preserveViewportButton.widthAnchor.constraint(equalTo: group.widthAnchor),
            reloadFilesButton.widthAnchor.constraint(equalTo: group.widthAnchor),
            homeButton.widthAnchor.constraint(equalTo: group.widthAnchor)
        ])

        return group
    }

    private func makeSliderRow(title: String, valueLabel: NSTextField) -> NSView {
        let titleLabel = NSTextField(labelWithString: title)
        titleLabel.font = .systemFont(ofSize: 12, weight: .regular)
        titleLabel.textColor = NSColor(white: 0.70, alpha: 1)

        let row = NSStackView(views: [titleLabel, valueLabel])
        row.orientation = .horizontal
        row.alignment = .firstBaseline
        row.spacing = 8
        row.distribution = .fill

        titleLabel.setContentHuggingPriority(.defaultLow, for: .horizontal)
        valueLabel.setContentHuggingPriority(.required, for: .horizontal)

        return row
    }

    private func makeSectionTitleLabel(_ title: String) -> NSTextField {
        let titleLabel = NSTextField(labelWithString: title.uppercased())
        titleLabel.font = .systemFont(ofSize: 10, weight: .medium)
        titleLabel.textColor = NSColor(white: 0.54, alpha: 1)
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        return titleLabel
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
        updateWindowLevelControls()
        updateColorMapScaleView()
        updateExportControls()
        updateReloadControls()

        guard let array = renderer?.array else {
            emptyStateView.isHidden = false
            if emptyStateButton.isHidden {
                emptyStateLabel.stringValue = Self.emptyStatePrompt
                emptyStateButton.isHidden = false
            }
            fileLabel.stringValue = "No file"
            shapeLabel.stringValue = "shape -"
            dtypeLabel.stringValue = "dtype -"
            cursorLabel.stringValue = "x -  y -"
            homeButton.isEnabled = false
            return
        }

        emptyStateView.isHidden = true
        homeButton.isEnabled = true
        let file = selectedURL?.lastPathComponent ?? array.url.lastPathComponent
        fileLabel.stringValue = file
        shapeLabel.stringValue = "shape \(array.height)x\(array.width)"
        dtypeLabel.stringValue = "dtype \(array.elementType.dtypeName)"
        updateCursorText()
    }

    private func updateModePopUp() {
        let array = renderer?.array
        let modes: [DisplayMode]
        if array?.elementType == .complex64 {
            modes = [.complexAbs, .complexIntensity, .complexPhase, .complexReal, .complexImag]
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

    private func updateColorMapScaleView() {
        colorMapScaleView.setState(
            colorMap: renderer?.colorMap ?? .gray,
            displayMode: renderer?.displayMode ?? .scalar,
            window: renderer?.window ?? 1,
            level: renderer?.level ?? 0.5,
            isScaleEnabled: renderer?.array != nil
        )
    }

    private func updateWindowLevelControls() {
        let hasImage = renderer?.array != nil
        let window = renderer?.window ?? 1
        let level = renderer?.level ?? 0.5

        windowSlider.doubleValue = Double(window)
        levelSlider.doubleValue = Double(level)
        windowValueLabel.stringValue = ViewerFormatting.controlValue(window)
        levelValueLabel.stringValue = ViewerFormatting.controlValue(level)

        windowSlider.isEnabled = hasImage
        levelSlider.isEnabled = hasImage
        resetWindowLevelButton.isEnabled = hasImage
    }

    private func updateExportControls() {
        exportPNGButton.isEnabled = renderer?.array != nil && displayedURL != nil && !isExportingPNG
        exportPNGButton.title = isExportingPNG ? "Exporting..." : "Export PNG..."
    }

    private func updateReloadControls() {
        reloadFilesButton.isEnabled = sessionDirectoryURL != nil || !sessionItems.isEmpty || displayedURL != nil
    }

    private func updateCursorText() {
        guard let array = renderer?.array else {
            cursorLabel.stringValue = "x -  y -"
            return
        }

        cursorLabel.stringValue = hoverText ?? ViewerFormatting.placeholderHoverText(for: array)
    }

    private func refreshHoverFromCurrentMouseLocation() {
        guard let point = metalView.currentTopLeftMousePointIfInside() else {
            setHoverText(nil)
            return
        }

        imageMetalView(metalView, didHoverAt: point)
    }

    private func setHoverText(_ text: String?) {
        guard hoverText != text else {
            return
        }

        hoverText = text
        updateCursorText()
    }

    private func setPNGExportInProgress(_ isExporting: Bool) {
        isExportingPNG = isExporting
        updateExportControls()
    }

    private func finishOpen(array: NPYArray, url: URL, preservingViewport: Bool) {
        let previousHoverText = hoverText
        let viewportState = preservingViewport && preserveViewportButton.state == .on ? renderer?.viewportState() : nil
        let windowLevelState = windowLevelByURL[url]
        let displayModeState = displayModeByURL[url]
        hoverText = nil

        do {
            try renderer?.setArray(
                array,
                preserving: viewportState,
                windowLevel: windowLevelState.map { (window: $0.window, level: $0.level) },
                displayMode: displayModeState
            )
            displayedURL = url
            onTitleChanged?(title(for: url))
            updateInspector()
            refreshHoverFromCurrentMouseLocation()
        } catch {
            hoverText = previousHoverText
            renderer?.clearArray()
            displayedURL = nil
            onTitleChanged?(title(for: url))
            showError(error, title: "Could Not Open \(url.lastPathComponent)")
            updateInspector()
        }
    }

    private func shouldPreserveViewport(forSelectionAt index: Int) -> Bool {
        preserveViewportButton.state == .on &&
            sessionItems.count > 1 &&
            selectedSessionIndex != nil &&
            selectedSessionIndex != index
    }

    private func reloadDirectorySession(_ directoryURL: URL) {
        let previousSelectedURL = selectedURL ?? displayedURL
        let previousSelectedIndex = selectedSessionIndex

        do {
            let urls = try NPYFileDiscovery.npyFiles(in: directoryURL)
            guard !urls.isEmpty else {
                clearSession(
                    directoryURL: directoryURL,
                    emptyStateMessage: "No .npy files found in \(directoryURL.lastPathComponent)."
                )
                return
            }

            let selectedIndex = reloadedSelectionIndex(
                in: urls,
                preferredURL: previousSelectedURL,
                previousIndex: previousSelectedIndex
            )
            openSession(
                directoryURL: directoryURL,
                urls: urls,
                selectedIndex: selectedIndex,
                preservingViewSettings: true,
                preservingViewport: true
            )
        } catch {
            showError(error, title: "Could Not Reload \(directoryURL.lastPathComponent)")
        }
    }

    private func clearSession(directoryURL: URL?, emptyStateMessage: String) {
        openRequestID &+= 1
        sessionDirectoryURL = directoryURL
        sessionItems = []
        selectedSessionIndex = nil
        displayedURL = nil
        hoverText = nil
        windowLevelByURL = [:]
        displayModeByURL = [:]
        renderer?.clearArray()
        onTitleChanged?(directoryURL?.lastPathComponent ?? "NPYViewer")
        updateFileNavigator()
        emptyStateLabel.stringValue = emptyStateMessage
        emptyStateButton.isHidden = false
        updateInspector()
    }

    private func reloadedSelectionIndex(in urls: [URL], preferredURL: URL?, previousIndex: Int?) -> Int {
        if let preferredURL, let index = urls.firstIndex(of: preferredURL) {
            return index
        }

        if let previousIndex {
            return min(max(previousIndex, 0), urls.count - 1)
        }

        return 0
    }

    private func saveCurrentWindowLevelState() {
        guard let url = displayedURL, let renderer, renderer.array != nil else {
            return
        }

        windowLevelByURL[url] = WindowLevelState(window: renderer.window, level: renderer.level)
    }

    private func saveCurrentDisplayModeState() {
        guard let url = displayedURL, let renderer, renderer.array != nil else {
            return
        }

        displayModeByURL[url] = renderer.displayMode
    }

    private var selectedURL: URL? {
        guard let selectedSessionIndex, sessionItems.indices.contains(selectedSessionIndex) else {
            return nil
        }

        return sessionItems[selectedSessionIndex].url
    }

    private func title(for url: URL) -> String {
        guard let sessionDirectoryURL else {
            return url.lastPathComponent
        }

        return "\(sessionDirectoryURL.lastPathComponent) - \(url.lastPathComponent)"
    }

    private func updateFileNavigator() {
        fileNavigatorTable.reloadData()
        let shouldShowNavigator = sessionItems.count > 1
        fileNavigatorWidthConstraint?.constant = shouldShowNavigator ? fileNavigatorWidth : 0
        fileNavigatorDividerWidthConstraint?.constant = shouldShowNavigator ? 1 : 0
        fileNavigatorContainer.isHidden = !shouldShowNavigator
        fileNavigatorDivider.isHidden = !shouldShowNavigator
        updateFileNavigatorSelection()
    }

    private func updateFileNavigatorSelection() {
        isSynchronizingNavigatorSelection = true
        defer { isSynchronizingNavigatorSelection = false }

        guard let selectedSessionIndex, sessionItems.indices.contains(selectedSessionIndex) else {
            fileNavigatorTable.deselectAll(nil)
            return
        }

        fileNavigatorTable.selectRowIndexes(IndexSet(integer: selectedSessionIndex), byExtendingSelection: false)
        fileNavigatorTable.scrollRowToVisible(selectedSessionIndex)
    }

    private func showError(_ error: Error, title: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        alert.alertStyle = .warning
        alert.runModal()
    }

    private static let upArrowKeyCode: UInt16 = 126
    private static let downArrowKeyCode: UInt16 = 125
}
