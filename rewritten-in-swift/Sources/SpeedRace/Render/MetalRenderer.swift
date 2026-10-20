import Foundation
import Metal
import QuartzCore

// Speed Race (1974) — Swift + Metal port.
//
// Metal renderer. Rewritten after the Pac-Man comparison
// (docs/METAL-VS-PACMAN.md): CPU-triangulated geometry, a retained
// triple-buffered `MTLBuffer`, shaders from a Swift string, and two pipelines
// (solid and textured) over a single vertex format.
//
// Two surfaces are rendered every frame:
//   * the CRT scene at 240 x 360 into an offscreen texture, nearest-sampled;
//   * the cabinet at 960 x 720, which composites that texture, letterboxed into
//     the window (or read back for headless screenshots).

public final class MetalRenderer {
    public static let crtWidth = 240
    public static let crtHeight = 360
    public static let canvasWidth = 960
    public static let canvasHeight = 720

    public let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    private let solidPipeline: MTLRenderPipelineState
    private let texturedPipeline: MTLRenderPipelineState
    private let crtTexture: MTLTexture
    /// Triple-buffered vertex storage. Each buffer must stay alive until the
    /// command buffer that references it completes; that lifetime rule is the
    /// mistake that made an earlier version render nothing
    /// (docs/METAL-VS-PACMAN.md, cause 3).
    private var vertexBuffers: [MTLBuffer] = []
    private var frameIndex = 0
    private let inFlight = DispatchSemaphore(value: 2)
    private let crtCanvas = VertexCanvas(reserveVertices: 30_000)
    private let cabinetCanvas = VertexCanvas(reserveVertices: 90_000)

    public init(device: MTLDevice? = nil) throws {
        guard let device = device ?? MTLCreateSystemDefaultDevice() else {
            throw RendererError.noDevice
        }
        self.device = device
        guard let queue = device.makeCommandQueue() else {
            throw RendererError.noCommandQueue
        }
        commandQueue = queue

        let library = try MetalRenderer.makeLibrary(device: device)
        guard
            let vertexFunction = library.makeFunction(name: "vertex_main"),
            let solidFragment = library.makeFunction(name: "fragment_solid"),
            let texturedFragment = library.makeFunction(name: "fragment_textured")
        else {
            throw RendererError.missingFunction
        }
        solidPipeline = try MetalRenderer.makePipeline(
            device: device, vertex: vertexFunction, fragment: solidFragment)
        texturedPipeline = try MetalRenderer.makePipeline(
            device: device, vertex: vertexFunction, fragment: texturedFragment)

        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm, width: MetalRenderer.crtWidth,
            height: MetalRenderer.crtHeight, mipmapped: false)
        descriptor.usage = [.renderTarget, .shaderRead]
        descriptor.storageMode = .private
        guard let texture = device.makeTexture(descriptor: descriptor) else {
            throw RendererError.textureAllocation
        }
        crtTexture = texture

