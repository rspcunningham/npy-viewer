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

struct ViewerSessionItem {
    let url: URL
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
    let isAutomaticReload: Bool
    let previousDisplayedURL: URL?
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

    private(set) var directoryURL: URL?
    private(set) var items: [ViewerSessionItem] = []
    private(set) var selectedIndex: Int?
    private(set) var displayedURL: URL?

    var onItemsChanged: (() -> Void)?
    var onSelectionStarted: ((URL) -> Void)?
    var onLoadCompleted: ((ViewerSessionLoadResult) -> Void)?
    var onSessionCleared: ((URL?, String) -> Void)?

    var itemURLs: [URL] {
        items.map(\.url)
    }

    var selectedURL: URL? {
        guard let selectedIndex, items.indices.contains(selectedIndex) else {
            return nil
        }

        return items[selectedIndex].url
    }

    var canReload: Bool {
        directoryURL != nil || !items.isEmpty || displayedURL != nil
    }

    func open(url: URL, currentState: ViewerSessionCurrentState) throws {
        if NPYFileDiscovery.isDirectory(url) {
            try openDirectory(url, currentState: currentState)
            return
        }

        guard NPYFileDiscovery.isNPYFile(url) else {
            throw ViewerOpenError.unsupportedFile(url)
        }

        openSession(
            directoryURL: nil,
            urls: [url],
            selectedIndex: 0,
            preservingViewSettings: false,
            preservingViewport: false,
            isAutomaticReload: false,
            currentState: currentState
        )
    }

    func reload(currentState: ViewerSessionCurrentState, isAutomatic: Bool = false) throws {
        saveCurrentState(currentState)

        if let directoryURL {
            try reloadDirectory(directoryURL, currentState: currentState, isAutomatic: isAutomatic)
            return
        }

        guard let url = selectedURL ?? displayedURL ?? items.first?.url else {
            return
        }

        openSession(
            directoryURL: nil,
            urls: [url],
            selectedIndex: 0,
            preservingViewSettings: true,
            preservingViewport: true,
            isAutomaticReload: isAutomatic,
            currentState: currentState
        )
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
        guard let directoryURL else {
            return url.lastPathComponent
        }

        return "\(directoryURL.lastPathComponent) - \(url.lastPathComponent)"
    }

    private func openDirectory(_ url: URL, currentState: ViewerSessionCurrentState) throws {
        let urls = try NPYFileDiscovery.npyFiles(in: url)
        guard !urls.isEmpty else {
            throw ViewerOpenError.noNPYFiles(url)
        }

        openSession(
            directoryURL: url,
            urls: urls,
            selectedIndex: 0,
            preservingViewSettings: false,
            preservingViewport: false,
            isAutomaticReload: false,
            currentState: currentState
        )
    }

    private func reloadDirectory(
        _ directoryURL: URL,
        currentState: ViewerSessionCurrentState,
        isAutomatic: Bool
    ) throws {
        let previousSelectedURL = selectedURL ?? displayedURL
        let previousSelectedIndex = selectedIndex
        let urls = try NPYFileDiscovery.npyFiles(in: directoryURL)
        guard !urls.isEmpty else {
            clearSession(
                directoryURL: directoryURL,
                message: "No .npy files found in \(directoryURL.lastPathComponent)."
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
            preservingViewport: true,
            isAutomaticReload: isAutomatic,
            currentState: currentState
        )
    }

    private func openSession(
        directoryURL: URL?,
        urls: [URL],
        selectedIndex: Int,
        preservingViewSettings: Bool,
        preservingViewport: Bool,
        isAutomaticReload: Bool,
        currentState: ViewerSessionCurrentState
    ) {
        saveCurrentState(currentState)
        self.directoryURL = directoryURL
        items = urls.map(ViewerSessionItem.init(url:))
        self.selectedIndex = nil
        displayedURL = nil

        if preservingViewSettings {
            let urls = Set(urls)
            windowLevelByURL = windowLevelByURL.filter { urls.contains($0.key) }
            displayModeByURL = displayModeByURL.filter { urls.contains($0.key) }
        } else {
            windowLevelByURL = [:]
            displayModeByURL = [:]
        }

        startLoadingItem(
            at: selectedIndex,
            preservingViewport: preservingViewport,
            isAutomaticReload: isAutomaticReload
        )
    }

    private func startLoadingItem(
        at index: Int,
        preservingViewport: Bool,
        isAutomaticReload: Bool = false
    ) {
        guard items.indices.contains(index) else {
            return
        }

        requestID &+= 1
        let requestID = requestID
        let previousDisplayedURL = displayedURL
        selectedIndex = index
        displayedURL = nil
        let url = items[index].url
        let context = ViewerSessionLoadContext(
            url: url,
            shouldPreserveViewport: preservingViewport,
            windowLevelState: windowLevelByURL[url],
            displayModeState: displayModeByURL[url],
            isAutomaticReload: isAutomaticReload,
            previousDisplayedURL: previousDisplayedURL
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

    private func clearSession(directoryURL: URL?, message: String) {
        requestID &+= 1
        self.directoryURL = directoryURL
        items = []
        selectedIndex = nil
        displayedURL = nil
        windowLevelByURL = [:]
        displayModeByURL = [:]
        onItemsChanged?()
        onSessionCleared?(directoryURL, message)
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
}
