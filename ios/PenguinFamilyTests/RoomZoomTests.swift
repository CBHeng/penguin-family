import Testing
@testable import PenguinFamily

/// 縮放的數學：範圍、不吸附、手指下面那一點不動。
struct RoomZoomTests {
    /// iPhone 17 直拿：402pt 寬；屋內箱庭 384 個單位寬。
    static let iPhone17 = RoomZoom(viewportWidth: 402, canvasWidth: 384)

    @Test func smallestFitsTheRoomWidthExactly() {
        #expect(Self.iPhone17.minPointsPerUnit == 402.0 / 384)
        // 橫拿 874pt
        #expect(RoomZoom(viewportWidth: 874, canvasWidth: 384).minPointsPerUnit == 874.0 / 384)
    }

    @Test func largestIsThreePointsAndAnythingBetweenStays() {
        #expect(Self.iPhone17.maxPointsPerUnit == 3)
        #expect(Self.iPhone17.clamped(10) == 3)
        #expect(Self.iPhone17.clamped(0.2) == 402.0 / 384)
        #expect(Self.iPhone17.clamped(1.4) == 1.4)          // 向量任何倍率都清楚，不用吸附
        // 畫面寬到房間 3pt 也塞得下時，最小就是最大，不能縮放
        #expect(RoomZoom(viewportWidth: 1400, canvasWidth: 384).minPointsPerUnit == 3)
    }

    @Test func pointUnderFingerStaysPut() {
        let viewport = (width: 402.0, height: 874.0)
        let anchor = (x: 100.0, y: 300.0)
        let before = (x: 200.0, y: 128.0)
        let after = RoomZoom.center(keeping: anchor, center: before, viewport: viewport, from: 3, to: 1.5)
        // 手指下面的箱庭點，縮放前後相同
        func pointed(_ c: (x: Double, y: Double), _ ppp: Double) -> (Double, Double) {
            (c.x - viewport.width / (2 * ppp) + anchor.x / ppp, c.y - viewport.height / (2 * ppp) + anchor.y / ppp)
        }
        let (bx, by) = pointed(before, 3)
        let (ax, ay) = pointed(after, 1.5)
        #expect(abs(bx - ax) < 1e-9)
        #expect(abs(by - ay) < 1e-9)
    }

    @Test func pinchingAtScreenCenterKeepsTheCenter() {
        let after = RoomZoom.center(keeping: (201, 437), center: (200, 128), viewport: (402, 874), from: 3, to: 2)
        #expect(abs(after.x - 200) < 1e-9)
        #expect(abs(after.y - 128) < 1e-9)
    }
}
