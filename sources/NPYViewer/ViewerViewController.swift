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

final class ViewerViewController: NSViewController, ImageMetalViewDelegate {
    private static let emptyStatePrompt = "Open a .npy file or directory to begin"
    private static let upArrowKeyCode: UInt16 = 126
    private static let downArrowKeyCode: UInt16 = 125

    private let metalView = ImageMetalView(frame: .zero, device: nil)
    private let emptyStateView = CanvasEmptyStateView()
    private let emptyStateLabel = NSTextField(labelWithString: ViewerViewController.emptyStatePrompt)
    private let emptyStateButton = NSButton(title: "Open File or Directory...", target: nil, action: nil)
    private let inspectorViewController = InspectorViewController()
    private let sessionCoordinator = ViewerSessionCoordinator()
    private let pngExportCoordinator = PNGExportCoordinator()
    private let sidebarWidth: CGFloat = 248

    private lazy var fileNavigatorController = FileNavigatorController(fallbackFirstResponder: metalView)
    private var renderer: MetalRenderer?
    private var hoverText: String?
    private var keyDownMonitor: Any?
    private var didConfigureCallbacks = false

    var onTitleChanged: ((String) -> Void)?

    override func loadView() {
        view = NSView()
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.black.cgColor

        let navigatorView = fileNavigatorController.view
        navigatorView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(navigatorView)

        let navigatorDivider = fileNavigatorController.dividerView
        navigatorDivider.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(navigatorDivider)

        metalView.translatesAutoresizingMaskIntoConstraints = false
        metalView.interactionDelegate = self
        view.addSubview(metalView)

        emptyStateView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(emptyStateView)
        configureEmptyState()

        addChild(inspectorViewController)
        let sidebar = inspectorViewController.view
        sidebar.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(sidebar)

        let divider = makeDivider()
        divider.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(divider)

        let fileNavigatorWidthConstraint = navigatorView.widthAnchor.constraint(equalToConstant: 0)
        let fileNavigatorDividerWidthConstraint = navigatorDivider.widthAnchor.constraint(equalToConstant: 0)
        fileNavigatorController.setWidthConstraints(
            fileNavigatorWidthConstraint,
            dividerWidthConstraint: fileNavigatorDividerWidthConstraint
        )

        NSLayoutConstraint.activate([
            navigatorView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            navigatorView.topAnchor.constraint(equalTo: view.topAnchor),
            navigatorView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            fileNavigatorWidthConstraint,

            navigatorDivider.leadingAnchor.constraint(equalTo: navigatorView.trailingAnchor),
            navigatorDivider.topAnchor.constraint(equalTo: view.topAnchor),
            navigatorDivider.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            fileNavigatorDividerWidthConstraint,

            metalView.leadingAnchor.constraint(equalTo: navigatorDivider.trailingAnchor),
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

        configureCallbacks()
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
        do {
            try sessionCoordinator.open(url: url, currentState: currentSessionState())
        } catch {
            showError(error, title: "Could Not Open \(url.lastPathComponent)")
        }
    }

    func reloadSession() {
        do {
            try sessionCoordinator.reload(currentState: currentSessionState())
        } catch {
            let title = sessionCoordinator.directoryURL?.lastPathComponent ?? "Session"
            showError(error, title: "Could Not Reload \(title)")
        }
    }

    func resetZoom() {
        renderer?.resetView()
        renderer?.requestDraw()
        updateInspector()
        refreshHoverFromCurrentMouseLocation()
    }

    func numberOfRows(in tableView: NSTableView) -> Int {
        fileNavigatorController.numberOfRows(in: tableView)
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        fileNavigatorController.tableView(tableView, viewFor: tableColumn, row: row)
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

    private func configureCallbacks() {
        guard !didConfigureCallbacks else {
            return
        }
        didConfigureCallbacks = true

        fileNavigatorController.onSelectionChanged = { [weak self] row in
            guard let self else {
                return
            }
            self.sessionCoordinator.selectItem(at: row, currentState: self.currentSessionState())
        }

        inspectorViewController.onModeChanged = { [weak self] mode in
            self?.renderer?.setDisplayMode(mode)
            self?.updateInspector()
        }
        inspectorViewController.onColorMapChanged = { [weak self] colorMap in
            self?.renderer?.setColorMap(colorMap)
            self?.updateInspector()
        }
        inspectorViewController.onWindowLevelChanged = { [weak self] window, level in
            self?.renderer?.setWindowLevel(window: window, level: level)
            self?.updateInspector()
        }
        inspectorViewController.onResetWindowLevel = { [weak self] in
            self?.renderer?.resetWindowLevel()
            self?.updateInspector()
        }
        inspectorViewController.onResetView = { [weak self] in
            self?.resetZoom()
        }
        inspectorViewController.onReload = { [weak self] in
            self?.reloadSession()
        }
        inspectorViewController.onExportPNG = { [weak self] in
            self?.exportPNG()
        }

        sessionCoordinator.onItemsChanged = { [weak self] in
            self?.updateFileNavigator()
            self?.updateInspector()
        }
        sessionCoordinator.onSelectionStarted = { [weak self] url in
            self?.showOpeningState(for: url)
        }
        sessionCoordinator.onLoadCompleted = { [weak self] result in
            self?.handleLoadResult(result)
        }
        sessionCoordinator.onSessionCleared = { [weak self] directoryURL, message in
            self?.clearDisplayedSession(directoryURL: directoryURL, message: message)
        }

        pngExportCoordinator.onExportingChanged = { [weak self] _ in
            self?.updateInspector()
        }
        pngExportCoordinator.onError = { [weak self] error in
            self?.showError(error, title: "Could Not Export PNG")
        }
    }

    private func exportPNG() {
        guard let renderer, let sourceURL = sessionCoordinator.displayedURL else {
            return
        }

        pngExportCoordinator.export(renderer: renderer, sourceURL: sourceURL)
    }

    private func handleLoadResult(_ result: ViewerSessionLoadResult) {
        switch result {
        case .success(let array, let context):
            finishOpen(array: array, context: context)
        case .failure(let error, let context):
            renderer?.clearArray()
            sessionCoordinator.markDisplayed(nil)
            onTitleChanged?(sessionCoordinator.title(for: context.url))
            showError(error, title: "Could Not Open \(context.url.lastPathComponent)")
            updateInspector()
        }
    }

    private func finishOpen(array: NPYArray, context: ViewerSessionLoadContext) {
        guard let renderer else {
            return
        }

        let previousHoverText = hoverText
        let viewportState = context.shouldPreserveViewport && inspectorViewController.preserveViewportEnabled
            ? renderer.viewportState()
            : nil
        hoverText = nil

        do {
            try renderer.setArray(
                array,
                preserving: viewportState,
                windowLevel: context.windowLevelState.map { (window: $0.window, level: $0.level) },
                displayMode: context.displayModeState
            )
            sessionCoordinator.markDisplayed(context.url)
            onTitleChanged?(sessionCoordinator.title(for: context.url))
            updateInspector()
            refreshHoverFromCurrentMouseLocation()
        } catch {
            hoverText = previousHoverText
            renderer.clearArray()
            sessionCoordinator.markDisplayed(nil)
            onTitleChanged?(sessionCoordinator.title(for: context.url))
            showError(error, title: "Could Not Open \(context.url.lastPathComponent)")
            updateInspector()
        }
    }

    private func clearDisplayedSession(directoryURL: URL?, message: String) {
        hoverText = nil
        renderer?.clearArray()
        onTitleChanged?(directoryURL?.lastPathComponent ?? "NPYViewer")
        emptyStateLabel.stringValue = message
        emptyStateButton.isHidden = false
        updateInspector()
    }

    private func showOpeningState(for url: URL) {
        hoverText = nil
        emptyStateLabel.stringValue = "Opening \(url.lastPathComponent)..."
        emptyStateButton.isHidden = true
        inspectorViewController.showOpening(fileName: url.lastPathComponent)
    }

    private func updateFileNavigator() {
        fileNavigatorController.setURLs(sessionCoordinator.itemURLs)
        fileNavigatorController.selectRow(sessionCoordinator.selectedIndex)
    }

    private func updateInspector() {
        let array = renderer?.array
        if array == nil {
            emptyStateView.isHidden = false
            if emptyStateButton.isHidden {
                emptyStateLabel.stringValue = Self.emptyStatePrompt
                emptyStateButton.isHidden = false
            }
        } else {
            emptyStateView.isHidden = true
        }

        inspectorViewController.update(
            InspectorViewState(
                array: array,
                fileName: sessionCoordinator.selectedURL?.lastPathComponent ?? array?.url.lastPathComponent,
                displayMode: renderer?.displayMode ?? .scalar,
                colorMap: renderer?.colorMap ?? .gray,
                window: renderer?.window ?? 1,
                level: renderer?.level ?? 0.5,
                hoverText: hoverText,
                canExport: array != nil && sessionCoordinator.displayedURL != nil,
                isExportingPNG: pngExportCoordinator.isExporting,
                canReload: sessionCoordinator.canReload
            )
        )
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
        updateInspector()
    }

    private func currentSessionState() -> ViewerSessionCurrentState {
        ViewerSessionCurrentState(
            hasImage: renderer?.array != nil,
            window: renderer?.window ?? 1,
            level: renderer?.level ?? 0.5,
            displayMode: renderer?.displayMode ?? .scalar,
            preserveViewportEnabled: inspectorViewController.preserveViewportEnabled
        )
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

    private func showError(_ error: Error, title: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        alert.alertStyle = .warning
        alert.runModal()
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
        guard sessionCoordinator.items.count > 1 else {
            return false
        }

        let previousFirstResponder = view.window?.firstResponder
        defer {
            fileNavigatorController.restoreFirstResponderAfterNavigation(
                in: view.window,
                previousFirstResponder: previousFirstResponder,
                fallbackFirstResponder: metalView
            )
        }

        let currentIndex = sessionCoordinator.selectedIndex ?? fileNavigatorController.selectedRow
        guard currentIndex >= 0 else {
            sessionCoordinator.selectItem(at: 0, currentState: currentSessionState())
            return true
        }

        let nextIndex = min(max(currentIndex + offset, 0), sessionCoordinator.items.count - 1)
        guard nextIndex != currentIndex else {
            return true
        }

        sessionCoordinator.selectItem(at: nextIndex, currentState: currentSessionState())
        return true
    }
}

private extension ViewerSessionCurrentState {
    static let empty = ViewerSessionCurrentState(
        hasImage: false,
        window: 1,
        level: 0.5,
        displayMode: .scalar,
        preserveViewportEnabled: true
    )
}
