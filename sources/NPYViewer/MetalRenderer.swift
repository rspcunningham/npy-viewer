import AppKit
import Metal
import MetalKit
import NPYCore

enum RendererError: LocalizedError {
    case noMetalDevice
    case noCommandQueue
    case noTexture
    case textureTooLarge(width: Int, height: Int, max: Int)
    case shaderCompile(String)

    var errorDescription: String? {
        switch self {
        case .noMetalDevice:
            "Metal is not available on this Mac."
        case .noCommandQueue:
            "Could not create a Metal command queue."
        case .noTexture:
            "Could not create a Metal texture for this array."
        case .textureTooLarge(let width, let height, let max):
            "Texture \(width)x\(height) exceeds the current v0.0 limit of \(max)x\(max)."
        case .shaderCompile(let message):
            "Could not compile Metal shaders: \(message)"
        }
    }
}

final class MetalRenderer: NSObject, MTKViewDelegate {
    private struct Vertex {
        var position: SIMD2<Float>
        var texCoord: SIMD2<Float>
    }

    private let maxTextureDimension = 16_384
    private let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    private let pipelineState: MTLRenderPipelineState
    private weak var view: MTKView?

    private(set) var array: NPYArray?
    private var texture: MTLTexture?
    private(set) var displayMode: DisplayMode = .scalar
    private var scale: CGFloat = 1
    private var offset: CGPoint = .zero

    var onDisplayChanged: (() -> Void)?

    init(view: MTKView) throws {
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw RendererError.noMetalDevice
        }
        guard let commandQueue = device.makeCommandQueue() else {
            throw RendererError.noCommandQueue
        }

        self.device = device
        self.commandQueue = commandQueue

        let library: MTLLibrary
        do {
            library = try device.makeLibrary(source: Self.shaderSource, options: nil)
        } catch {
            throw RendererError.shaderCompile(error.localizedDescription)
        }

        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = library.makeFunction(name: "vertex_main")
        descriptor.fragmentFunction = library.makeFunction(name: "fragment_main")
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

    func setArray(_ array: NPYArray) throws {
        if array.width > maxTextureDimension || array.height > maxTextureDimension {
            throw RendererError.textureTooLarge(width: array.width, height: array.height, max: maxTextureDimension)
        }

        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: array.elementType == .float32 ? .r32Float : .rg32Float,
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
        self.displayMode = array.elementType == .complex64 ? .complexAbs : .scalar
        resetView()
        requestDraw()
        onDisplayChanged?()
    }

    func resetView() {
        guard let array, let view else {
            scale = 1
            offset = .zero
            return
        }

        let size = view.bounds.size
        guard size.width > 0, size.height > 0 else {
            scale = 1
            offset = .zero
            return
        }

        let fitScale = min(size.width / CGFloat(array.width), size.height / CGFloat(array.height))
        scale = fitScale
        offset = CGPoint(
            x: (size.width - CGFloat(array.width) * scale) * 0.5,
            y: (size.height - CGFloat(array.height) * scale) * 0.5
        )
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
        guard array?.elementType == .complex64 else {
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

    func cycleComplexMode() {
        let modes: [DisplayMode] = [.complexAbs, .complexPhase, .complexReal, .complexImag]
        guard let index = modes.firstIndex(of: displayMode) else {
            setDisplayMode(.complexAbs)
            return
        }
        setDisplayMode(modes[(index + 1) % modes.count])
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
            encoder.setFragmentBytes(&mode, length: MemoryLayout<UInt32>.size, index: 0)
            encoder.setFragmentTexture(texture, index: 0)
            encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: vertices.count)
        }

        encoder.endEncoding()

        if let drawable = view.currentDrawable {
            commandBuffer.present(drawable)
        }
        commandBuffer.commit()
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
}

private extension MetalRenderer {
    static let shaderSource = """
    #include <metal_stdlib>
    using namespace metal;

    struct Vertex {
        float2 position;
        float2 texCoord;
    };

    struct VertexOut {
        float4 position [[position]];
        float2 texCoord;
    };

    vertex VertexOut vertex_main(uint vertexID [[vertex_id]],
                                 constant Vertex *vertices [[buffer(0)]]) {
        VertexOut out;
        out.position = float4(vertices[vertexID].position, 0.0, 1.0);
        out.texCoord = vertices[vertexID].texCoord;
        return out;
    }

    fragment float4 fragment_main(VertexOut in [[stage_in]],
                                  texture2d<float> image [[texture(0)]],
                                  constant uint &mode [[buffer(0)]]) {
        constexpr sampler imageSampler(address::clamp_to_edge, filter::linear);
        float4 sample = image.sample(imageSampler, in.texCoord);
        float value = sample.r;

        if (mode == 1) {
            value = length(sample.rg);
        } else if (mode == 2) {
            constexpr float pi = 3.14159265358979323846;
            value = (atan2(sample.g, sample.r) + pi) / (2.0 * pi);
        } else if (mode == 3) {
            value = sample.r;
        } else if (mode == 4) {
            value = sample.g;
        }

        value = clamp(value, 0.0, 1.0);
        return float4(value, value, value, 1.0);
    }
    """
}
