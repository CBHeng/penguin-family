/// 箱庭的縮放：每個箱庭像素畫成幾 pt。只做數學，不碰畫面。
///
/// 範圍（作者 2026-11-16 決定）：
/// - 最大：每個像素 3pt，也就是原本的固定大小。
/// - 最小：房間左右剛好塞進畫面，上下留黑沒關係。
///
/// 捏合時連續縮放；放開後吸附到「一個箱庭像素等於整數個螢幕實體像素」，讓每個像素一樣大。
/// 倍數不是整數時，有些像素會被畫得比旁邊寬一點。
nonisolated struct RoomZoom: Equatable, Sendable {
    static let maxPointsPerPixel: Double = 3

    /// 1pt 等於幾個螢幕實體像素（iPhone 17 是 3，iPhone 11 是 2）。
    let displayScale: Double
    let minPointsPerPixel: Double
    let maxPointsPerPixel: Double

    /// - Parameters:
    ///   - viewportWidth: 畫面寬（pt）。
    ///   - canvasWidth: 箱庭圖寬（箱庭像素）。
    init(viewportWidth: Double, canvasWidth: Double, displayScale: Double,
         maxPointsPerPixel: Double = RoomZoom.maxPointsPerPixel) {
        let scale = max(1, displayScale)
        self.displayScale = scale
        self.maxPointsPerPixel = maxPointsPerPixel
        // 房間塞得進畫面的最大整數倍（實體像素），至少 1 個實體像素
        let fit = max(1, (viewportWidth * scale / canvasWidth).rounded(.down)) / scale
        minPointsPerPixel = min(fit, maxPointsPerPixel)
    }

    /// 限制在範圍內，不取整（捏合中用）。
    func clamped(_ pointsPerPixel: Double) -> Double {
        min(max(pointsPerPixel, minPointsPerPixel), maxPointsPerPixel)
    }

    /// 吸附到最近的整數個實體像素，再限制在範圍內（放開後用）。上下限本身都是整數個實體像素。
    func snapped(_ pointsPerPixel: Double) -> Double {
        clamped((pointsPerPixel * displayScale).rounded() / displayScale)
    }

    /// 縮放後的鏡頭中心（箱庭像素），讓手指下面那一點留在原地。
    ///
    /// - Parameters:
    ///   - anchor: 捏合開始時手指在畫面上的位置（pt，畫面左上角為原點）。
    ///   - center: 縮放前鏡頭中心（箱庭像素）。
    ///   - viewport: 畫面大小（pt）。
    static func center(keeping anchor: (x: Double, y: Double), center: (x: Double, y: Double),
                       viewport: (width: Double, height: Double), from old: Double, to new: Double) -> (x: Double, y: Double) {
        func axis(_ a: Double, _ c: Double, _ v: Double) -> Double {
            let pointed = c - v / (2 * old) + a / old   // 手指下面是箱庭的哪一點
            return pointed - a / new + v / (2 * new)
        }
        return (axis(anchor.x, center.x, viewport.width), axis(anchor.y, center.y, viewport.height))
    }
}
