import CoreGraphics

/// 畫好的圖：每個像素 4 個位元組（R、G、B、A，顏色已經乘過透明度），由上而下、由左而右。直接送進 GPU 當貼圖。
nonisolated struct RGBABitmap: Equatable, Sendable {
    let width: Int
    let height: Int
    let rgba: [UInt8]

    init(width: Int, height: Int, rgba: [UInt8]) {
        precondition(rgba.count == width * height * 4, "位元組數和寬高不合")
        self.width = width
        self.height = height
        self.rgba = rgba
    }

    /// 佔多少記憶體（位元組）。
    var byteCount: Int { rgba.count }
}

/// 把向量角色的部件畫成貼圖（ADR 0007）：載入時用 Core Graphics 畫一次，之後每一格在 Metal 轉動、縮放這些貼圖。
///
/// 每個部件畫兩張：
/// - 外框：外形用外框色填滿、再加粗描一圈。繪圖時先把整隻的外框都畫完，再畫顏色，部件重疊處才不會多出內線。
/// - 顏色：照順序畫每一層。
///
/// 解析度照最大倍率準備（`pixelsPerUnit` = 每單位最多幾 pt × 螢幕倍率），縮小時交給 mipmap。
/// 形狀一個一個分開畫，重疊的地方是聯集（和私有素材 repo 的 SVG 預覽一樣）；`clip` 每一組的形狀取聯集，組與組取交集。
/// 只畫畫好的方向；翻轉的方向（右前、右後）共用來源的貼圖，繪圖時才翻轉。
nonisolated enum VectorRasterizer {
    /// 一個部件的兩張圖。
    struct PartImages: Sendable {
        let name: String
        /// 圖蓋住的範圍（角色畫布的單位，整數）。
        let bounds: CGRect
        let outline: RGBABitmap
        let fill: RGBABitmap

        var byteCount: Int { outline.byteCount + fill.byteCount }
    }

    /// 某個方向的每個部件，依 `drawOrder`。
    static func rasterize(_ rig: VectorRig, facing name: String, pixelsPerUnit: Double) -> [PartImages] {
        guard let facing = rig.facings[name], let outlineColor = cgColor(rig.outline.color) else { return [] }
        return facing.drawOrder.compactMap { partName in
            guard let part = facing.parts[partName] else { return nil }
            let bounds = Self.bounds(of: part, outlineWidth: rig.outline.width)
            let outline = draw(bounds, pixelsPerUnit) { ctx in
                ctx.setFillColor(outlineColor)
                ctx.setStrokeColor(outlineColor)
                ctx.setLineWidth(rig.outline.width * 2)
                ctx.setLineJoin(.round)
                for shape in part.silhouette {
                    ctx.addPath(path(shape))
                    ctx.drawPath(using: .fillStroke)
                }
            }
            let fill = draw(bounds, pixelsPerUnit) { ctx in
                for layer in part.layers { drawLayer(layer, in: ctx, bounds: bounds, pixelsPerUnit: pixelsPerUnit) }
            }
            return PartImages(name: partName, bounds: bounds, outline: outline, fill: fill)
        }
    }

    /// 某個角色所有畫好的方向的部件貼圖共佔多少位元組：每個部件外框、顏色兩張，加上 mipmap 約多 1/3。
    /// 只用範圍算，不用真的畫；和 `rasterize` 畫出來的圖一樣大，繪圖層也照同樣的算法記錄用量。
    static func textureBytes(_ rig: VectorRig, pixelsPerUnit: Double) -> Int {
        rig.facings.values.reduce(0) { total, facing in
            facing.parts.values.reduce(total) { total, part in
                let size = pixelSize(bounds(of: part, outlineWidth: rig.outline.width), pixelsPerUnit)
                return total + size.width * size.height * 4 * 2 * 4 / 3
            }
        }
    }

    /// 部件所有形狀的外接矩形，加上外框、描線寬度與 1 單位的抗鋸齒邊，取到整數單位。
    static func bounds(of part: VectorRig.Part, outlineWidth: Double) -> CGRect {
        var minX = Double.infinity, minY = Double.infinity, maxX = -Double.infinity, maxY = -Double.infinity
        func include(_ shapes: [VectorRig.Shape], pad: Double) {
            for shape in shapes {
                let b = shape.bounds
                minX = min(minX, b.minX - pad); minY = min(minY, b.minY - pad)
                maxX = max(maxX, b.maxX + pad); maxY = max(maxY, b.maxY + pad)
            }
        }
        include(part.silhouette, pad: outlineWidth)
        for layer in part.layers { include(layer.shapes, pad: (layer.width ?? 0) / 2) }
        let x0 = (minX - 1).rounded(.down), y0 = (minY - 1).rounded(.down)
        let x1 = (maxX + 1).rounded(.up), y1 = (maxY + 1).rounded(.up)
        return CGRect(x: x0, y: y0, width: x1 - x0, height: y1 - y0)
    }

    // MARK: - 畫圖

    private static let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!

    /// 一個部件的圖有幾個像素寬、高。
    private static func pixelSize(_ bounds: CGRect, _ pixelsPerUnit: Double) -> (width: Int, height: Int) {
        (Int((bounds.width * pixelsPerUnit).rounded(.up)), Int((bounds.height * pixelsPerUnit).rounded(.up)))
    }

    /// 開一張透明的圖，座標換成「角色畫布的單位、y 往下」再畫；回傳預乘透明度的 RGBA，由上而下。
    private static func draw(_ bounds: CGRect, _ pixelsPerUnit: Double, _ body: (CGContext) -> Void) -> RGBABitmap {
        let (width, height) = pixelSize(bounds, pixelsPerUnit)
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        bytes.withUnsafeMutableBytes { raw in
            guard let ctx = CGContext(data: raw.baseAddress, width: width, height: height, bitsPerComponent: 8,
                                      bytesPerRow: width * 4, space: colorSpace,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return }
            ctx.translateBy(x: 0, y: CGFloat(height))
            ctx.scaleBy(x: pixelsPerUnit, y: -pixelsPerUnit)
            ctx.translateBy(x: -bounds.minX, y: -bounds.minY)
            body(ctx)
        }
        return RGBABitmap(width: width, height: height, rgba: bytes)
    }

    private static func drawLayer(_ layer: VectorRig.Layer, in ctx: CGContext, bounds: CGRect, pixelsPerUnit: Double) {
        ctx.saveGState()
        defer { ctx.restoreGState() }
        // 每一組裁切各做一張遮罩，依序套上去（裁切範圍取交集）。遮罩是由上而下的點陣圖：回到裝置座標套上去，再換回單位座標
        for group in layer.clip ?? [] {
            guard let mask = mask(group, bounds: bounds, pixelsPerUnit: pixelsPerUnit) else { continue }
            let units = ctx.ctm
            ctx.concatenate(units.inverted())
            ctx.clip(to: CGRect(x: 0, y: 0, width: mask.width, height: mask.height), mask: mask)
            ctx.concatenate(units)
        }
        if let fill = layer.fill, let color = cgColor(fill) {
            ctx.setFillColor(color)
            for shape in layer.shapes {
                ctx.addPath(path(shape))
                ctx.fillPath()
            }
        } else if let stroke = layer.stroke, let width = layer.width, let color = cgColor(stroke) {
            ctx.setStrokeColor(color)
            ctx.setLineWidth(width)
            ctx.setLineCap(.round)
            ctx.setLineJoin(.round)
            for shape in layer.shapes {
                ctx.addPath(path(shape))
                ctx.strokePath()
            }
        }
    }

    /// 裁切範圍：每個形狀分開填白，取聯集。
    private static func mask(_ shapes: [VectorRig.Shape], bounds: CGRect, pixelsPerUnit: Double) -> CGImage? {
        let (width, height) = pixelSize(bounds, pixelsPerUnit)
        guard let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width,
                                  space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue)
        else { return nil }
        ctx.translateBy(x: 0, y: CGFloat(height))
        ctx.scaleBy(x: pixelsPerUnit, y: -pixelsPerUnit)
        ctx.translateBy(x: -bounds.minX, y: -bounds.minY)
        ctx.setFillColor(gray: 1, alpha: 1)
        for shape in shapes {
            ctx.addPath(path(shape))
            ctx.fillPath()
        }
        return ctx.makeImage()
    }

    static func path(_ shape: VectorRig.Shape) -> CGPath {
        switch shape {
        case let .ellipse(cx, cy, rx, ry):
            return CGPath(ellipseIn: CGRect(x: cx - rx, y: cy - ry, width: rx * 2, height: ry * 2), transform: nil)
        case .path(let commands):
            let p = CGMutablePath()
            for command in commands {
                switch command {
                case let .move(x, y): p.move(to: CGPoint(x: x, y: y))
                case let .line(x, y): p.addLine(to: CGPoint(x: x, y: y))
                case let .curve(x1, y1, x2, y2, x, y):
                    p.addCurve(to: CGPoint(x: x, y: y), control1: CGPoint(x: x1, y: y1), control2: CGPoint(x: x2, y: y2))
                case .close: p.closeSubpath()
                }
            }
            return p
        }
    }

    private static func cgColor(_ hex: String) -> CGColor? {
        guard let c = RGBColor(hex: hex) else { return nil }
        return CGColor(colorSpace: colorSpace, components: [CGFloat(c.red) / 255, CGFloat(c.green) / 255, CGFloat(c.blue) / 255, 1])
    }
}
