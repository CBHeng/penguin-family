import Testing
@testable import PenguinFamily

/// 縮放的數學：範圍、吸附到整數個實體像素、手指下面那一點不動。
struct RoomZoomTests {
    /// iPhone 17 直拿：402pt 寬、@3x；屋內箱庭 384 像素寬。
    static let iPhone17 = RoomZoom(viewportWidth: 402, canvasWidth: 384, displayScale: 3)
    /// iPhone 11 直拿：414pt 寬、@2x。
    static let iPhone11 = RoomZoom(viewportWidth: 414, canvasWidth: 384, displayScale: 2)

    @Test func smallestFitsTheRoomWidthWithWholeScreenPixels() {
        // 1206 / 384 = 3.14 → 3 個實體像素 = 1pt，384pt 塞得進 402pt
        #expect(Self.iPhone17.minPointsPerPixel == 1)
        // 828 / 384 = 2.16 → 2 個實體像素 = 1pt
        #expect(Self.iPhone11.minPointsPerPixel == 1)
        // 橫拿 874pt @3x：2622 / 384 = 6.8 → 6 個實體像素 = 2pt
        #expect(RoomZoom(viewportWidth: 874, canvasWidth: 384, displayScale: 3).minPointsPerPixel == 2)
    }

    @Test func largestIsThreePoints() {
        #expect(Self.iPhone17.maxPointsPerPixel == 3)
        #expect(Self.iPhone17.clamped(10) == 3)
        #expect(Self.iPhone17.clamped(0.2) == 1)
        // 畫面寬到房間 3pt 也塞得下時，最小就是最大，不能縮放
        #expect(RoomZoom(viewportWidth: 1400, canvasWidth: 384, displayScale: 2).minPointsPerPixel == 3)
    }

    @Test func snapsToWholeScreenPixels() {
        // @3x 可以停在 1、4/3、5/3、2、7/3、8/3、3
        #expect(Self.iPhone17.snapped(1.4) == 4.0 / 3)
        #expect(Self.iPhone17.snapped(2.9) == 3)
        // @2x 可以停在 1、1.5、2、2.5、3
        #expect(Self.iPhone11.snapped(1.7) == 1.5)
        #expect(Self.iPhone11.snapped(2.3) == 2.5)
        #expect(Self.iPhone11.snapped(0.4) == 1)
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
