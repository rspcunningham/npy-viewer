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
    private(set) var colorMap: ColorMap = .gray
    private(set) var window: Float = 1
    private(set) var level: Float = 0.5
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
        resetWindowLevel()
        resetView()
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

    float3 ramp(float value,
                float3 c0,
                float3 c1,
                float3 c2,
                float3 c3,
                float3 c4) {
        if (value < 0.25) {
            return mix(c0, c1, value / 0.25);
        } else if (value < 0.5) {
            return mix(c1, c2, (value - 0.25) / 0.25);
        } else if (value < 0.75) {
            return mix(c2, c3, (value - 0.5) / 0.25);
        }
        return mix(c3, c4, (value - 0.75) / 0.25);
    }

    float3 apply_color_map(float value, uint colorMap) {
        if (colorMap == 1) {
            return ramp(
                value,
                float3(0.267, 0.005, 0.329),
                float3(0.231, 0.322, 0.545),
                float3(0.129, 0.569, 0.549),
                float3(0.369, 0.788, 0.384),
                float3(0.993, 0.906, 0.144)
            );
        } else if (colorMap == 2) {
            return ramp(
                value,
                float3(0.000, 0.000, 0.016),
                float3(0.231, 0.059, 0.439),
                float3(0.549, 0.161, 0.506),
                float3(0.871, 0.286, 0.408),
                float3(0.988, 0.992, 0.749)
            );
        } else if (colorMap == 3) {
            return float3(
                smoothstep(0.00, 0.45, value),
                smoothstep(0.35, 0.75, value),
                smoothstep(0.70, 1.00, value)
            );
        }

        return float3(value, value, value);
    }

    fragment float4 fragment_main(VertexOut in [[stage_in]],
                                  texture2d<float> image [[texture(0)]],
                                  constant uint &mode [[buffer(0)]],
                                  constant uint &colorMap [[buffer(1)]],
                                  constant float2 &windowLevel [[buffer(2)]]) {
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
        } else if (mode == 5) {
            value = dot(sample.rg, sample.rg);
        }

        float window = max(windowLevel.x, 0.01);
        float level = windowLevel.y;
        value = (value - (level - window * 0.5)) / window;
        value = clamp(value, 0.0, 1.0);
        return float4(apply_color_map(value, colorMap), 1.0);
    }
    """
}
