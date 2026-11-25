import MetalKit
import os

/// 用 Metal 照繪製清單（`DrawList`）把每一樣東西畫出來（ADR 0006、0007、0008）。
///
/// 只畫：不算姿勢、不排序、不讀模擬。姿勢、前後順序、鏡頭都由畫面準備（`FrameBuilder`）算好放在清單裡。
/// - 箱庭（牆、地板、家具）是多邊形：載入時切成三角形放進一個緩衝區，之後每一格只指定畫哪一段。
/// - 角色：載入時把每個畫好的方向的每個部件畫成兩張貼圖（外框、顏色，見 `VectorRasterizer`），每一格照清單裡每個部件的矩陣
///   把貼圖的四個角放到畫面上；先畫整隻的外框，再畫顏色。貼圖照抱抱近景的倍率準備（螢幕倍率最多算到 2），縮小時用 mipmap。
///   右前、右後翻轉左邊的貼圖，不另外準備（矩陣裡已經翻好）。外形是空的部件（例如眼睛）沒有外框那一張。
/// - 共用特效（ADR 0010，例如 Z、泡泡）：載入時把每個形狀畫成一張貼圖，照清單的矩陣放、乘上透明度。
/// - 邊緣用 4 倍多重取樣抗鋸齒；多重取樣的畫布只在 GPU 晶片上（memoryless），不佔記憶體。
/// - 顏色不經過轉換：貼圖與頂點顏色都是 sRGB 的數值，畫面標成 sRGB。
final class SpriteRenderer: NSObject, MTKViewDelegate {
    /// 向量部件的貼圖準備到每單位幾 pt：抱抱近景最大 8pt（遊戲設計：6～8pt，實機上調）。
    static let vectorMaxPointsPerUnit = 8.0

    /// 貼圖最多照螢幕幾倍準備（作者 2026-11-19 決定）：3 倍螢幕也照 2 倍，每支手機的貼圖一樣大。
    /// 箱庭最多放大到每單位 3pt，3 倍螢幕只要 9 個像素，2 倍的貼圖（16 個）綽綽有餘；
    /// 抱抱近景（8pt）在 3 倍螢幕要 24 個，到時候會稍微糊，做抱抱時在實機上看過再決定。
    static let maxTextureScale = 2.0

    /// 向量部件的貼圖每單位幾個實體像素（`displayScale` 是 1pt 幾個實體像素，超過 `maxTextureScale` 的照它算）。
    static func vectorPixelsPerUnit(displayScale: Double) -> Double {
        vectorMaxPointsPerUnit * min(max(1, displayScale), maxTextureScale)
    }

    static let sampleCount = 4

    /// 和 shader 的 `QuadUniforms` 對應：四個角（左上、右上、左下、右下）與畫面大小，單位是螢幕實體像素。
    private struct QuadUniforms {
        var c0: SIMD2<Float>, c1: SIMD2<Float>, c2: SIMD2<Float>, c3: SIMD2<Float>
        var viewport: SIMD2<Float>
    }

    /// 和 shader 的 `PolygonVertex` 對應。
    private struct PolygonVertex {
        var position: SIMD2<Float>
        var color: SIMD4<Float>
    }

    /// 和 shader 的 `PolygonUniforms` 對應。
    private struct PolygonUniforms {
        var topLeft: SIMD2<Float>
        var viewport: SIMD2<Float>
        var devicePerUnit: Float
    }

    private struct VectorPart {
        let name: String
        let bounds: CGRect
        /// 外形是空的部件沒有（ADR 0010）。
        let outline: MTLTexture?
        let fill: MTLTexture
    }

    private static let log = Logger(subsystem: "PenguinFamily", category: "Render")

    /// 這一格要畫的東西；遊戲迴圈換新的清單後呼叫 `MTKView.draw()`。
    var drawList: DrawList?
    private let device: MTLDevice
    private let pixelFormat: MTLPixelFormat
    private let commandQueue: MTLCommandQueue
    private let quadPipeline: MTLRenderPipelineState
    private let polygonPipeline: MTLRenderPipelineState
    private let smooth: MTLSamplerState
    private let polygonBuffer: MTLBuffer?
    /// 每一組多邊形在緩衝區裡是第幾個頂點到第幾個。
    private let polygonRanges: [DrawKey: Range<Int>]
    /// 每一隻、每個畫好的方向或姿勢、每個部件的貼圖。
    private let vectorParts: [CharacterID: [String: [String: VectorPart]]]
    /// 每一隻、每個有影子的造型的影子（ADR 0011）。
    private let vectorShadows: [CharacterID: [String: VectorPart]]
    /// 共用特效的貼圖，依名稱。
    private let effectParts: [String: VectorPart]
    private var multisample: MTLTexture?
    /// 貼圖佔多少記憶體（位元組，含 mipmap）。
    let textureBytes: Int

