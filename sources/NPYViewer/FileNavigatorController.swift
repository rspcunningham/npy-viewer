import AppKit

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

final class FileNavigatorController: NSObject, NSTableViewDataSource, NSTableViewDelegate {
    let view = NSView()
    let dividerView = NSView()

    private let tableView = FileNavigatorTableView()
    private let scrollView = NSScrollView()
    private var widthConstraint: NSLayoutConstraint?
    private var dividerWidthConstraint: NSLayoutConstraint?
    private var urls: [URL] = []
    private var isSynchronizingSelection = false

    var onSelectionChanged: ((Int) -> Void)?

    var itemCount: Int {
        urls.count
    }

    var selectedRow: Int {
        tableView.selectedRow
    }

    init(fallbackFirstResponder: NSResponder?) {
        super.init()
        configureView()
        configureDivider()
        configureTable(fallbackFirstResponder: fallbackFirstResponder)
    }

    func setWidthConstraints(_ widthConstraint: NSLayoutConstraint, dividerWidthConstraint: NSLayoutConstraint) {
        self.widthConstraint = widthConstraint
        self.dividerWidthConstraint = dividerWidthConstraint
        updateVisibility()
    }

    func setURLs(_ urls: [URL]) {
        self.urls = urls
        tableView.reloadData()
        updateVisibility()
    }

    func selectRow(_ row: Int?) {
        isSynchronizingSelection = true
        defer { isSynchronizingSelection = false }

        guard let row, urls.indices.contains(row) else {
            tableView.deselectAll(nil)
            return
        }

        tableView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        tableView.scrollRowToVisible(row)
    }

    func restoreFirstResponderAfterNavigation(
        in window: NSWindow?,
        previousFirstResponder: NSResponder?,
        fallbackFirstResponder: NSResponder
    ) {
        guard let window, window.firstResponder === tableView else {
            return
        }

        if let previousFirstResponder, previousFirstResponder !== tableView {
            window.makeFirstResponder(previousFirstResponder)
        } else {
            window.makeFirstResponder(fallbackFirstResponder)
        }
    }

    func numberOfRows(in tableView: NSTableView) -> Int {
        urls.count
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard urls.indices.contains(row) else {
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

        label.stringValue = urls[row].lastPathComponent
        return label
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        guard !isSynchronizingSelection else {
            return
        }

        let row = tableView.selectedRow
        guard row >= 0 else {
            return
        }

        onSelectionChanged?(row)
    }

    private func configureView() {
        view.wantsLayer = true
        view.appearance = NSAppearance(named: .darkAqua)
        view.layer?.backgroundColor = NSColor(
            calibratedRed: 0.082,
            green: 0.086,
            blue: 0.094,
            alpha: 1
        ).cgColor
        view.isHidden = true

        let titleLabel = makeSectionTitleLabel("Files")
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(titleLabel)

        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = false
        view.addSubview(scrollView)

        NSLayoutConstraint.activate([
            titleLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 14),
            titleLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -14),
            titleLabel.topAnchor.constraint(equalTo: view.topAnchor, constant: 18),

            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 8),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -8),
            scrollView.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 10),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -8)
        ])
    }

    private func configureDivider() {
        dividerView.wantsLayer = true
        dividerView.layer?.backgroundColor = NSColor(
            calibratedRed: 0.19,
            green: 0.20,
            blue: 0.22,
            alpha: 1
        ).cgColor
        dividerView.isHidden = true
    }

    private func configureTable(fallbackFirstResponder: NSResponder?) {
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("filename"))
        column.resizingMask = .autoresizingMask
        tableView.addTableColumn(column)
        tableView.headerView = nil
        tableView.rowHeight = 28
        tableView.intercellSpacing = NSSize(width: 0, height: 2)
        tableView.selectionHighlightStyle = .regular
        tableView.backgroundColor = .clear
        tableView.fallbackFirstResponder = fallbackFirstResponder
        tableView.delegate = self
        tableView.dataSource = self

        scrollView.documentView = tableView
    }

    private func updateVisibility() {
        let shouldShowNavigator = urls.count > 1
        widthConstraint?.constant = shouldShowNavigator ? 240 : 0
        dividerWidthConstraint?.constant = shouldShowNavigator ? 1 : 0
        view.isHidden = !shouldShowNavigator
        dividerView.isHidden = !shouldShowNavigator
    }

    private func makeSectionTitleLabel(_ title: String) -> NSTextField {
        let titleLabel = NSTextField(labelWithString: title.uppercased())
        titleLabel.font = .systemFont(ofSize: 10, weight: .medium)
        titleLabel.textColor = NSColor(white: 0.54, alpha: 1)
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        return titleLabel
    }
}
