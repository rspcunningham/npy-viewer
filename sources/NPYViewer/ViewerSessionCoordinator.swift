import Foundation
import NPYCore
import NPYViewerSupport

enum ViewerOpenError: LocalizedError {
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

enum ViewerSessionSourceKind {
    case directory
    case looseFiles
}

struct ViewerSessionSource {
    let id: UUID
    let kind: ViewerSessionSourceKind
    let url: URL?
    var fileURLs: [URL]

    var title: String {
        switch kind {
        case .directory:
            url?.lastPathComponent ?? "Directory"
        case .looseFiles:
            "Opened Files"
        }
    }
}

struct ViewerSessionItem {
    let url: URL
    let sourceID: UUID
}

struct ViewerNavigatorItem {
    let index: Int
    let url: URL
    let title: String
}

struct ViewerNavigatorSection {
    let title: String
    let url: URL?
    let items: [ViewerNavigatorItem]
}

struct ViewerWindowLevelState {
    let window: Float
    let level: Float
}

struct ViewerSessionCurrentState {
    let hasImage: Bool
    let window: Float
    let level: Float
    let displayMode: DisplayMode
    let preserveViewportEnabled: Bool
}

struct ViewerSessionLoadContext {
    let url: URL
    let shouldPreserveViewport: Bool
    let windowLevelState: ViewerWindowLevelState?
    let displayModeState: DisplayMode?
}

enum ViewerSessionLoadResult {
    case success(NPYArray, ViewerSessionLoadContext)
    case failure(Error, ViewerSessionLoadContext)
}

final class ViewerSessionCoordinator {
    private let fileLoadQueue = DispatchQueue(label: "com.parasight.NPYViewer.file-load", qos: .userInitiated)
    private var requestID = 0
    private var windowLevelByURL: [URL: ViewerWindowLevelState] = [:]
    private var displayModeByURL: [URL: DisplayMode] = [:]
    private var sources: [ViewerSessionSource] = []

    private(set) var items: [ViewerSessionItem] = []
    private(set) var selectedIndex: Int?
    private(set) var displayedURL: URL?

    var onItemsChanged: (() -> Void)?
    var onSelectionStarted: ((URL) -> Void)?
    var onLoadCompleted: ((ViewerSessionLoadResult) -> Void)?
    var onSessionCleared: ((String) -> Void)?

    var itemURLs: [URL] {
        items.map(\.url)
    }

    var navigatorSections: [ViewerNavigatorSection] {
        var nextIndex = 0
        return sources.map { source in
            let navigatorItems = source.fileURLs.map { url in
                defer { nextIndex += 1 }
                return ViewerNavigatorItem(
                    index: nextIndex,
                    url: url,
                    title: url.lastPathComponent
                )
            }

            return ViewerNavigatorSection(
                title: source.title,
                url: source.url,
                items: navigatorItems
            )
        }
    }

    var sessionTitle: String {
        guard !sources.isEmpty else {
            return "NPYViewer"
        }

        guard sources.count == 1 else {
            return "Session"
        }

        return sources[0].title
    }

    var selectedURL: URL? {
        guard let selectedIndex, items.indices.contains(selectedIndex) else {
            return nil
        }

        return items[selectedIndex].url
    }

    var canReload: Bool {
        !sources.isEmpty || !items.isEmpty || displayedURL != nil
    }

    func open(url: URL, currentState: ViewerSessionCurrentState) throws {
        try open(urls: [url], currentState: currentState)
    }

    func open(urls: [URL], currentState: ViewerSessionCurrentState) throws {
        let resolvedEntries = try resolveOpenEntries(urls)
        guard !resolvedEntries.isEmpty else {
            return
        }

        saveCurrentState(currentState)
        let previousSelectedURL = selectedURL ?? displayedURL
        let firstAddedURL = mergeResolvedEntries(resolvedEntries)
        rebuildItems()
        pruneViewState()

        guard let selectedIndex = selectionIndex(preferredURL: firstAddedURL ?? previousSelectedURL) else {
            notifyEmptySession(message: "No .npy files found in opened sources.")
            return
        }

        startLoadingItem(at: selectedIndex, preservingViewport: false)
    }

