import AppKit
import UniformTypeIdentifiers

final class PNGExportCoordinator {
    private let queue = DispatchQueue(label: "com.parasight.NPYViewer.png-export", qos: .userInitiated)
    private(set) var isExporting = false

    var onExportingChanged: ((Bool) -> Void)?
    var onError: ((Error) -> Void)?

    func export(renderer: MetalRenderer, sourceURL: URL) {
        let snapshot: MetalRenderer.PNGExportSnapshot
        do {
            snapshot = try renderer.makePNGExportSnapshot()
        } catch {
            onError?(error)
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

        setExporting(true)
        queue.async { [weak self, renderer] in
            let result = Result {
                try renderer.writePNG(from: snapshot, to: destinationURL)
            }

            DispatchQueue.main.async { [weak self] in
                self?.setExporting(false)
                if case .failure(let error) = result {
                    self?.onError?(error)
                }
            }
        }
    }

    private func setExporting(_ isExporting: Bool) {
        self.isExporting = isExporting
        onExportingChanged?(isExporting)
    }
}
