import AppKit

final class ViewerWindowController: NSWindowController {
    private let viewerViewController = ViewerViewController()

    init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1100, height: 900),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "NPYViewer"
        window.minSize = NSSize(width: 560, height: 420)
        window.contentViewController = viewerViewController

        super.init(window: window)

        viewerViewController.onTitleChanged = { [weak window] title in
            window?.title = title
        }
        window.center()
    }

    required init?(coder: NSCoder) {
        nil
    }

    func open(url: URL) {
        viewerViewController.open(url: url)
    }

    func openDocument() {
        viewerViewController.openDocument()
    }

    func resetZoom() {
        viewerViewController.resetZoom()
    }
}
