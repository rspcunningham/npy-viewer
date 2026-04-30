import AppKit
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var windowController: ViewerWindowController?
    private var pendingOpenURLs: [URL] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        buildMenu()

        let controller = ViewerWindowController()
        controller.showWindow(nil)
        windowController = controller

        if !pendingOpenURLs.isEmpty {
            controller.open(urls: pendingOpenURLs)
        }
        pendingOpenURLs.removeAll()

        var argumentURLs: [URL] = []
        for argument in CommandLine.arguments.dropFirst() {
            let url = URL(fileURLWithPath: argument)
            if FileManager.default.fileExists(atPath: url.path) {
                argumentURLs.append(url)
            }
        }
        if !argumentURLs.isEmpty {
            controller.open(urls: argumentURLs)
        }

        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        guard let controller = windowController else {
            pendingOpenURLs.append(contentsOf: urls)
            return
        }

        controller.open(urls: urls)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    @objc func openDocument(_ sender: Any?) {
        windowController?.openDocument()
    }

    @objc func resetZoom(_ sender: Any?) {
        windowController?.resetZoom()
    }

    private func buildMenu() {
        let mainMenu = NSMenu()

        let appMenuItem = NSMenuItem()
        mainMenu.addItem(appMenuItem)
        let appMenu = NSMenu()
        appMenu.addItem(
            withTitle: "Quit NPYViewer",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        appMenuItem.submenu = appMenu

        let fileMenuItem = NSMenuItem()
        mainMenu.addItem(fileMenuItem)
        let fileMenu = NSMenu(title: "File")
        fileMenu.addItem(withTitle: "Open...", action: #selector(openDocument(_:)), keyEquivalent: "o")
        fileMenuItem.submenu = fileMenu

        let viewMenuItem = NSMenuItem()
        mainMenu.addItem(viewMenuItem)
        let viewMenu = NSMenu(title: "View")
        viewMenu.addItem(withTitle: "Reset Zoom", action: #selector(resetZoom(_:)), keyEquivalent: "0")
        viewMenuItem.submenu = viewMenu

        NSApp.mainMenu = mainMenu
    }
}
