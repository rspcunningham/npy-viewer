import AppKit

final class FileNavigatorOutlineView: NSOutlineView {
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

private final class FileNavigatorNode: NSObject {
    enum Kind {
        case source
        case file(index: Int)
    }

    let kind: Kind
    let title: String
    let url: URL?
    let children: [FileNavigatorNode]

    init(kind: Kind, title: String, url: URL?, children: [FileNavigatorNode] = []) {
        self.kind = kind
        self.title = title
        self.url = url
        self.children = children
    }

    var itemIndex: Int? {
        guard case .file(let index) = kind else {
            return nil
        }

        return index
    }
}

final class FileNavigatorController: NSObject, NSOutlineViewDataSource, NSOutlineViewDelegate {
    let view = NSView()
    let dividerView = NSView()

    private let outlineView = FileNavigatorOutlineView()
    private let scrollView = NSScrollView()
    private var widthConstraint: NSLayoutConstraint?
    private var dividerWidthConstraint: NSLayoutConstraint?
    private var rootNodes: [FileNavigatorNode] = []
    private var isSynchronizingSelection = false

    var onSelectionChanged: ((Int) -> Void)?

    var itemCount: Int {
        rootNodes.reduce(0) { count, node in count + node.children.count }
    }

    var sourceCount: Int {
        rootNodes.count
    }

    var visibleRowCount: Int {
        outlineView.numberOfRows
    }

    var selectedItemIndex: Int? {
        let row = outlineView.selectedRow
        guard row >= 0 else {
            return nil
        }

        return (outlineView.item(atRow: row) as? FileNavigatorNode)?.itemIndex
    }

    init(fallbackFirstResponder: NSResponder?) {
        super.init()
        configureView()
        configureDivider()
        configureOutline(fallbackFirstResponder: fallbackFirstResponder)
    }

    func setWidthConstraints(_ widthConstraint: NSLayoutConstraint, dividerWidthConstraint: NSLayoutConstraint) {
        self.widthConstraint = widthConstraint
        self.dividerWidthConstraint = dividerWidthConstraint
        updateVisibility()
    }

    func setSections(_ sections: [ViewerNavigatorSection]) {
        rootNodes = sections.map { section in
            FileNavigatorNode(
                kind: .source,
                title: section.title,
                url: section.url,
                children: section.items.map { item in
                    FileNavigatorNode(
                        kind: .file(index: item.index),
                        title: item.title,
                        url: item.url
                    )
                }
            )
        }

        outlineView.reloadData()
        rootNodes.forEach { outlineView.expandItem($0) }
        updateVisibility()
    }

    func selectItem(at index: Int?) {
        isSynchronizingSelection = true
        defer { isSynchronizingSelection = false }

        guard let index, let node = fileNode(for: index) else {
            outlineView.deselectAll(nil)
            return
        }

        if let parent = parentNode(for: node) {
            outlineView.expandItem(parent)
        }

        let row = outlineView.row(forItem: node)
        guard row >= 0 else {
            outlineView.deselectAll(nil)
            return
        }

        outlineView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        outlineView.scrollRowToVisible(row)
    }

    func sourceTitle(at index: Int) -> String? {
        guard rootNodes.indices.contains(index) else {
            return nil
        }

        return rootNodes[index].title
    }

    func childCountForSource(at index: Int) -> Int {
        guard rootNodes.indices.contains(index) else {
            return 0
        }

        return rootNodes[index].children.count
    }

    func childTitle(sourceIndex: Int, childIndex: Int) -> String? {
        guard
            rootNodes.indices.contains(sourceIndex),
            rootNodes[sourceIndex].children.indices.contains(childIndex)
        else {
            return nil
        }

        return rootNodes[sourceIndex].children[childIndex].title
    }

    func restoreFirstResponderAfterNavigation(
        in window: NSWindow?,
        previousFirstResponder: NSResponder?,
        fallbackFirstResponder: NSResponder
    ) {
        guard let window, window.firstResponder === outlineView else {
            return
        }

        if let previousFirstResponder, previousFirstResponder !== outlineView {
            window.makeFirstResponder(previousFirstResponder)
        } else {
            window.makeFirstResponder(fallbackFirstResponder)
        }
    }

    func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
        guard let node = item as? FileNavigatorNode else {
            return rootNodes.count
        }

        return node.children.count
    }

    func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
        guard let node = item as? FileNavigatorNode else {
            return rootNodes[index]
        }

        return node.children[index]
    }

    func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
        guard let node = item as? FileNavigatorNode else {
            return false
        }

        return !node.children.isEmpty
    }

    func outlineView(_ outlineView: NSOutlineView, shouldSelectItem item: Any) -> Bool {
        (item as? FileNavigatorNode)?.itemIndex != nil
    }

    func outlineView(_ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? {
        guard let node = item as? FileNavigatorNode else {
            return nil
        }

        let identifier = NSUserInterfaceItemIdentifier("FileNavigatorCell")
        let label: NSTextField
        if let reusedLabel = outlineView.makeView(withIdentifier: identifier, owner: self) as? NSTextField {
            label = reusedLabel
        } else {
            label = NSTextField(labelWithString: "")
            label.identifier = identifier
            label.lineBreakMode = .byTruncatingMiddle
            label.maximumNumberOfLines = 1
        }

        label.stringValue = node.title
        label.toolTip = node.url?.path

        switch node.kind {
        case .source:
            label.font = .systemFont(ofSize: 11, weight: .semibold)
            label.textColor = NSColor(white: 0.62, alpha: 1)
        case .file:
            label.font = .systemFont(ofSize: 13)
            label.textColor = NSColor(white: 0.86, alpha: 1)
        }

        return label
    }

    func outlineViewSelectionDidChange(_ notification: Notification) {
        guard !isSynchronizingSelection else {
            return
        }

        guard let index = selectedItemIndex else {
            return
        }

        onSelectionChanged?(index)
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

    private func configureOutline(fallbackFirstResponder: NSResponder?) {
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("filename"))
        column.resizingMask = .autoresizingMask
        outlineView.addTableColumn(column)
        outlineView.outlineTableColumn = column
        outlineView.headerView = nil
        outlineView.rowHeight = 28
        outlineView.intercellSpacing = NSSize(width: 0, height: 2)
        outlineView.selectionHighlightStyle = .regular
        outlineView.backgroundColor = .clear
        outlineView.indentationPerLevel = 14
        outlineView.fallbackFirstResponder = fallbackFirstResponder
        outlineView.delegate = self
        outlineView.dataSource = self

        scrollView.documentView = outlineView
    }

    private func updateVisibility() {
        let shouldShowNavigator = sourceCount > 1 || itemCount > 1
        widthConstraint?.constant = shouldShowNavigator ? 260 : 0
        dividerWidthConstraint?.constant = shouldShowNavigator ? 1 : 0
        view.isHidden = !shouldShowNavigator
        dividerView.isHidden = !shouldShowNavigator
    }

    private func fileNode(for index: Int) -> FileNavigatorNode? {
        for source in rootNodes {
            if let node = source.children.first(where: { $0.itemIndex == index }) {
                return node
            }
        }

        return nil
    }

    private func parentNode(for child: FileNavigatorNode) -> FileNavigatorNode? {
        rootNodes.first { source in
            source.children.contains { $0 === child }
        }
    }

    private func makeSectionTitleLabel(_ title: String) -> NSTextField {
        let titleLabel = NSTextField(labelWithString: title.uppercased())
        titleLabel.font = .systemFont(ofSize: 10, weight: .medium)
        titleLabel.textColor = NSColor(white: 0.54, alpha: 1)
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        return titleLabel
    }
}