    /// - Parameters:
    ///   - polygons: 箱庭的多邊形（背景與每件家具）。
    ///   - rigs: 後台名單每一隻的造型，包含還沒上台的。
    ///   - effects: 共用特效的形狀。
    ///   - displayScale: 1pt 幾個實體像素，決定向量部件的貼圖解析度。
    init?(device: MTLDevice, pixelFormat: MTLPixelFormat, polygons: [DrawKey: [ColoredPolygon]],
          rigs: [CharacterID: VectorRig], effects: EffectLibrary = .empty, displayScale: Double) {
        guard let queue = device.makeCommandQueue(),
              let library = device.makeDefaultLibrary(),
              let quadPipeline = Self.pipeline(device, library, pixelFormat, "quadVertex", "quadFragment"),
              let polygonPipeline = Self.pipeline(device, library, pixelFormat, "polygonVertex", "polygonFragment"),
              let smooth = Self.sampler(device)
        else { return nil }
        var bytes = 0

        // 箱庭：每塊凸多邊形用扇形切成三角形
        var vertices: [PolygonVertex] = []
        var ranges: [DrawKey: Range<Int>] = [:]
        for (key, polygons) in polygons {
            let start = vertices.count
            for polygon in polygons where polygon.points.count >= 3 {
                let c = polygon.color
                let color = SIMD4<Float>(Float(c.red) / 255, Float(c.green) / 255, Float(c.blue) / 255, 1)
                let p = polygon.points.map { SIMD2<Float>(Float($0.x), Float($0.y)) }
                for i in 1..<(p.count - 1) {
                    vertices += [PolygonVertex(position: p[0], color: color), PolygonVertex(position: p[i], color: color),
                                 PolygonVertex(position: p[i + 1], color: color)]
                }
            }
            ranges[key] = start..<vertices.count
        }
        let polygonBuffer = vertices.isEmpty ? nil : device.makeBuffer(
            bytes: vertices, length: vertices.count * MemoryLayout<PolygonVertex>.stride, options: .storageModeShared)

        // 角色：部件畫成貼圖，產生 mipmap；共用特效也一樣
        var parts: [CharacterID: [String: [String: VectorPart]]] = [:]
        var shadows: [CharacterID: [String: VectorPart]] = [:]
        var effectParts: [String: VectorPart] = [:]
        let pixelsPerUnit = Self.vectorPixelsPerUnit(displayScale: displayScale)
        let rasterize = PerfSignposts.signposter.beginInterval("rasterize")
        if !rigs.isEmpty || !effects.effects.isEmpty,
           let mipmaps = queue.makeCommandBuffer(), let blit = mipmaps.makeBlitCommandEncoder() {
            func upload(_ images: VectorRasterizer.PartImages) -> VectorPart? {
                guard let fill = Self.makeTexture(images.fill, device: device, mipmapped: true) else { return nil }
                var outline: MTLTexture?
                if let bitmap = images.outline {
                    guard let texture = Self.makeTexture(bitmap, device: device, mipmapped: true) else { return nil }
                    blit.generateMipmaps(for: texture)
                    outline = texture
                }
                blit.generateMipmaps(for: fill)
                bytes += images.byteCount * 4 / 3
                return VectorPart(name: images.name, bounds: images.bounds, outline: outline, fill: fill)
            }
            for (id, rig) in rigs {
                for facing in Array(rig.facings.keys) + Array(rig.postures.keys) {
                    var list: [String: VectorPart] = [:]
                    for images in VectorRasterizer.rasterize(rig, facing: facing, pixelsPerUnit: pixelsPerUnit) {
                        list[images.name] = upload(images)
                    }
                    parts[id, default: [:]][facing] = list
                    if let images = VectorRasterizer.rasterizeShadow(rig, facing: facing, pixelsPerUnit: pixelsPerUnit) {
                        shadows[id, default: [:]][facing] = upload(images)
                    }
                }
            }
            for (name, effect) in effects.effects {
                guard let images = VectorRasterizer.rasterizeEffect(effect, name: name, pixelsPerUnit: pixelsPerUnit) else { continue }
                effectParts[name] = upload(images)
            }
            blit.endEncoding()
            mipmaps.commit()
            mipmaps.waitUntilCompleted()
        }
        PerfSignposts.signposter.endInterval("rasterize", rasterize)
        Self.log.info("textures \(bytes / 1024) KB, polygon vertices \(vertices.count)")

        self.device = device
        self.pixelFormat = pixelFormat
        self.commandQueue = queue
        self.quadPipeline = quadPipeline
        self.polygonPipeline = polygonPipeline
        self.smooth = smooth
        self.polygonBuffer = polygonBuffer
        self.polygonRanges = ranges
        self.vectorParts = parts
        self.vectorShadows = shadows
        self.effectParts = effectParts
        self.textureBytes = bytes
        super.init()
    }

