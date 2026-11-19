import MetalKit
import os

/// 用 Metal 照 `RoomStage` 的清單把每一樣東西畫出來（ADR 0006、0007）。
///
/// - 箱庭（牆、地板、家具）是多邊形：載入時切成三角形放進一個緩衝區，之後每一格只指定畫哪一段。
/// - 向量企鵝：載入時把每個畫好的方向的每個部件畫成兩張貼圖（外框、顏色，見 `VectorRasterizer`），每一格依姿勢把貼圖轉到畫面上；
///   先畫整隻的外框，再畫顏色。貼圖照抱抱近景的倍率準備，縮小時用 mipmap。右前、右後翻轉左邊的貼圖，不另外準備。
/// - 像素圖（灰色剪影，和沒有向量造型的角色；A1 第 10 項拿掉）：取最近的像素，左上角對齊實體像素。
/// - 邊緣用 4 倍多重取樣抗鋸齒；多重取樣的畫布只在 GPU 晶片上（memoryless），不佔記憶體。
/// - 顏色不經過轉換：貼圖與頂點顏色都是 sRGB 的數值，畫面標成 sRGB。
final class SpriteRenderer: NSObject, MTKViewDelegate {
    /// 向量部件的貼圖準備到每單位幾 pt：抱抱近景最大 8pt（遊戲設計：6～8pt，實機上調）。
    static let vectorMaxPointsPerUnit = 8.0

    /// 向量部件的貼圖每單位幾個實體像素（`displayScale` 是 1pt 幾個實體像素）。
    static func vectorPixelsPerUnit(displayScale: Double) -> Double {
        vectorMaxPointsPerUnit * max(1, displayScale)
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
        let outline: MTLTexture
        let fill: MTLTexture
    }

    private static let log = Logger(subsystem: "PenguinFamily", category: "Render")

    private let stage: RoomStage
    private let device: MTLDevice
    private let pixelFormat: MTLPixelFormat
    private let commandQueue: MTLCommandQueue
    private let quadPipeline: MTLRenderPipelineState
    private let polygonPipeline: MTLRenderPipelineState
    private let nearest: MTLSamplerState
    private let smooth: MTLSamplerState
    private let textures: [RoomStage.SpriteKey: MTLTexture]
    private let polygonBuffer: MTLBuffer?
    /// 每一組多邊形在緩衝區裡是第幾個頂點到第幾個。
    private let polygonRanges: [RoomStage.SpriteKey: Range<Int>]
    private let vectorRigs: [PenguinID: VectorRig]
    /// 每一隻、每個畫好的方向、每個部件的貼圖。
    private let vectorParts: [PenguinID: [String: [String: VectorPart]]]
    private var multisample: MTLTexture?
    /// 貼圖佔多少記憶體（位元組，含 mipmap）。
    let textureBytes: Int

