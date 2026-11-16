import CoreGraphics
import Foundation

/// 把合成好的像素圖轉成原始尺寸的圖片；放大交給顯示層，而且不能做平滑處理。
nonisolated enum PixelImage {
    /// 每格 4 個位元組（R、G、B、A），由上而下、由左而右；透明格全是 0。
    static func rgba(_ grid: PixelGrid, colors: [Character: PixelColor]) -> [UInt8] {
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
        return bytes
    }

    static func cgImage(_ grid: PixelGrid, colors: [Character: PixelColor]) -> CGImage? {
        let bytes = rgba(grid, colors: colors)
        guard let provider = CGDataProvider(data: Data(bytes) as CFData),
              let space = CGColorSpace(name: CGColorSpace.sRGB)
        else { return nil }
        return CGImage(
            width: grid.width, height: grid.height,
            bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: grid.width * 4,
            space: space,
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
            provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
    }
}
