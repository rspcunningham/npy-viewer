import AppKit
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var windowController: ViewerWindowController?
    private var pendingOpenURLs: [URL] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        buildMenu()

        let controller = ViewerWindowController()
        controller.showWindow(nil)
        windowController = controller

        for url in pendingOpenURLs {
            controller.open(url: url)
        }
        pendingOpenURLs.removeAll()

        for argument in CommandLine.arguments.dropFirst() where argument.lowercased().hasSuffix(".npy") {
            controller.open(url: URL(fileURLWithPath: argument))
        }

        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        guard let controller = windowController else {
            pendingOpenURLs.append(contentsOf: urls)
            return
        }

        for url in urls {
            controller.open(url: url)
        }
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
