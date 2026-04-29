import AppKit
import Foundation
import ImageIO
import Metal
import MetalKit
import NPYCore
@testable import NPYViewerApp
import NPYViewerSupport
import Testing

@MainActor
@Test func imageMetalViewInitializesInteractionDefaults() {
    let view = ImageMetalView(frame: NSRect(x: 0, y: 0, width: 120, height: 80), device: nil)

    #expect(view.acceptsFirstResponder)
    #expect(view.currentTopLeftMousePointIfInside() == nil)
    view.updateTrackingAreas()
    view.resetCursorRects()
}

@MainActor
@Test func viewerControllerBuildsInitialViewState() {
    guard MTLCreateSystemDefaultDevice() != nil else {
        return
    }

    let controller = ViewerViewController()
    controller.loadView()
    controller.viewDidLoad()

    #expect(controller.view.subviews.count >= 5)
    #expect(controller.numberOfRows(in: NSTableView()) == 0)
    #expect(controller.tableView(NSTableView(), viewFor: nil, row: 0) == nil)

    let imageView = ImageMetalView(frame: NSRect(x: 0, y: 0, width: 120, height: 80), device: nil)
    controller.resetZoom()
    controller.imageMetalViewDidEndHover(imageView)
    controller.imageMetalView(imageView, didZoomBy: 2, around: CGPoint(x: 20, y: 30))
    controller.imageMetalView(imageView, didPanBy: CGSize(width: 5, height: -3))
}

@MainActor
@Test func viewerControllerReloadsDirectoryContents() throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("NPYViewerReloadTests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }

    let firstURL = directory.appendingPathComponent("first.npy")
    try makeNPY(descr: "<f4", shape: [1, 1], payload: floats([1])).write(to: firstURL)

    let controller = ViewerViewController()
    controller.loadView()
    controller.open(url: directory)
    #expect(controller.numberOfRows(in: NSTableView()) == 1)

    let secondURL = directory.appendingPathComponent("second.npy")
    try makeNPY(descr: "<f4", shape: [1, 1], payload: floats([2])).write(to: secondURL)
    controller.reloadSession()
    #expect(controller.numberOfRows(in: NSTableView()) == 2)

    try FileManager.default.removeItem(at: firstURL)
    try FileManager.default.removeItem(at: secondURL)
    controller.reloadSession()
    #expect(controller.numberOfRows(in: NSTableView()) == 0)
}

@MainActor
@Test func fileNavigatorControllerTracksURLsAndSelection() {
    let fallback = NSView()
    let controller = FileNavigatorController(fallbackFirstResponder: fallback)
    let urls = [
        URL(fileURLWithPath: "/tmp/a.npy"),
        URL(fileURLWithPath: "/tmp/b.npy")
    ]

    controller.setURLs(urls)
    #expect(controller.itemCount == 2)
    #expect(controller.numberOfRows(in: NSTableView()) == 2)

    controller.selectRow(1)
    #expect(controller.selectedRow == 1)

    controller.setURLs([])
    #expect(controller.itemCount == 0)
}

@MainActor
@Test func colorMapScaleViewFormatsTickLabels() {
    let scaleView = ColorMapScaleView(frame: NSRect(x: 0, y: 0, width: 160, height: 40))

    #expect(scaleView.tickLabels == ["--", "--", "--"])

    scaleView.setState(
        colorMap: .viridis,
        displayMode: .scalar,
        window: 0.5,
        level: 0.5,
        isScaleEnabled: true
    )
    #expect(scaleView.colorMap == .viridis)
    #expect(scaleView.windowValue == 0.5)
    #expect(scaleView.levelValue == 0.5)
    #expect(scaleView.tickLabels == ["0.25", "0.50", "0.75"])

    scaleView.setState(
        colorMap: .hot,
        displayMode: .complexPhase,
        window: 1,
        level: 0.5,
        isScaleEnabled: true
    )
    #expect(scaleView.colorMap == .hot)
    #expect(scaleView.displayMode == .complexPhase)
    #expect(scaleView.tickLabels == ["-pi", "0", "+pi"])

    let grayStart = ColorMapScaleView.color(forNormalizedValue: 0, colorMap: .gray)
    let grayEnd = ColorMapScaleView.color(forNormalizedValue: 1, colorMap: .gray)
    #expect(grayStart != grayEnd)
}

@MainActor
@Test func windowControllerCreatesViewerWindow() {
    let controller = ViewerWindowController()

    #expect(controller.window?.title == "NPYViewer")
    #expect(controller.window?.contentViewController is ViewerViewController)
    controller.resetZoom()
}

