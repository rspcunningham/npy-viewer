import AppKit
import ImageIO
import Metal
import MetalKit
import NPYCore
import NPYViewerSupport
import UniformTypeIdentifiers

enum RendererError: LocalizedError {
    case noMetalDevice
    case noCommandQueue
    case noCommandBuffer
    case noCommandEncoder
    case noBuffer
    case noArray
    case noTexture
    case textureTooLarge(width: Int, height: Int, max: Int)
    case shaderCompile(String)
    case commandFailed(String)
    case pngImageCreateFailed
    case pngDestinationCreateFailed(URL)
    case pngWriteFailed(URL)

    var errorDescription: String? {
        switch self {
        case .noMetalDevice:
            "Metal is not available on this Mac."
        case .noCommandQueue:
            "Could not create a Metal command queue."
        case .noCommandBuffer:
            "Could not create a Metal command buffer."
        case .noCommandEncoder:
            "Could not create a Metal render encoder."
        case .noBuffer:
            "Could not create a Metal readback buffer."
        case .noArray:
            "No image is loaded."
        case .noTexture:
            "Could not create a Metal texture for this array."
        case .textureTooLarge(let width, let height, let max):
            "Texture \(width)x\(height) exceeds the current v0.0 limit of \(max)x\(max)."
        case .shaderCompile(let message):
            "Could not compile Metal shaders: \(message)"
        case .commandFailed(let message):
            "Metal export failed: \(message)"
        case .pngImageCreateFailed:
            "Could not create an image from the rendered pixels."
        case .pngDestinationCreateFailed(let url):
            "Could not create a PNG file at \(url.path)."
        case .pngWriteFailed(let url):
            "Could not write PNG file at \(url.path)."
        }
    }
}

final class MetalRenderer: NSObject, MTKViewDelegate {
    struct ViewportState {
        let normalizedCenter: CGPoint
        let zoom: CGFloat
    }

    struct PNGExportSnapshot {
        fileprivate let texture: MTLTexture
        fileprivate let width: Int
        fileprivate let height: Int
        fileprivate let displayMode: DisplayMode
        fileprivate let colorMap: ColorMap
        fileprivate let window: Float
        fileprivate let level: Float
    }

    private struct Vertex {
        var position: SIMD2<Float>
        var texCoord: SIMD2<Float>
    }

    private let maxTextureDimension = 16_384
    private let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    private let pipelineState: MTLRenderPipelineState
    private let colorMapTexture: MTLTexture
    private weak var view: MTKView?

    private(set) var array: NPYArray?
    private var texture: MTLTexture?
    private(set) var displayMode: DisplayMode = .scalar
    private(set) var colorMap: ColorMap = .gray
    private(set) var window: Float = 1
    private(set) var level: Float = 0.5
    private var scale: CGFloat = 1
    private var offset: CGPoint = .zero

    var onDisplayChanged: (() -> Void)?

    init(view: MTKView, shaderLibraryURL: URL? = nil) throws {
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw RendererError.noMetalDevice
        }
        guard let commandQueue = device.makeCommandQueue() else {
            throw RendererError.noCommandQueue
        }

        self.device = device
        self.commandQueue = commandQueue
        self.colorMapTexture = try Self.makeColorMapTexture(device: device)

        let library = try Self.makeShaderLibrary(device: device, explicitURL: shaderLibraryURL)

        let descriptor = MTLRenderPipelineDescriptor()
        guard let vertexFunction = library.makeFunction(name: "vertex_main") else {
            throw RendererError.shaderCompile("Missing vertex_main in default.metallib")
        }
        guard let fragmentFunction = library.makeFunction(name: "fragment_main") else {
            throw RendererError.shaderCompile("Missing fragment_main in default.metallib")
        }
        descriptor.vertexFunction = vertexFunction
        descriptor.fragmentFunction = fragmentFunction
        descriptor.colorAttachments[0].pixelFormat = view.colorPixelFormat
        self.pipelineState = try device.makeRenderPipelineState(descriptor: descriptor)

        super.init()