    func reload(currentState: ViewerSessionCurrentState) throws {
        saveCurrentState(currentState)
        guard !sources.isEmpty else {
            return
        }

        let previousSelectedURL = selectedURL ?? displayedURL
        let previousSelectedIndex = selectedIndex

        for index in sources.indices where sources[index].kind == .directory {
            guard let directoryURL = sources[index].url else {
                continue
            }
            sources[index].fileURLs = try uniqueURLs(NPYFileDiscovery.npyFiles(in: directoryURL))
        }

        removeEmptyLooseFilesSource()
        rebuildItems()
        pruneViewState()

        guard !items.isEmpty else {
            notifyEmptySession(message: "No .npy files found in opened sources.")
            return
        }

        let index = reloadedSelectionIndex(
            preferredURL: previousSelectedURL,
            previousIndex: previousSelectedIndex
        )
        startLoadingItem(at: index, preservingViewport: true)
    }

    func selectItem(
        at index: Int,
        currentState: ViewerSessionCurrentState,
        preservingCurrentViewport: Bool = false
    ) {
        guard items.indices.contains(index) else {
            return
        }

        let shouldPreserveViewport = preservingCurrentViewport ||
            (
                currentState.preserveViewportEnabled &&
                    items.count > 1 &&
                    selectedIndex != nil &&
                    selectedIndex != index
            )
        saveCurrentState(currentState)
        startLoadingItem(at: index, preservingViewport: shouldPreserveViewport)
    }

    func markDisplayed(_ url: URL?) {
        displayedURL = url
    }

    func title(for url: URL) -> String {
        guard
            let source = source(containing: url),
            source.kind == .directory
        else {
            return url.lastPathComponent
        }

        return "\(source.title) - \(url.lastPathComponent)"
    }

    private func startLoadingItem(at index: Int, preservingViewport: Bool) {
        guard items.indices.contains(index) else {
            return
        }

        requestID &+= 1
        let requestID = requestID
        selectedIndex = index
        displayedURL = nil
        let url = items[index].url
        let context = ViewerSessionLoadContext(
            url: url,
            shouldPreserveViewport: preservingViewport,
            windowLevelState: windowLevelByURL[url],
            displayModeState: displayModeByURL[url]
        )

        onItemsChanged?()
        onSelectionStarted?(url)

        fileLoadQueue.async { [weak self] in
            let result = Result {
                try NPYArray(contentsOf: url)
            }

            DispatchQueue.main.async { [weak self] in
                guard let self, self.requestID == requestID else {
                    return
                }

                switch result {
                case .success(let array):
                    self.onLoadCompleted?(.success(array, context))
                case .failure(let error):
                    self.onLoadCompleted?(.failure(error, context))
                }
            }
        }
    }

    private func notifyEmptySession(message: String) {
        requestID &+= 1
        selectedIndex = nil
        displayedURL = nil
        onItemsChanged?()
        onSessionCleared?(message)
    }

    private func reloadedSelectionIndex(preferredURL: URL?, previousIndex: Int?) -> Int {
        if let preferredURL, let index = items.firstIndex(where: { sameFile($0.url, preferredURL) }) {
            return index
        }

        if let previousIndex {
            return min(max(previousIndex, 0), items.count - 1)
        }

        return 0
    }

    private func saveCurrentState(_ currentState: ViewerSessionCurrentState) {
        guard let displayedURL, currentState.hasImage else {
            return
        }

        windowLevelByURL[displayedURL] = ViewerWindowLevelState(
            window: currentState.window,
            level: currentState.level
        )
        displayModeByURL[displayedURL] = currentState.displayMode
    }

    private func selectionIndex(preferredURL: URL?) -> Int? {
        if let preferredURL, let index = items.firstIndex(where: { sameFile($0.url, preferredURL) }) {
            return index
        }

        return items.isEmpty ? nil : 0
    }

    private func rebuildItems() {
        items = sources.flatMap { source in
            source.fileURLs.map { ViewerSessionItem(url: $0, sourceID: source.id) }
        }
    }

    private func pruneViewState() {
        let urls = Set(itemURLs.map(canonicalURL))
        windowLevelByURL = windowLevelByURL.filter { urls.contains(canonicalURL($0.key)) }
        displayModeByURL = displayModeByURL.filter { urls.contains(canonicalURL($0.key)) }
    }

    private func source(containing url: URL) -> ViewerSessionSource? {
        let canonical = canonicalURL(url)
        return sources.first { source in
            source.fileURLs.contains { canonicalURL($0) == canonical }
        }
    }