@MainActor
@Test func appDelegateHandlesSimpleActionsBeforeLaunch() {
    let delegate = AppDelegate()

    #expect(delegate.applicationShouldTerminateAfterLastWindowClosed(NSApplication.shared))
    delegate.openDocument(nil)
    delegate.resetZoom(nil)
}

@MainActor
@Test func rendererLoadsArraysAndUpdatesViewportState() throws {
    guard MTLCreateSystemDefaultDevice() != nil else {
        return
    }

    let view = MTKView(frame: NSRect(x: 0, y: 0, width: 400, height: 200), device: nil)
    let renderer = try MetalRenderer(view: view)
    var displayChangeCount = 0
    renderer.onDisplayChanged = {
        displayChangeCount += 1
    }

    let array = try NPYArray(data: makeNPY(descr: "<f4", shape: [2, 4], payload: floats(Array(0..<8).map(Float.init))))
    try renderer.setArray(array)

    #expect(renderer.array === array)
    #expect(renderer.displayMode == .scalar)
    #expect(renderer.colorMap == .gray)
    #expect(renderer.window == 1)
    #expect(renderer.level == 0.5)
    #expect(displayChangeCount == 1)

    let coordinate = renderer.imageCoordinate(for: CGPoint(x: 399, y: 199))
    #expect(coordinate?.x == 3)
    #expect(coordinate?.y == 1)
    #expect(renderer.imageCoordinate(for: CGPoint(x: 401, y: 199)) == nil)

    guard let initialState = renderer.viewportState() else {
        Issue.record("Expected viewport state after loading an array")
        return
    }
    #expect(isClose(initialState.normalizedCenter.x, 0.5))
    #expect(isClose(initialState.normalizedCenter.y, 0.5))
    #expect(isClose(initialState.zoom, 1))

    renderer.zoom(by: 2, around: CGPoint(x: 200, y: 100))
    guard let zoomedState = renderer.viewportState() else {
        Issue.record("Expected viewport state after zooming")
        return
    }
    #expect(isClose(zoomedState.normalizedCenter.x, 0.5))
    #expect(isClose(zoomedState.normalizedCenter.y, 0.5))
    #expect(isClose(zoomedState.zoom, 2))

    renderer.pan(by: CGSize(width: 20, height: -10))
    guard let pannedState = renderer.viewportState() else {
        Issue.record("Expected viewport state after panning")
        return
    }
    #expect(pannedState.normalizedCenter.x < zoomedState.normalizedCenter.x)
    #expect(pannedState.normalizedCenter.y > zoomedState.normalizedCenter.y)

    renderer.setWindowLevel(window: -5, level: 2)
    #expect(renderer.window == 0.01)
    #expect(renderer.level == 1)

    renderer.setColorMap(.magma)
    #expect(renderer.colorMap == .magma)

    renderer.setDisplayMode(.complexImag)
    #expect(renderer.displayMode == .scalar)
}

@MainActor
@Test func rendererLoadsCompiledShaderLibrary() throws {
    guard let device = MTLCreateSystemDefaultDevice() else {
        return
    }
    guard let libraryURL = MetalRenderer.defaultShaderLibraryURL() else {
        Issue.record("Expected NPYVIEWER_METALLIB_PATH or bundled default.metallib")
        return
    }

    let library = try device.makeLibrary(URL: libraryURL)
    #expect(library.makeFunction(name: "vertex_main") != nil)
    #expect(library.makeFunction(name: "fragment_main") != nil)

    let view = MTKView(frame: NSRect(x: 0, y: 0, width: 64, height: 64), device: nil)
    _ = try MetalRenderer(view: view, shaderLibraryURL: libraryURL)
}

@MainActor
@Test func rendererFailsForMissingShaderLibrary() throws {
    guard MTLCreateSystemDefaultDevice() != nil else {
        return
    }

    let missingURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("missing-\(UUID().uuidString).metallib")
    let view = MTKView(frame: NSRect(x: 0, y: 0, width: 64, height: 64), device: nil)

    expectRendererError("missing shader library", {
        _ = try MetalRenderer(view: view, shaderLibraryURL: missingURL)
    }, matches: { error in
        guard case .shaderCompile(let message) = error else { return false }
        return message.contains(missingURL.lastPathComponent)
    })
}

