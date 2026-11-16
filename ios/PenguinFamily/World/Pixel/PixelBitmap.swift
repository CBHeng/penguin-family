/// 原始尺寸的像素圖：每格 4 個位元組（R、G、B、A），由上而下、由左而右。
///
/// 直接送進 GPU 當貼圖，顏色不經過任何色彩轉換，所以一定和調色盤相同。放大交給繪圖層，而且不能做平滑處理。
nonisolated struct PixelBitmap: Equatable, Sendable {
    let width: Int
    let height: Int
    /// 透明格全是 0。
    let rgba: [UInt8]

    init(width: Int, height: Int, rgba: [UInt8]) {
        precondition(rgba.count == width * height * 4, "位元組數和寬高不合")
        self.width = width
        self.height = height
        self.rgba = rgba
    }

    /// 把調色盤代碼的格子轉成顏色。
    init(_ grid: PixelGrid, colors: [Character: PixelColor]) {
        var bytes = [UInt8](repeating: 0, count: grid.width * grid.height * 4)
        for y in 0..<grid.height {
            for x in 0..<grid.width {
                guard let code = grid[x, y], let color = colors[code] else { continue }
                let i = (y * grid.width + x) * 4
                bytes[i] = color.red
                bytes[i + 1] = color.green
                bytes[i + 2] = color.blue
                bytes[i + 3] = 255
            }
        }
        self.init(width: grid.width, height: grid.height, rgba: bytes)
    }

    /// 佔多少記憶體（位元組）。
    var byteCount: Int { rgba.count }
}
