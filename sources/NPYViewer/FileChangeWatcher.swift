import Darwin
import Foundation
import NPYViewerSupport

final class FileChangeWatcher {
    enum Target: Equatable {
        case directory(URL, selectedFileURL: URL?)
        case file(URL)
        case session(directoryURLs: [URL], fileURLs: [URL], selectedFileURL: URL?)
    }

    private struct FileSignature: Equatable {
        let entries: [FileEntry]
    }

    private struct FileEntry: Equatable {
        let path: String
        let exists: Bool
        let modificationTime: TimeInterval
        let size: UInt64
        let inode: UInt64
    }

    private let debounceInterval: TimeInterval
    private var sources: [DispatchSourceFileSystemObject] = []
    private var debounceWorkItem: DispatchWorkItem?
    private var target: Target?
    private var signature = FileSignature(entries: [])
    private var onChange: (() -> Void)?

    init(debounceInterval: TimeInterval = 0.25) {
        self.debounceInterval = debounceInterval
    }

    deinit {
        stop()
    }

    func startWatching(target: Target, onChange: @escaping () -> Void) throws {
        stop()

        let sources = Self.watchedURLs(for: target).compactMap { url -> DispatchSourceFileSystemObject? in
            let fileDescriptor = open(url.path, O_EVTONLY)
            guard fileDescriptor >= 0 else {
                return nil
            }

            let source = DispatchSource.makeFileSystemObjectSource(
                fileDescriptor: fileDescriptor,
                eventMask: [.attrib, .delete, .extend, .rename, .write],
                queue: .main
            )

            source.setEventHandler { [weak self] in
                self?.scheduleChangeCheck()
            }
            source.setCancelHandler {
                close(fileDescriptor)
            }
            return source
        }
        guard !sources.isEmpty else {
            throw CocoaError(.fileReadNoSuchFile)
        }

        self.target = target
        signature = Self.signature(for: target)
        self.onChange = onChange
        self.sources = sources

        for source in sources {
            source.resume()
        }
    }

    func stop() {
        debounceWorkItem?.cancel()
        debounceWorkItem = nil
        target = nil
        onChange = nil

        for source in sources {
            source.cancel()
        }
        sources = []
    }

    private func scheduleChangeCheck() {
        debounceWorkItem?.cancel()

        let workItem = DispatchWorkItem { [weak self] in
            self?.notifyIfSignatureChanged()
        }
        debounceWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + debounceInterval, execute: workItem)
    }

    private func notifyIfSignatureChanged() {
        guard let target else {
            return
        }

        let nextSignature = Self.signature(for: target)
        guard nextSignature != signature else {
            return
        }

        signature = nextSignature
        onChange?()
    }

    private static func signature(for target: Target) -> FileSignature {
        FileSignature(entries: signatureURLs(for: target).map { fileEntry(for: $0) })
    }

    private static func watchedURLs(for target: Target) -> [URL] {
        let urls: [URL]
        switch target {
        case .directory(let url, let selectedFileURL):
            urls = [url] + [selectedFileURL].compactMap(\.self)
        case .file(let url):
            urls = [url.deletingLastPathComponent(), url]
        case .session(let directoryURLs, let fileURLs, let selectedFileURL):
            urls = directoryURLs +
                fileURLs.flatMap { [$0.deletingLastPathComponent(), $0] } +
                [selectedFileURL].compactMap(\.self)
        }

        var seenPaths = Set<String>()
        return urls.filter { url in
            seenPaths.insert(url.standardizedFileURL.path).inserted
        }
    }

    private static func signatureURLs(for target: Target) -> [URL] {
        let urls: [URL]
        switch target {
        case .directory(let url, _):
            urls = (try? NPYFileDiscovery.npyFiles(in: url)) ?? []
        case .file(let url):
            urls = [url]
        case .session(let directoryURLs, let fileURLs, _):
            let directoryFileURLs = directoryURLs.flatMap { directoryURL in
                (try? NPYFileDiscovery.npyFiles(in: directoryURL)) ?? []
            }
            urls = directoryFileURLs + fileURLs
        }

        var seenPaths = Set<String>()
        return urls
            .sorted { lhs, rhs in
                lhs.standardizedFileURL.path.localizedStandardCompare(rhs.standardizedFileURL.path) == .orderedAscending
            }
            .filter { url in
                seenPaths.insert(url.standardizedFileURL.path).inserted
            }
    }

    private static func fileEntry(for url: URL) -> FileEntry {
        let path = url.standardizedFileURL.path
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: path) else {
            return FileEntry(
                path: path,
                exists: false,
                modificationTime: 0,
                size: 0,
                inode: 0
            )
        }

        return FileEntry(
            path: path,
            exists: true,
            modificationTime: (attributes[.modificationDate] as? Date)?.timeIntervalSinceReferenceDate ?? 0,
            size: (attributes[.size] as? NSNumber)?.uint64Value ?? 0,
            inode: (attributes[.systemFileNumber] as? NSNumber)?.uint64Value ?? 0
        )
    }
}