    private static func pipeline(_ device: MTLDevice, _ library: MTLLibrary, _ pixelFormat: MTLPixelFormat,
                                 _ vertex: String, _ fragment: String) -> MTLRenderPipelineState? {
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = library.makeFunction(name: vertex)
        descriptor.fragmentFunction = library.makeFunction(name: fragment)
        descriptor.rasterSampleCount = sampleCount
        let color = descriptor.colorAttachments[0]!
        color.pixelFormat = pixelFormat
        // 顏色已經乘過透明度，疊圖用「來源 + 底下 × (1 - 來源透明度)」
        color.isBlendingEnabled = true
        color.sourceRGBBlendFactor = .one
        color.sourceAlphaBlendFactor = .one
        color.destinationRGBBlendFactor = .oneMinusSourceAlpha
        color.destinationAlphaBlendFactor = .oneMinusSourceAlpha
        return try? device.makeRenderPipelineState(descriptor: descriptor)
    }

    /// 線性取樣加 mipmap：部件轉動、縮放時邊緣平滑。
    private static func sampler(_ device: MTLDevice) -> MTLSamplerState? {
        let d = MTLSamplerDescriptor()
        d.minFilter = .linear
        d.magFilter = .linear
        d.mipFilter = .linear
        d.sAddressMode = .clampToEdge
        d.tAddressMode = .clampToEdge
        return device.makeSamplerState(descriptor: d)
    }

