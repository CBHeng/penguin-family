/// 箱庭的鏡頭：決定畫面中央對著箱庭圖的哪一點（單位：像素）。
///
/// 只做數學，不碰畫面：限制在箱庭範圍內、對齊整個像素、慢慢靠近目標。
nonisolated struct RoomCamera: Equatable, Sendable {
    /// 箱庭圖的大小（像素）。
    let canvasWidth: Double
    let canvasHeight: Double
    /// 畫面看得到多大（像素）。
    let viewportWidth: Double
    let viewportHeight: Double
    /// 畫面中央對著的點（像素）。永遠在允許的範圍內。
    private(set) var centerX: Double
    private(set) var centerY: Double

    init(canvasWidth: Double, canvasHeight: Double, viewportWidth: Double, viewportHeight: Double,
         centerX: Double, centerY: Double) {
        self.canvasWidth = canvasWidth
        self.canvasHeight = canvasHeight
        self.viewportWidth = viewportWidth
        self.viewportHeight = viewportHeight
        self.centerX = 0
        self.centerY = 0
        moveTo(x: centerX, y: centerY)
    }

    /// 移到某一點；超出範圍時停在邊上。箱庭比畫面小的那個方向，固定在正中央。
    mutating func moveTo(x: Double, y: Double) {
        centerX = Self.clamp(x, canvas: canvasWidth, viewport: viewportWidth)
        centerY = Self.clamp(y, canvas: canvasHeight, viewport: viewportHeight)
    }

    /// 往目標靠近一步：每步走剩下距離的 `fraction`，很近時直接到位。回傳是否已經到了。
    @discardableResult
    mutating func approach(x: Double, y: Double, fraction: Double) -> Bool {
        let target = (Self.clamp(x, canvas: canvasWidth, viewport: viewportWidth),
                      Self.clamp(y, canvas: canvasHeight, viewport: viewportHeight))
        let dx = target.0 - centerX, dy = target.1 - centerY
        if abs(dx) < 0.5 && abs(dy) < 0.5 {
            moveTo(x: target.0, y: target.1)
            return true
        }
        moveTo(x: centerX + dx * fraction, y: centerY + dy * fraction)
        return false
    }

    /// 畫面左上角對著箱庭圖的哪個像素，取整數，讓所有像素對齊、移動時不閃。
    var topLeft: PixelPoint {
        PixelPoint(x: Int((centerX - viewportWidth / 2).rounded()), y: Int((centerY - viewportHeight / 2).rounded()))
    }

    private static func clamp(_ value: Double, canvas: Double, viewport: Double) -> Double {
        if canvas <= viewport { return canvas / 2 }
        return min(max(value, viewport / 2), canvas - viewport / 2)
    }
}