    /// - Parameter displayScale: 1pt 幾個實體像素，決定向量部件的貼圖解析度。
    init?(device: MTLDevice, pixelFormat: MTLPixelFormat, stage: RoomStage, displayScale: Double) {
        guard let queue = device.makeCommandQueue(),
              let library = device.makeDefaultLibrary(),
              let quadPipeline = Self.pipeline(device, library, pixelFormat, "quadVertex", "quadFragment"),
              let polygonPipeline = Self.pipeline(device, library, pixelFormat, "polygonVertex", "polygonFragment"),
              let nearest = Self.sampler(device, smooth: false),
              let smooth = Self.sampler(device, smooth: true)
        else { return nil }

        var bytes = 0
        var textures: [RoomStage.SpriteKey: MTLTexture] = [:]
        for (key, bitmap) in stage.allBitmaps() {
            guard let texture = Self.makeTexture(bitmap, device: device, mipmapped: false) else { return nil }
            textures[key] = texture
            bytes += bitmap.byteCount
        }

        // 箱庭：每塊凸多邊形用扇形切成三角形
        var vertices: [PolygonVertex] = []
        var ranges: [RoomStage.SpriteKey: Range<Int>] = [:]
        for (key, polygons) in stage.polygons() {
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

        // 向量企鵝：部件畫成貼圖，產生 mipmap
        let rigs = stage.vectorRigs()
        var parts: [PenguinID: [String: [String: VectorPart]]] = [:]
        let pixelsPerUnit = Self.vectorPixelsPerUnit(displayScale: displayScale)
        let rasterize = PerfSignposts.signposter.beginInterval("rasterize")
        if !rigs.isEmpty, let mipmaps = queue.makeCommandBuffer(), let blit = mipmaps.makeBlitCommandEncoder() {
            for (id, rig) in rigs {
                for facing in rig.facings.keys {
                    var list: [String: VectorPart] = [:]
                    for images in VectorRasterizer.rasterize(rig, facing: facing, pixelsPerUnit: pixelsPerUnit) {
                        guard let outline = Self.makeTexture(images.outline, device: device, mipmapped: true),
                              let fill = Self.makeTexture(images.fill, device: device, mipmapped: true) else { continue }
                        blit.generateMipmaps(for: outline)
                        blit.generateMipmaps(for: fill)
                        list[images.name] = VectorPart(name: images.name, bounds: images.bounds, outline: outline, fill: fill)
                        bytes += images.byteCount * 4 / 3
                    }
                    parts[id, default: [:]][facing] = list
                }
            }
            blit.endEncoding()
            mipmaps.commit()
            mipmaps.waitUntilCompleted()
        }
        PerfSignposts.signposter.endInterval("rasterize", rasterize)
        Self.log.info("textures \(bytes / 1024) KB, polygon vertices \(vertices.count)")

        self.stage = stage
        self.device = device
        self.pixelFormat = pixelFormat
        self.commandQueue = queue
        self.quadPipeline = quadPipeline
        self.polygonPipeline = polygonPipeline
        self.nearest = nearest
        self.smooth = smooth
        self.textures = textures
        self.polygonBuffer = polygonBuffer
        self.polygonRanges = ranges
        self.vectorRigs = rigs
        self.vectorParts = parts
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

    private static func sampler(_ device: MTLDevice, smooth: Bool) -> MTLSamplerState? {
        let d = MTLSamplerDescriptor()
        d.minFilter = smooth ? .linear : .nearest
        d.magFilter = smooth ? .linear : .nearest
        d.mipFilter = smooth ? .linear : .notMipmapped
        d.sAddressMode = .clampToEdge
        d.tAddressMode = .clampToEdge
        return device.makeSamplerState(descriptor: d)
    }

    private static func makeTexture(_ bitmap: PixelBitmap, device: MTLDevice, mipmapped: Bool) -> MTLTexture? {
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
        guard let transform = stage.viewTransform, stage.viewport.width > 0 else { return }
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

        // 一個單位等於幾個螢幕實體像素
        let devicePerUnit = transform.pointsPerPixel * size.width / stage.viewport.width
        let viewport = SIMD2<Float>(Float(size.width), Float(size.height))
        func onScreen(_ x: Double, _ y: Double) -> SIMD2<Float> {
            SIMD2(Float((x - transform.topLeftX) * devicePerUnit), Float((y - transform.topLeftY) * devicePerUnit))
        }
        var polygonUniforms = PolygonUniforms(topLeft: SIMD2(Float(transform.topLeftX), Float(transform.topLeftY)),
                                              viewport: viewport, devicePerUnit: Float(devicePerUnit))

        let encode = PerfSignposts.signposter.beginInterval("encode")
        defer { PerfSignposts.signposter.endInterval("encode", encode) }
        for sprite in stage.sprites() {
            switch sprite.key {
            case .background, .furniture:
                guard let polygonBuffer, let range = polygonRanges[sprite.key], !range.isEmpty else { continue }
                encoder.setRenderPipelineState(polygonPipeline)
                encoder.setVertexBuffer(polygonBuffer, offset: 0, index: 0)
                encoder.setVertexBytes(&polygonUniforms, length: MemoryLayout<PolygonUniforms>.stride, index: 1)
                encoder.drawPrimitives(type: .triangle, vertexStart: range.lowerBound, vertexCount: range.count)
            case .penguinVector(let id):
                guard let pose = sprite.vector, let frame = vectorRigs[id]?.frame(pose),
                      let parts = vectorParts[id]?[frame.look.source] else { continue }
                encoder.setRenderPipelineState(quadPipeline)
                encoder.setFragmentSamplerState(smooth, index: 0)
                // 先畫整隻的外框，再畫顏色：部件重疊處才不會多出內線。翻轉的方向用來源的貼圖，矩陣裡已經翻好
                for outline in [true, false] {
                    for name in frame.look.drawOrder {
                        guard let part = parts[name] else { continue }
                        let t = frame.transforms[name] ?? .identity
                        let b = part.bounds
                        let corners = [(b.minX, b.minY), (b.maxX, b.minY), (b.minX, b.maxY), (b.maxX, b.maxY)].map { corner in
                            let p = t.apply(corner.0, corner.1)
                            return onScreen(sprite.x + p.x, sprite.y + p.y)
                        }
                        drawQuad(encoder, corners, viewport, outline ? part.outline : part.fill)
                    }
                }
            default:
                guard let texture = textures[sprite.key] else { continue }
                encoder.setRenderPipelineState(quadPipeline)
                encoder.setFragmentSamplerState(nearest, index: 0)
                // 像素圖：左上角對齊實體像素，每格才一樣大
                let origin = onScreen(sprite.x, sprite.y).rounded(.toNearestOrAwayFromZero)
                let w = Float(sprite.width * devicePerUnit), h = Float(sprite.height * devicePerUnit)
                drawQuad(encoder, [origin, origin + SIMD2(w, 0), origin + SIMD2(0, h), origin + SIMD2(w, h)], viewport, texture)
            }
        }
        encoder.endEncoding()
        buffer.present(drawable)
        buffer.commit()
    }

    private func drawQuad(_ encoder: MTLRenderCommandEncoder, _ corners: [SIMD2<Float>], _ viewport: SIMD2<Float>,
                          _ texture: MTLTexture) {
        var quad = QuadUniforms(c0: corners[0], c1: corners[1], c2: corners[2], c3: corners[3], viewport: viewport)
        encoder.setVertexBytes(&quad, length: MemoryLayout<QuadUniforms>.stride, index: 0)
        encoder.setFragmentTexture(texture, index: 0)
        encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
    }
}
