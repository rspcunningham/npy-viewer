import AppKit
import NPYCore
import NPYViewerSupport

struct InspectorViewState {
    let array: NPYArray?
    let fileName: String?
    let displayMode: DisplayMode
    let colorMap: ColorMap
    let window: Float
    let level: Float
    let hoverText: String?
    let canExport: Bool
    let isExportingPNG: Bool
    let canReload: Bool
}

final class InspectorViewController: NSViewController {
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

    var onModeChanged: ((DisplayMode) -> Void)?
    var onColorMapChanged: ((ColorMap) -> Void)?
    var onWindowLevelChanged: ((Float, Float) -> Void)?
    var onResetWindowLevel: (() -> Void)?
    var onResetView: (() -> Void)?
    var onReload: (() -> Void)?
    var onExportPNG: (() -> Void)?

    var preserveViewportEnabled: Bool {
        preserveViewportButton.state == .on
    }

    override func loadView() {
        let sidebar = NSView()
        sidebar.wantsLayer = true
        sidebar.appearance = NSAppearance(named: .darkAqua)
        sidebar.layer?.backgroundColor = NSColor(
            calibratedRed: 0.105,
            green: 0.108,
            blue: 0.116,
            alpha: 1
        ).cgColor
        view = sidebar

        configurePopUps()
        configureWindowLevelControls()
        configureViewControls()
        configureExportControls()
        configureMetadataLabels()
        installStack(in: sidebar)
    }

    func showOpening(fileName: String) {
        fileLabel.stringValue = "Opening \(fileName)..."
        shapeLabel.stringValue = "shape -"
        dtypeLabel.stringValue = "dtype -"
        cursorLabel.stringValue = "x -  y -"
        updateExportControls(canExport: false, isExportingPNG: false)
    }

    func update(_ state: InspectorViewState) {
        updateModePopUp(array: state.array, selectedMode: state.displayMode)
        updateColorMapPopUp(selectedColorMap: state.colorMap, hasImage: state.array != nil)
        updateWindowLevelControls(
            window: state.window,
            level: state.level,
            hasImage: state.array != nil
        )
        updateColorMapScaleView(
            colorMap: state.colorMap,
            displayMode: state.displayMode,
            window: state.window,
            level: state.level,
            hasImage: state.array != nil
        )
        updateExportControls(canExport: state.canExport, isExportingPNG: state.isExportingPNG)
        reloadFilesButton.isEnabled = state.canReload

        guard let array = state.array else {
            fileLabel.stringValue = "No file"
            shapeLabel.stringValue = "shape -"
            dtypeLabel.stringValue = "dtype -"
            cursorLabel.stringValue = "x -  y -"
            homeButton.isEnabled = false
            return
        }

        homeButton.isEnabled = true
        fileLabel.stringValue = state.fileName ?? array.url.lastPathComponent
        shapeLabel.stringValue = "shape \(array.shape.map(String.init).joined(separator: "x"))"
        dtypeLabel.stringValue = "dtype \(array.elementType.dtypeName)"
        cursorLabel.stringValue = state.hoverText ?? ViewerFormatting.placeholderHoverText(for: array)
    }

    private func installStack(in sidebar: NSView) {
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

    private func updateModePopUp(array: NPYArray?, selectedMode: DisplayMode) {
        let modes: [DisplayMode]
        if array?.elementType.isComplex == true {
            modes = [.complexAbs, .complexIntensity, .complexPhase, .complexReal, .complexImag]
        } else {
            modes = [.scalar]
        }

        modePopUp.removeAllItems()
        for mode in modes {
            modePopUp.addItem(withTitle: mode.menuLabel)
            modePopUp.lastItem?.tag = Int(mode.rawValue)
        }

        modePopUp.selectItem(withTag: Int(selectedMode.rawValue))
        modePopUp.isEnabled = array != nil && modes.count > 1
    }

    private func updateColorMapPopUp(selectedColorMap: ColorMap, hasImage: Bool) {
        colorMapPopUp.selectItem(withTag: Int(selectedColorMap.rawValue))
        colorMapPopUp.isEnabled = hasImage
    }

    private func updateWindowLevelControls(window: Float, level: Float, hasImage: Bool) {
        windowSlider.doubleValue = Double(window)
        levelSlider.doubleValue = Double(level)
        windowValueLabel.stringValue = ViewerFormatting.controlValue(window)
        levelValueLabel.stringValue = ViewerFormatting.controlValue(level)

        windowSlider.isEnabled = hasImage
        levelSlider.isEnabled = hasImage
        resetWindowLevelButton.isEnabled = hasImage
    }

    private func updateColorMapScaleView(
        colorMap: ColorMap,
        displayMode: DisplayMode,
        window: Float,
        level: Float,
        hasImage: Bool
    ) {
        colorMapScaleView.setState(
            colorMap: colorMap,
            displayMode: displayMode,
            window: window,
            level: level,
            isScaleEnabled: hasImage
        )
    }

    private func updateExportControls(canExport: Bool, isExportingPNG: Bool) {
        exportPNGButton.isEnabled = canExport && !isExportingPNG
        exportPNGButton.title = isExportingPNG ? "Exporting..." : "Export PNG..."
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

    @objc private func modeChanged(_ sender: NSPopUpButton) {
        guard let mode = DisplayMode(rawValue: UInt32(sender.selectedTag())) else {
            return
        }

        onModeChanged?(mode)
    }

    @objc private func colorMapChanged(_ sender: NSPopUpButton) {
        guard let colorMap = ColorMap(rawValue: UInt32(sender.selectedTag())) else {
            return
        }

        onColorMapChanged?(colorMap)
    }

    @objc private func windowLevelChanged(_ sender: NSSlider) {
        onWindowLevelChanged?(Float(windowSlider.doubleValue), Float(levelSlider.doubleValue))
    }

    @objc private func resetWindowLevelButtonPressed(_ sender: NSButton) {
        onResetWindowLevel?()
    }

    @objc private func homeButtonPressed(_ sender: NSButton) {
        onResetView?()
    }

    @objc private func reloadFilesButtonPressed(_ sender: NSButton) {
        onReload?()
    }

    @objc private func exportPNGButtonPressed(_ sender: NSButton) {
        onExportPNG?()
    }
}
