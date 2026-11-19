/// 箱庭的縮放：每個單位畫成幾 pt。只做數學，不碰畫面。
///
/// 範圍（作者 2026-11-16 決定）：
/// - 最大：每個單位 3pt（遊戲設計的遠景大小）。
/// - 最小：房間左右剛好塞進畫面，上下留黑沒關係。
///
/// 捏合時連續縮放，放開後停在那個倍率；向量任何倍率都清楚，不用吸附（ADR 0007）。
nonisolated struct RoomZoom: Equatable, Sendable {
    static let maxPointsPerUnit: Double = 3

    let minPointsPerUnit: Double
    let maxPointsPerUnit: Double

    /// - Parameters:
    ///   - viewportWidth: 畫面寬（pt）。
    ///   - canvasWidth: 箱庭寬（單位）。
    init(viewportWidth: Double, canvasWidth: Double, maxPointsPerUnit: Double = RoomZoom.maxPointsPerUnit) {
        self.maxPointsPerUnit = maxPointsPerUnit
        // 房間左右剛好塞進畫面
        minPointsPerUnit = min(viewportWidth / canvasWidth, maxPointsPerUnit)
    }

    /// 限制在範圍內。
    func clamped(_ pointsPerUnit: Double) -> Double {
        min(max(pointsPerUnit, minPointsPerUnit), maxPointsPerUnit)
    }

    /// 縮放後的鏡頭中心（單位），讓手指下面那一點留在原地。
    ///
    /// - Parameters:
    ///   - anchor: 捏合開始時手指在畫面上的位置（pt，畫面左上角為原點）。
    ///   - center: 縮放前鏡頭中心（單位）。
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