    private static func makeTexture(_ bitmap: RGBABitmap, device: MTLDevice, mipmapped: Bool) -> MTLTexture? {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba8Unorm, width: bitmap.width, height: bitmap.height, mipmapped: mipmapped)
        descriptor.usage = .shaderRead
        guard let texture = device.makeTexture(descriptor: descriptor) else { return nil }
        bitmap.rgba.withUnsafeBytes { raw in
            texture.replace(region: MTLRegionMake2D(0, 0, bitmap.width, bitmap.height), mipmapLevel: 0,
                            withBytes: raw.baseAddress!, bytesPerRow: bitmap.width * 4)
        }
        return texture
    }

    /// 多重取樣的畫布，大小跟著畫面；實機上只在 GPU 晶片上（memoryless），模擬器不支援時改放顯示記憶體。
    private func multisampleTexture(width: Int, height: Int) -> MTLTexture? {
        if let multisample, multisample.width == width, multisample.height == height { return multisample }
        let d = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: pixelFormat, width: width, height: height, mipmapped: false)
        d.textureType = .type2DMultisample
        d.sampleCount = Self.sampleCount
        d.usage = .renderTarget
        #if targetEnvironment(simulator)
        d.storageMode = .private
        #else
        d.storageMode = .memoryless
        #endif
        multisample = device.makeTexture(descriptor: d)
        return multisample
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

    func draw(in view: MTKView) {
        guard let list = drawList, list.viewportWidth > 0 else { return }
        let size = view.drawableSize
        // 要畫布：沒有空的畫布時會在這裡等（量這一步，追偶發的變慢）
        let drawable = PerfSignposts.measure("acquireDrawable") { view.currentDrawable }
        guard let drawable, let target = multisampleTexture(width: Int(size.width), height: Int(size.height)),
              let buffer = commandQueue.makeCommandBuffer() else { return }
        let pass = MTLRenderPassDescriptor()
        let attachment = pass.colorAttachments[0]!
        attachment.texture = target
        attachment.resolveTexture = drawable.texture
        attachment.loadAction = .clear
        attachment.clearColor = view.clearColor
        attachment.storeAction = .multisampleResolve
        guard let encoder = buffer.makeRenderCommandEncoder(descriptor: pass) else { return }

        // 清單用畫面上的 pt；1pt 等於幾個螢幕實體像素
        let pixelsPerPoint = size.width / list.viewportWidth
        let viewport = SIMD2<Float>(Float(size.width), Float(size.height))
        var polygonUniforms = PolygonUniforms(topLeft: SIMD2(Float(list.topLeftX), Float(list.topLeftY)), viewport: viewport,
                                              devicePerUnit: Float(list.pointsPerUnit * pixelsPerPoint))

        let encode = PerfSignposts.signposter.beginInterval("encode")
        defer { PerfSignposts.signposter.endInterval("encode", encode) }
        for item in list.items {
            switch item {
            case .polygons(let key):
                guard let polygonBuffer, let range = polygonRanges[key], !range.isEmpty else { continue }
                encoder.setRenderPipelineState(polygonPipeline)
                encoder.setVertexBuffer(polygonBuffer, offset: 0, index: 0)
                encoder.setVertexBytes(&polygonUniforms, length: MemoryLayout<PolygonUniforms>.stride, index: 1)
                encoder.drawPrimitives(type: .triangle, vertexStart: range.lowerBound, vertexCount: range.count)
            case .shadow(let id, let look, let transform, let alpha):
                guard let texture = vectorShadows[id]?[look] else { continue }
                encoder.setRenderPipelineState(quadPipeline)
                encoder.setFragmentSamplerState(smooth, index: 0)
                drawQuad(encoder, corners(texture.bounds, transform, pixelsPerPoint), viewport, texture.fill, alpha: Float(alpha))
            case .character(let id, let look, let parts):
                guard let textures = vectorParts[id]?[look] else { continue }
                encoder.setRenderPipelineState(quadPipeline)
                encoder.setFragmentSamplerState(smooth, index: 0)
                // 先畫整隻的外框，再畫顏色：部件重疊處才不會多出內線
                for outline in [true, false] {
                    for part in parts {
                        guard let texture = textures[part.name],
                              let image = outline ? texture.outline : texture.fill else { continue }
                        drawQuad(encoder, corners(texture.bounds, part.transform, pixelsPerPoint), viewport, image, alpha: 1)
                    }
                }
            case .effect(let name, let transform, let alpha):
                guard let texture = effectParts[name], alpha > 0 else { continue }
                encoder.setRenderPipelineState(quadPipeline)
                encoder.setFragmentSamplerState(smooth, index: 0)
                drawQuad(encoder, corners(texture.bounds, transform, pixelsPerPoint), viewport, texture.fill, alpha: Float(alpha))
            }
        }
        encoder.endEncoding()
        buffer.present(drawable)
        buffer.commit()
    }

    /// 貼圖的四個角（左上、右上、左下、右下）照矩陣放到畫面上，單位是螢幕實體像素。
    private func corners(_ b: CGRect, _ transform: Affine2D, _ pixelsPerPoint: Double) -> [SIMD2<Float>] {
        [(b.minX, b.minY), (b.maxX, b.minY), (b.minX, b.maxY), (b.maxX, b.maxY)].map { corner in
            let p = transform.apply(corner.0, corner.1)
            return SIMD2<Float>(Float(p.x * pixelsPerPoint), Float(p.y * pixelsPerPoint))
        }
    }

    /// `alpha` 是整張圖再乘上的透明度（特效淡入淡出、影子用；角色是 1）。
    private func drawQuad(_ encoder: MTLRenderCommandEncoder, _ corners: [SIMD2<Float>], _ viewport: SIMD2<Float>,
                          _ texture: MTLTexture, alpha: Float) {
        var quad = QuadUniforms(c0: corners[0], c1: corners[1], c2: corners[2], c3: corners[3], viewport: viewport)
        var alpha = alpha
        encoder.setVertexBytes(&quad, length: MemoryLayout<QuadUniforms>.stride, index: 0)
        encoder.setFragmentBytes(&alpha, length: MemoryLayout<Float>.stride, index: 0)
        encoder.setFragmentTexture(texture, index: 0)
        encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
    }
}