        self.view = view
        view.device = device
        view.clearColor = MTLClearColor(red: 0.025, green: 0.026, blue: 0.028, alpha: 1)
        view.framebufferOnly = true
        view.enableSetNeedsDisplay = true
        view.isPaused = true
        view.delegate = self
    }

    func setArray(
        _ array: NPYArray,
        preserving viewportState: ViewportState? = nil,
        windowLevel: (window: Float, level: Float)? = nil,
        displayMode restoredDisplayMode: DisplayMode? = nil
    ) throws {
        if array.width > maxTextureDimension || array.height > maxTextureDimension {
            throw RendererError.textureTooLarge(width: array.width, height: array.height, max: maxTextureDimension)
        }

        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: pixelFormat(for: array.elementType),
            width: array.width,
            height: array.height,
            mipmapped: false
        )
        descriptor.storageMode = .shared
        descriptor.usage = [.shaderRead]

        guard let texture = device.makeTexture(descriptor: descriptor) else {
            throw RendererError.noTexture
        }

        try array.withRawPayloadPointer { pointer in
            texture.replace(
                region: MTLRegionMake2D(0, 0, array.width, array.height),
                mipmapLevel: 0,
                withBytes: pointer,
                bytesPerRow: array.width * array.elementType.bytesPerElement
            )
        }

        self.array = array
        self.texture = texture
        if array.elementType.isComplex, let restoredDisplayMode, restoredDisplayMode != .scalar {
            self.displayMode = restoredDisplayMode
        } else {
            self.displayMode = array.elementType.isComplex ? .complexAbs : .scalar
        }
        if let windowLevel {
            setWindowLevel(window: windowLevel.window, level: windowLevel.level)
        } else {
            resetWindowLevel()
        }
        if let viewportState {
            apply(viewportState, to: array)
        } else {
            resetView()
        }
        requestDraw()
        onDisplayChanged?()
    }

    func clearArray() {
        array = nil
        texture = nil
        displayMode = .scalar
        scale = 1
        offset = .zero
        requestDraw()
        onDisplayChanged?()
    }

    func resetView() {
        guard let array, let view else {
            scale = 1
            offset = .zero
            return
        }

        guard let fitScale = fitScale(for: array, in: view.bounds.size) else {
            scale = 1
            offset = .zero
            return
        }

        let size = view.bounds.size
        scale = fitScale
        offset = CGPoint(
            x: (size.width - CGFloat(array.width) * scale) * 0.5,
            y: (size.height - CGFloat(array.height) * scale) * 0.5
        )
    }

    func viewportState() -> ViewportState? {
        guard
            let array,
            let view,
            scale.isFinite,
            scale > 0,
            let fitScale = fitScale(for: array, in: view.bounds.size)
        else {
            return nil
        }

        let size = view.bounds.size
        let viewCenter = CGPoint(x: size.width * 0.5, y: size.height * 0.5)
        let imageCenter = CGPoint(
            x: (viewCenter.x - offset.x) / scale,
            y: (viewCenter.y - offset.y) / scale
        )
        let normalizedCenter = CGPoint(
            x: imageCenter.x / CGFloat(array.width),
            y: imageCenter.y / CGFloat(array.height)
        )
        let zoom = scale / fitScale

        guard
            normalizedCenter.x.isFinite,
            normalizedCenter.y.isFinite,
            zoom.isFinite,
            zoom > 0
        else {
            return nil
        }

        return ViewportState(normalizedCenter: normalizedCenter, zoom: zoom)
    }

    func zoom(by factor: CGFloat, around point: CGPoint) {
        guard array != nil, factor.isFinite, factor > 0 else {
            return
        }

        let oldScale = scale
        let imageX = (point.x - offset.x) / oldScale
        let imageY = (point.y - offset.y) / oldScale
        let newScale = min(max(oldScale * factor, 0.01), 256)

        scale = newScale
        offset = CGPoint(
            x: point.x - imageX * newScale,
            y: point.y - imageY * newScale
        )
        requestDraw()
    }

    func pan(by delta: CGSize) {
        guard array != nil else {
            return
        }

        offset.x += delta.width
        offset.y += delta.height
        requestDraw()
    }

    func imageCoordinate(for point: CGPoint) -> (x: Int, y: Int)? {
        guard let array, scale > 0 else {
            return nil
        }

        let x = Int(floor((point.x - offset.x) / scale))
        let y = Int(floor((point.y - offset.y) / scale))
        guard x >= 0, y >= 0, x < array.width, y < array.height else {
            return nil
        }
        return (x, y)
    }

    func setDisplayMode(_ mode: DisplayMode) {
        guard array?.elementType.isComplex == true else {
            guard displayMode != .scalar else {
                return
            }
            displayMode = .scalar
            onDisplayChanged?()
            return
        }

        let nextMode: DisplayMode = mode == .scalar ? .complexAbs : mode
        guard displayMode != nextMode else {
            return
        }

        displayMode = nextMode
        requestDraw()
        onDisplayChanged?()
    }

    func setColorMap(_ colorMap: ColorMap) {
        guard self.colorMap != colorMap else {
            return
        }

        self.colorMap = colorMap
        requestDraw()
        onDisplayChanged?()
    }

    func setWindowLevel(window: Float, level: Float) {
        let nextWindow = min(max(window, 0.01), 1)
        let nextLevel = min(max(level, 0), 1)
        guard self.window != nextWindow || self.level != nextLevel else {
            return
        }

        self.window = nextWindow
        self.level = nextLevel
        requestDraw()
        onDisplayChanged?()
    }

    func resetWindowLevel() {
        setWindowLevel(window: 1, level: 0.5)
    }

    func makePNGExportSnapshot() throws -> PNGExportSnapshot {
        guard let array, let texture else {
            throw RendererError.noArray
        }

        return PNGExportSnapshot(
            texture: texture,
            width: array.width,
            height: array.height,
            displayMode: displayMode,
            colorMap: colorMap,
            window: window,
            level: level
        )
    }

    func writePNG(from snapshot: PNGExportSnapshot, to url: URL) throws {
        let bytesPerPixel = 4
        let minimumBytesPerRow = snapshot.width * bytesPerPixel
        let bytesPerRow = aligned(minimumBytesPerRow, to: 256)
        let pixelData = try renderExportPixels(from: snapshot, bytesPerRow: bytesPerRow)

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let provider = CGDataProvider(data: pixelData as CFData) else {
            throw RendererError.pngImageCreateFailed
        }

        let bitmapInfo = CGBitmapInfo.byteOrder32Little.union(
            CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedFirst.rawValue)
        )
        guard let image = CGImage(
            width: snapshot.width,
            height: snapshot.height,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: bitmapInfo,
            provider: provider,
            decode: nil,
            shouldInterpolate: false,
            intent: .defaultIntent
        ) else {
            throw RendererError.pngImageCreateFailed
        }

        guard let destination = CGImageDestinationCreateWithURL(
            url as CFURL,
            UTType.png.identifier as CFString,
            1,
            nil
        ) else {
            throw RendererError.pngDestinationCreateFailed(url)
        }

        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else {
            throw RendererError.pngWriteFailed(url)
        }
    }

    func requestDraw() {
        view?.needsDisplay = true
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        resetView()
        requestDraw()
        onDisplayChanged?()
    }

    func draw(in view: MTKView) {
        guard
            let commandBuffer = commandQueue.makeCommandBuffer(),
            let descriptor = view.currentRenderPassDescriptor,
            let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: descriptor)
        else {
            return
        }

        if let array, let texture {
            encoder.setRenderPipelineState(pipelineState)
            let vertices = quadVertices(for: array, in: view.bounds.size)
            vertices.withUnsafeBytes { bytes in
                if let baseAddress = bytes.baseAddress {
                    encoder.setVertexBytes(baseAddress, length: bytes.count, index: 0)
                }
            }

            var mode = displayMode.rawValue
            var colorMapRaw = colorMap.rawValue
            var windowLevel = SIMD2<Float>(window, level)
            encoder.setFragmentBytes(&mode, length: MemoryLayout<UInt32>.size, index: 0)
            encoder.setFragmentBytes(&colorMapRaw, length: MemoryLayout<UInt32>.size, index: 1)
            encoder.setFragmentBytes(&windowLevel, length: MemoryLayout<SIMD2<Float>>.size, index: 2)
            encoder.setFragmentTexture(texture, index: 0)
            encoder.setFragmentTexture(colorMapTexture, index: 1)
            encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: vertices.count)
        }

        encoder.endEncoding()

        if let drawable = view.currentDrawable {
            commandBuffer.present(drawable)
        }
        commandBuffer.commit()
    }

    private func renderExportPixels(from snapshot: PNGExportSnapshot, bytesPerRow: Int) throws -> Data {
        let textureDescriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm,
            width: snapshot.width,
            height: snapshot.height,
            mipmapped: false
        )
        textureDescriptor.storageMode = .private
        textureDescriptor.usage = [.renderTarget]

        guard let outputTexture = device.makeTexture(descriptor: textureDescriptor) else {
            throw RendererError.noTexture
        }
        let bufferLength = bytesPerRow * snapshot.height
        guard let readbackBuffer = device.makeBuffer(length: bufferLength, options: .storageModeShared) else {
            throw RendererError.noBuffer
        }

        let renderPassDescriptor = MTLRenderPassDescriptor()
        renderPassDescriptor.colorAttachments[0].texture = outputTexture
        renderPassDescriptor.colorAttachments[0].loadAction = .clear
        renderPassDescriptor.colorAttachments[0].storeAction = .store
        renderPassDescriptor.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)

        guard let commandBuffer = commandQueue.makeCommandBuffer() else {
            throw RendererError.noCommandBuffer
        }
        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor) else {
            throw RendererError.noCommandEncoder
        }

        encoder.setRenderPipelineState(pipelineState)
        let vertices = fullImageVertices()
        vertices.withUnsafeBytes { bytes in
            if let baseAddress = bytes.baseAddress {
                encoder.setVertexBytes(baseAddress, length: bytes.count, index: 0)
            }
        }

        var mode = snapshot.displayMode.rawValue
        var colorMapRaw = snapshot.colorMap.rawValue
        var windowLevel = SIMD2<Float>(snapshot.window, snapshot.level)
        encoder.setFragmentBytes(&mode, length: MemoryLayout<UInt32>.size, index: 0)
        encoder.setFragmentBytes(&colorMapRaw, length: MemoryLayout<UInt32>.size, index: 1)
        encoder.setFragmentBytes(&windowLevel, length: MemoryLayout<SIMD2<Float>>.size, index: 2)
        encoder.setFragmentTexture(snapshot.texture, index: 0)
        encoder.setFragmentTexture(colorMapTexture, index: 1)
        encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: vertices.count)
        encoder.endEncoding()

        guard let blitEncoder = commandBuffer.makeBlitCommandEncoder() else {
            throw RendererError.noCommandEncoder
        }
        blitEncoder.copy(
            from: outputTexture,
            sourceSlice: 0,
            sourceLevel: 0,
            sourceOrigin: MTLOrigin(x: 0, y: 0, z: 0),
            sourceSize: MTLSize(width: snapshot.width, height: snapshot.height, depth: 1),
            to: readbackBuffer,
            destinationOffset: 0,
            destinationBytesPerRow: bytesPerRow,
            destinationBytesPerImage: bufferLength
        )
        blitEncoder.endEncoding()

        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()

        if let error = commandBuffer.error {
            throw RendererError.commandFailed(error.localizedDescription)
        }

        return Data(bytes: readbackBuffer.contents(), count: bufferLength)
    }

    private func quadVertices(for array: NPYArray, in viewSize: CGSize) -> [Vertex] {
        guard viewSize.width > 0, viewSize.height > 0 else {
            return []
        }

        let left = offset.x
        let top = offset.y
        let right = left + CGFloat(array.width) * scale
        let bottom = top + CGFloat(array.height) * scale

        func ndc(x: CGFloat, y: CGFloat) -> SIMD2<Float> {
            SIMD2<Float>(
                Float((x / viewSize.width) * 2 - 1),
                Float(1 - (y / viewSize.height) * 2)
            )
        }

        return [
            Vertex(position: ndc(x: left, y: top), texCoord: SIMD2<Float>(0, 0)),
            Vertex(position: ndc(x: left, y: bottom), texCoord: SIMD2<Float>(0, 1)),
            Vertex(position: ndc(x: right, y: top), texCoord: SIMD2<Float>(1, 0)),
            Vertex(position: ndc(x: right, y: bottom), texCoord: SIMD2<Float>(1, 1))
        ]
    }

    private func fullImageVertices() -> [Vertex] {
        [
            Vertex(position: SIMD2<Float>(-1, 1), texCoord: SIMD2<Float>(0, 0)),
            Vertex(position: SIMD2<Float>(-1, -1), texCoord: SIMD2<Float>(0, 1)),
            Vertex(position: SIMD2<Float>(1, 1), texCoord: SIMD2<Float>(1, 0)),
            Vertex(position: SIMD2<Float>(1, -1), texCoord: SIMD2<Float>(1, 1))
        ]
    }

    private func apply(_ state: ViewportState, to array: NPYArray) {
        guard
            let view,
            state.normalizedCenter.x.isFinite,
            state.normalizedCenter.y.isFinite,
            state.zoom.isFinite,
            state.zoom > 0,
            let fitScale = fitScale(for: array, in: view.bounds.size)
        else {
            resetView()
            return
        }

        let size = view.bounds.size
        let minZoom = 0.01 / fitScale
        let maxZoom = 256 / fitScale
        let nextZoom = clamp(state.zoom, min: minZoom, max: maxZoom)
        let normalizedCenter = CGPoint(
            x: clamp(state.normalizedCenter.x, min: 0, max: 1),
            y: clamp(state.normalizedCenter.y, min: 0, max: 1)
        )
        let viewCenter = CGPoint(x: size.width * 0.5, y: size.height * 0.5)

        scale = fitScale * nextZoom
        offset = CGPoint(
            x: viewCenter.x - normalizedCenter.x * CGFloat(array.width) * scale,
            y: viewCenter.y - normalizedCenter.y * CGFloat(array.height) * scale
        )
    }

    private func fitScale(for array: NPYArray, in size: CGSize) -> CGFloat? {
        guard size.width > 0, size.height > 0 else {
            return nil
        }

        let fitScale = min(size.width / CGFloat(array.width), size.height / CGFloat(array.height))
        guard fitScale.isFinite, fitScale > 0 else {
            return nil
        }
        return fitScale
    }

    private func clamp(_ value: CGFloat, min lowerBound: CGFloat, max upperBound: CGFloat) -> CGFloat {
        min(max(value, lowerBound), upperBound)
    }

    private func aligned(_ value: Int, to alignment: Int) -> Int {
        ((value + alignment - 1) / alignment) * alignment
    }

    private func pixelFormat(for elementType: NPYElementType) -> MTLPixelFormat {
        switch elementType {
        case .uint8:
            return .r8Unorm
        case .uint16:
            return .r16Unorm
        case .float32:
            return .r32Float
        case .complex64:
            return .rg32Float
        }
    }

    private static func makeShaderLibrary(device: MTLDevice, explicitURL: URL?) throws -> MTLLibrary {
        guard let libraryURL = explicitURL ?? defaultShaderLibraryURL() else {
            throw RendererError.shaderCompile(
                "Could not find default.metallib. Build with scripts/build.sh or set NPYVIEWER_METALLIB_PATH."
            )
        }

        do {
            return try device.makeLibrary(URL: libraryURL)
        } catch {
            throw RendererError.shaderCompile("Could not load \(libraryURL.path): \(error.localizedDescription)")
        }
    }

    static func defaultShaderLibraryURL() -> URL? {
        let environment = ProcessInfo.processInfo.environment
        if let path = environment["NPYVIEWER_METALLIB_PATH"], !path.isEmpty {
            return URL(fileURLWithPath: path)
        }

        return Bundle.main.url(forResource: "default", withExtension: "metallib")
    }

    private static func makeColorMapTexture(device: MTLDevice) throws -> MTLTexture {
        let sampleCount = 256
        let colorMapCount = Int((ColorMap.allCases.map(\.rawValue).max() ?? 0) + 1)
        let bytesPerPixel = 4
        let bytesPerRow = sampleCount * bytesPerPixel

        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba8Unorm,
            width: sampleCount,
            height: colorMapCount,
            mipmapped: false
        )
        descriptor.storageMode = .shared
        descriptor.usage = [.shaderRead]

        guard let texture = device.makeTexture(descriptor: descriptor) else {
            throw RendererError.noTexture
        }

        var pixels = [UInt8](repeating: 0, count: bytesPerRow * colorMapCount)
        for colorMap in ColorMap.allCases {
            let row = Int(colorMap.rawValue)
            for index in 0..<sampleCount {
                let value = Float(index) / Float(sampleCount - 1)
                let color = colorMap.color(forNormalizedValue: value)
                let offset = row * bytesPerRow + index * bytesPerPixel
                pixels[offset] = colorByte(color.red)
                pixels[offset + 1] = colorByte(color.green)
                pixels[offset + 2] = colorByte(color.blue)
                pixels[offset + 3] = 255
            }
        }

        texture.replace(
            region: MTLRegionMake2D(0, 0, sampleCount, colorMapCount),
            mipmapLevel: 0,
            withBytes: pixels,
            bytesPerRow: bytesPerRow
        )
        return texture
    }

    private static func colorByte(_ value: Float) -> UInt8 {
        UInt8(clamping: Int((min(max(value, 0), 1) * 255).rounded()))
    }
}