        let capacity = 200_000 * CanvasVertex.stride
        for _ in 0..<3 {
            guard let buffer = device.makeBuffer(length: capacity, options: .storageModeShared)
            else {
                throw RendererError.textureAllocation
            }
            vertexBuffers.append(buffer)
        }
    }

    /// Compiles the shader source embedded in `MetalShaderSource`.
    public static func makeLibrary(device: MTLDevice) throws -> MTLLibrary {
        do {
            return try device.makeLibrary(source: MetalShaderSource.source, options: nil)
        } catch {
            throw RendererError.shaderCompilation(String(describing: error))
        }
    }

    private static func makePipeline(
        device: MTLDevice, vertex: MTLFunction, fragment: MTLFunction
    ) throws -> MTLRenderPipelineState {
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = vertex
        descriptor.fragmentFunction = fragment
        let attachment = descriptor.colorAttachments[0]!
        attachment.pixelFormat = .bgra8Unorm
        attachment.isBlendingEnabled = true
        attachment.rgbBlendOperation = .add
        attachment.alphaBlendOperation = .add
        attachment.sourceRGBBlendFactor = .sourceAlpha
        attachment.sourceAlphaBlendFactor = .sourceAlpha
        attachment.destinationRGBBlendFactor = .oneMinusSourceAlpha
        attachment.destinationAlphaBlendFactor = .oneMinusSourceAlpha
        return try device.makeRenderPipelineState(descriptor: descriptor)
    }

    // MARK: - Frame

    /// Renders one frame.
    ///
    /// - Parameters:
    ///   - crt: the 240 x 360 scene draw list.
    ///   - cabinet: the 960 x 720 cabinet draw list (contains one texture blit).
    ///   - drawable: window drawable, or `nil` for a headless render.
    /// - Returns: straight-alpha RGBA pixels of the cabinet when `drawable` is
    ///   `nil`, otherwise `nil`.
    @discardableResult
    public func render(
        crt: DrawList, cabinet: DrawList, drawable: CAMetalDrawable?, viewport: CGRect?
    ) throws -> (width: Int, height: Int, pixels: [UInt8])? {
        inFlight.wait()
        guard let commandBuffer = commandQueue.makeCommandBuffer() else {
            inFlight.signal()
            throw RendererError.noCommandBuffer
        }
        commandBuffer.addCompletedHandler { [inFlight] _ in inFlight.signal() }

        // --- Pass 1: the CRT scene.
        crtCanvas.reset()
        CanvasBuilder.build(crt, into: crtCanvas)
        let crtPass = MTLRenderPassDescriptor()
        crtPass.colorAttachments[0].texture = crtTexture
        crtPass.colorAttachments[0].loadAction = .clear
        crtPass.colorAttachments[0].storeAction = .store
        crtPass.colorAttachments[0].clearColor = clearColor(Palette.void)
        if let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: crtPass) {
            encode(
                canvas: crtCanvas, encoder: encoder,
                viewportSize: SIMD2<Float>(Float(Self.crtWidth), Float(Self.crtHeight)),
                texture: nil, viewport: nil)
            encoder.endEncoding()
        }

        // --- Pass 2: the cabinet.
        cabinetCanvas.reset()
        CanvasBuilder.build(cabinet, into: cabinetCanvas)

        if let drawable {
            let pass = MTLRenderPassDescriptor()
            pass.colorAttachments[0].texture = drawable.texture
            pass.colorAttachments[0].loadAction = .clear
            pass.colorAttachments[0].storeAction = .store
            pass.colorAttachments[0].clearColor = clearColor(RGBAColor.rgb(0, 0, 0))
            if let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: pass) {
                encode(
                    canvas: cabinetCanvas, encoder: encoder,
                    viewportSize: SIMD2<Float>(
                        Float(Self.canvasWidth), Float(Self.canvasHeight)),
                    texture: crtTexture, viewport: viewport)
                encoder.endEncoding()
            }
            commandBuffer.present(drawable)
            commandBuffer.commit()
            return nil
        }

        // Offscreen: render the cabinet, read it back. No row flip; the texture
        // is stored top-row-first like the draw list.
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm, width: Self.canvasWidth, height: Self.canvasHeight,
            mipmapped: false)
        descriptor.usage = [.renderTarget]
        descriptor.storageMode = .managed
        guard let target = device.makeTexture(descriptor: descriptor) else {
            commandBuffer.commit()
            throw RendererError.textureAllocation
        }
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = target
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].storeAction = .store
        pass.colorAttachments[0].clearColor = clearColor(RGBAColor.rgb(0, 0, 0))
        if let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: pass) {
            encode(
                canvas: cabinetCanvas, encoder: encoder,
                viewportSize: SIMD2<Float>(
                    Float(Self.canvasWidth), Float(Self.canvasHeight)),
                texture: crtTexture, viewport: nil)
            encoder.endEncoding()
        }
        if let blit = commandBuffer.makeBlitCommandEncoder() {
            blit.synchronize(resource: target)
            blit.endEncoding()
        }
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
        return try readBack(target)
    }

    // MARK: - Encoding

    private func encode(
        canvas: VertexCanvas, encoder: MTLRenderCommandEncoder,
        viewportSize: SIMD2<Float>, texture: MTLTexture?, viewport: CGRect?
    ) {
        guard !canvas.isEmpty else { return }

        // Upload into the current retained buffer, growing it if needed.
        let needed = canvas.vertices.count * CanvasVertex.stride
        if needed > vertexBuffers[frameIndex].length {
            let newLength = max(needed, vertexBuffers[frameIndex].length * 2)
            if let larger = device.makeBuffer(length: newLength, options: .storageModeShared) {
                vertexBuffers[frameIndex] = larger
            }
        }
        let buffer = vertexBuffers[frameIndex]
        frameIndex = (frameIndex + 1) % vertexBuffers.count
        canvas.vertices.withUnsafeBytes { raw in
            if let base = raw.baseAddress {
                buffer.contents().copyMemory(from: base, byteCount: needed)
            }
        }

        if let viewport {
            encoder.setViewport(
                MTLViewport(
                    originX: Double(viewport.origin.x), originY: Double(viewport.origin.y),
                    width: Double(viewport.width), height: Double(viewport.height),
                    znear: 0, zfar: 1))
        }
        var uniforms = viewportSize
        encoder.setVertexBuffer(buffer, offset: 0, index: 0)
        encoder.setVertexBytes(&uniforms, length: MemoryLayout<SIMD2<Float>>.stride, index: 1)

        // Draw segments in recording order, switching pipeline per segment.
        var currentTextured = false
        encoder.setRenderPipelineState(solidPipeline)
        for segment in canvas.segments where segment.range.count > 0 {
            if segment.textured {
                guard let texture else { continue }
                if !currentTextured {
                    encoder.setRenderPipelineState(texturedPipeline)
                    encoder.setFragmentTexture(texture, index: 0)
                    currentTextured = true
                }
            } else if currentTextured {
                encoder.setRenderPipelineState(solidPipeline)
                currentTextured = false
            }
            encoder.drawPrimitives(
                type: .triangle, vertexStart: segment.range.lowerBound,
                vertexCount: segment.range.count)
        }
    }

    /// Reads a rendered texture back as straight RGBA, top row first.
    ///
    /// Metal render targets are stored top-row-first, the same y-down layout as
    /// the draw list, so no flip is applied — the port's equivalent of the
    /// canonical repo's "raw framebuffer is the truth" rule (DIVERGENCES N-0006).
    private func readBack(_ target: MTLTexture) throws -> (width: Int, height: Int, pixels: [UInt8]) {
        let width = Self.canvasWidth
        let height = Self.canvasHeight
        let bytesPerRow = width * 4
        var bgra = [UInt8](repeating: 0, count: bytesPerRow * height)
        bgra.withUnsafeMutableBytes { buffer in
            target.getBytes(
                buffer.baseAddress!, bytesPerRow: bytesPerRow,
                from: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0)
        }
        var rgba = [UInt8](repeating: 0, count: bytesPerRow * height)
        for index in stride(from: 0, to: bgra.count, by: 4) {
            rgba[index] = bgra[index + 2]
            rgba[index + 1] = bgra[index + 1]
            rgba[index + 2] = bgra[index]
            rgba[index + 3] = bgra[index + 3]
        }
        return (width, height, rgba)
    }

    private func clearColor(_ color: RGBAColor) -> MTLClearColor {
        MTLClearColor(
            red: Double(color.r), green: Double(color.g), blue: Double(color.b),
            alpha: Double(color.a))
    }
}

public enum RendererError: Error, CustomStringConvertible {
    case noDevice
    case noCommandQueue
    case textureAllocation
    case missingFunction
    case shaderCompilation(String)
    case noCommandBuffer

    public var description: String {
        switch self {
        case .noDevice: return "no Metal device"
        case .noCommandQueue: return "could not create a Metal command queue"
        case .textureAllocation: return "could not allocate a Metal resource"
        case .missingFunction: return "a shader function is missing"
        case .shaderCompilation(let message): return "shader compilation failed: \(message)"
        case .noCommandBuffer: return "could not create a Metal command buffer"
        }
    }
}