@MainActor
@Test func rendererLoadsUnsignedIntegerArrays() throws {
    guard MTLCreateSystemDefaultDevice() != nil else {
        return
    }

    let view = MTKView(frame: NSRect(x: 0, y: 0, width: 64, height: 64), device: nil)
    let renderer = try MetalRenderer(view: view)

    let uint8Array = try NPYArray(data: makeNPY(descr: "|u1", shape: [2, 2], payload: Data([0, 128, 255, 64])))
    try renderer.setArray(uint8Array)
    #expect(renderer.array === uint8Array)
    #expect(renderer.displayMode == .scalar)

    let uint16Array = try NPYArray(data: makeNPY(descr: "<u2", shape: [2, 1, 1], payload: uint16s([0, 65_535])))
    try renderer.setArray(uint16Array)
    #expect(renderer.array === uint16Array)
    #expect(renderer.displayMode == .scalar)
    renderer.setDisplayMode(.complexPhase)
    #expect(renderer.displayMode == .scalar)
}

@MainActor
@Test func rendererHandlesComplexDisplayModesAndClearState() throws {
    guard MTLCreateSystemDefaultDevice() != nil else {
        return
    }

    let view = MTKView(frame: NSRect(x: 0, y: 0, width: 100, height: 100), device: nil)
    let renderer = try MetalRenderer(view: view)
    let array = try NPYArray(data: makeNPY(descr: "<c8", shape: [1, 1], payload: floats([3, 4])))

    try renderer.setArray(array)
    #expect(renderer.displayMode == .complexAbs)

    renderer.setDisplayMode(.scalar)
    #expect(renderer.displayMode == .complexAbs)

    renderer.setDisplayMode(.complexPhase)
    #expect(renderer.displayMode == .complexPhase)

    renderer.clearArray()
    #expect(renderer.array == nil)
    #expect(renderer.displayMode == .scalar)

    expectRendererError("snapshot without array", {
        _ = try renderer.makePNGExportSnapshot()
    }, matches: { error in
        guard case .noArray = error else { return false }
        return true
    })
}

@MainActor
@Test func rendererExportsPNGSnapshot() throws {
    guard MTLCreateSystemDefaultDevice() != nil else {
        return
    }

    let view = MTKView(frame: NSRect(x: 0, y: 0, width: 64, height: 64), device: nil)
    let renderer = try MetalRenderer(view: view)
    let array = try NPYArray(data: makeNPY(descr: "<f4", shape: [2, 2], payload: floats([0, 0.25, 0.5, 1])))
    try renderer.setArray(array)
    renderer.setColorMap(.viridis)
    renderer.setWindowLevel(window: 0.5, level: 0.5)

    let snapshot = try renderer.makePNGExportSnapshot()
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("NPYViewerAppTests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }

    let url = directory.appendingPathComponent("export.png")
    try renderer.writePNG(from: snapshot, to: url)

    let data = try Data(contentsOf: url)
    #expect(data.starts(with: [0x89, 0x50, 0x4e, 0x47]))

    guard
        let source = CGImageSourceCreateWithURL(url as CFURL, nil),
        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
    else {
        Issue.record("Expected exported PNG metadata")
        return
    }

    #expect(properties[kCGImagePropertyPixelWidth] as? Int == 2)
    #expect(properties[kCGImagePropertyPixelHeight] as? Int == 2)
}

private func makeNPY(descr: String, shape: [Int], payload: Data) -> Data {
    var data = Data([0x93, 0x4e, 0x55, 0x4d, 0x50, 0x59, 0x01, 0x00])
    let shapeText = shape.map(String.init).joined(separator: ", ") + (shape.count == 1 ? "," : "")
    var header = "{'descr': '\(descr)', 'fortran_order': False, 'shape': (\(shapeText)), }"
    let baseLength = 10
    let paddedHeaderLength = ((baseLength + header.utf8.count + 1 + 15) / 16) * 16 - baseLength
    header += String(repeating: " ", count: paddedHeaderLength - header.utf8.count - 1)
    header += "\n"

    let length = UInt16(header.utf8.count)
    data.append(UInt8(length & 0xff))
    data.append(UInt8((length >> 8) & 0xff))
    data.append(header.data(using: .ascii)!)
    data.append(payload)
    return data
}

private func floats(_ values: [Float]) -> Data {
    var values = values
    return Data(bytes: &values, count: values.count * MemoryLayout<Float>.size)
}

private func uint16s(_ values: [UInt16]) -> Data {
    var values = values.map { UInt16(littleEndian: $0) }
    return Data(bytes: &values, count: values.count * MemoryLayout<UInt16>.size)
}

private func isClose(_ lhs: CGFloat, _ rhs: CGFloat, tolerance: CGFloat = 0.0001) -> Bool {
    abs(lhs - rhs) <= tolerance
}

private func expectRendererError(
    _ description: String,
    _ body: () throws -> Void,
    matches: (RendererError) -> Bool
) {
    do {
        try body()
        Issue.record("Expected RendererError for \(description)")
    } catch let error as RendererError {
        #expect(matches(error))
    } catch {
        Issue.record("Expected RendererError for \(description), got \(error)")
    }
}
