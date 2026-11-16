import MetalKit

/// 用 Metal 照 `RoomStage` 的清單把每一張圖畫出來（ADR 0006）。
///
/// - 所有圖在建立時一次全部送進 GPU（用首次載入換順暢），之後每一格只是照清單貼圖。
/// - 每張圖都放在同一個像素格子上；放大時取最近的像素，不做平滑處理。
/// - 顏色不經過轉換：貼圖存原始的 RGBA，畫面標成 sRGB，和調色盤一致。
final class SpriteRenderer: NSObject, MTKViewDelegate {
    /// 和 shader 的 `SpriteQuad` 對應，單位是螢幕實體像素。
    private struct SpriteQuad {
        var origin: SIMD2<Float>
        var size: SIMD2<Float>
        var viewport: SIMD2<Float>
    }

    private let stage: RoomStage
    private let commandQueue: MTLCommandQueue
    private let pipeline: MTLRenderPipelineState
    private let sampler: MTLSamplerState
    private let textures: [RoomStage.SpriteKey: MTLTexture]
    /// 貼圖佔多少記憶體（位元組）。
    let textureBytes: Int

    init?(device: MTLDevice, pixelFormat: MTLPixelFormat, stage: RoomStage) {
        guard let queue = device.makeCommandQueue(),
              let library = device.makeDefaultLibrary(),
              let vertex = library.makeFunction(name: "spriteVertex"),
              let fragment = library.makeFunction(name: "spriteFragment")
        else { return nil }

        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = vertex
        descriptor.fragmentFunction = fragment
        let color = descriptor.colorAttachments[0]!
        color.pixelFormat = pixelFormat
        // 圖的顏色已經乘過透明度（透明格全是 0），疊圖用「來源 + 底下 × (1 - 來源透明度)」
        color.isBlendingEnabled = true
        color.sourceRGBBlendFactor = .one
        color.sourceAlphaBlendFactor = .one
        color.destinationRGBBlendFactor = .oneMinusSourceAlpha
        color.destinationAlphaBlendFactor = .oneMinusSourceAlpha
        guard let pipeline = try? device.makeRenderPipelineState(descriptor: descriptor) else { return nil }

        let samplerDescriptor = MTLSamplerDescriptor()
        samplerDescriptor.minFilter = .nearest
        samplerDescriptor.magFilter = .nearest
        samplerDescriptor.sAddressMode = .clampToEdge
        samplerDescriptor.tAddressMode = .clampToEdge
        guard let sampler = device.makeSamplerState(descriptor: samplerDescriptor) else { return nil }

        var textures: [RoomStage.SpriteKey: MTLTexture] = [:]
        var bytes = 0
        for (key, bitmap) in stage.allBitmaps() {
            guard let texture = Self.makeTexture(bitmap, device: device) else { return nil }
            textures[key] = texture
            bytes += bitmap.byteCount
        }

        self.stage = stage
        self.commandQueue = queue
        self.pipeline = pipeline
        self.sampler = sampler
        self.textures = textures
        self.textureBytes = bytes
        super.init()
    }

    private static func makeTexture(_ bitmap: PixelBitmap, device: MTLDevice) -> MTLTexture? {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba8Unorm, width: bitmap.width, height: bitmap.height, mipmapped: false)
        descriptor.usage = .shaderRead
        guard let texture = device.makeTexture(descriptor: descriptor) else { return nil }
        bitmap.rgba.withUnsafeBytes { raw in
            texture.replace(region: MTLRegionMake2D(0, 0, bitmap.width, bitmap.height), mipmapLevel: 0,
                            withBytes: raw.baseAddress!, bytesPerRow: bitmap.width * 4)
        }
        return texture
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

    func draw(in view: MTKView) {
        guard let transform = stage.viewTransform, stage.viewport.width > 0,
              let pass = view.currentRenderPassDescriptor,
              let drawable = view.currentDrawable,
              let buffer = commandQueue.makeCommandBuffer(),
              let encoder = buffer.makeRenderCommandEncoder(descriptor: pass)
        else { return }

        let drawableSize = view.drawableSize
        // 一個箱庭像素等於幾個螢幕實體像素
        let devicePerPixel = transform.pointsPerPixel * drawableSize.width / stage.viewport.width
        let viewport = SIMD2<Float>(Float(drawableSize.width), Float(drawableSize.height))
        encoder.setRenderPipelineState(pipeline)
        encoder.setFragmentSamplerState(sampler, index: 0)
        for sprite in stage.sprites() {
            guard let texture = textures[sprite.key] else { continue }
            var quad = SpriteQuad(
                origin: SIMD2(Float((Double(sprite.x) - transform.topLeftX) * devicePerPixel),
                              Float((Double(sprite.y) - transform.topLeftY) * devicePerPixel)),
                size: SIMD2(Float(Double(sprite.width) * devicePerPixel), Float(Double(sprite.height) * devicePerPixel)),
                viewport: viewport)
            encoder.setVertexBytes(&quad, length: MemoryLayout<SpriteQuad>.stride, index: 0)
            encoder.setFragmentTexture(texture, index: 0)
            encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
        }
        encoder.endEncoding()
        buffer.present(drawable)
        buffer.commit()
    }
}