    private enum ResolvedOpenEntry {
        case directory(url: URL, fileURLs: [URL])
        case file(URL)
    }

    private func resolveOpenEntries(_ urls: [URL]) throws -> [ResolvedOpenEntry] {
        var entries: [ResolvedOpenEntry] = []
        for url in urls {
            if NPYFileDiscovery.isDirectory(url) {
                let fileURLs = try uniqueURLs(NPYFileDiscovery.npyFiles(in: url))
                guard !fileURLs.isEmpty else {
                    throw ViewerOpenError.noNPYFiles(url)
                }
                entries.append(.directory(url: url, fileURLs: fileURLs))
                continue
            }

            guard NPYFileDiscovery.isNPYFile(url) else {
                throw ViewerOpenError.unsupportedFile(url)
            }

            entries.append(.file(url))
        }

        return entries
    }

    private func mergeResolvedEntries(_ entries: [ResolvedOpenEntry]) -> URL? {
        var firstAddedURL: URL?

        for entry in entries {
            let addedURL: URL?
            switch entry {
            case .directory(let url, let fileURLs):
                addedURL = mergeDirectorySource(url: url, fileURLs: fileURLs)
            case .file(let url):
                addedURL = mergeLooseFile(url)
            }

            if firstAddedURL == nil {
                firstAddedURL = addedURL
            }
        }

        return firstAddedURL
    }

    private func mergeDirectorySource(url: URL, fileURLs: [URL]) -> URL? {
        let uniqueFileURLs = uniqueURLs(fileURLs)
        let newFileKeys = Set(uniqueFileURLs.map(canonicalURL))
        removeLooseFiles(containedIn: newFileKeys)

        if let existingIndex = sources.firstIndex(where: { source in
            source.kind == .directory && source.url.map { sameFile($0, url) } == true
        }) {
            let previousKeys = Set(sources[existingIndex].fileURLs.map(canonicalURL))
            sources[existingIndex].fileURLs = uniqueFileURLs
            return uniqueFileURLs.first { !previousKeys.contains(canonicalURL($0)) } ?? uniqueFileURLs.first
        }

        sources.append(
            ViewerSessionSource(
                id: UUID(),
                kind: .directory,
                url: url,
                fileURLs: uniqueFileURLs
            )
        )
        return uniqueFileURLs.first
    }

    private func mergeLooseFile(_ url: URL) -> URL? {
        let key = canonicalURL(url)
        guard !directoryFileKeys().contains(key) else {
            return nil
        }

        let sourceIndex = looseFilesSourceIndex() ?? appendLooseFilesSource()
        guard !sources[sourceIndex].fileURLs.contains(where: { canonicalURL($0) == key }) else {
            return nil
        }

        sources[sourceIndex].fileURLs.append(url)
        return url
    }

    private func looseFilesSourceIndex() -> Int? {
        sources.firstIndex { $0.kind == .looseFiles }
    }

    private func appendLooseFilesSource() -> Int {
        sources.append(
            ViewerSessionSource(
                id: UUID(),
                kind: .looseFiles,
                url: nil,
                fileURLs: []
            )
        )
        return sources.count - 1
    }

    private func removeLooseFiles(containedIn keys: Set<URL>) {
        guard let sourceIndex = looseFilesSourceIndex() else {
            return
        }

        sources[sourceIndex].fileURLs.removeAll { keys.contains(canonicalURL($0)) }
        removeEmptyLooseFilesSource()
    }

    private func removeEmptyLooseFilesSource() {
        sources.removeAll { $0.kind == .looseFiles && $0.fileURLs.isEmpty }
    }

    private func directoryFileKeys() -> Set<URL> {
        Set(
            sources
                .filter { $0.kind == .directory }
                .flatMap(\.fileURLs)
                .map(canonicalURL)
        )
    }

    private func uniqueURLs(_ urls: [URL]) -> [URL] {
        var seen: Set<URL> = []
        return urls.filter { url in
            let canonical = canonicalURL(url)
            guard !seen.contains(canonical) else {
                return false
            }
            seen.insert(canonical)
            return true
        }
    }

    private func sameFile(_ lhs: URL, _ rhs: URL) -> Bool {
        canonicalURL(lhs) == canonicalURL(rhs)
    }

    private func canonicalURL(_ url: URL) -> URL {
        url.standardizedFileURL.resolvingSymlinksInPath()
    }
}
