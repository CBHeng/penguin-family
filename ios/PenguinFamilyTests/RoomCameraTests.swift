import Testing
@testable import PenguinFamily

/// 鏡頭的數學：範圍限制、對齊像素、慢慢靠近。
struct RoomCameraTests {
    /// 和屋內一樣大的箱庭（384×256），畫面 134×291（iPhone 17 直拿，每個像素 3pt）。
    static func camera(x: Double, y: Double) -> RoomCamera {
        RoomCamera(canvasWidth: 384, canvasHeight: 256, viewportWidth: 134, viewportHeight: 291, centerX: x, centerY: y)
    }

    @Test func staysInsideTheRoomHorizontally() {
        #expect(Self.camera(x: 0, y: 0).centerX == 67)        // 左邊界：畫面一半寬
        #expect(Self.camera(x: 1000, y: 0).centerX == 317)    // 右邊界：384 - 67
        #expect(Self.camera(x: 200, y: 0).centerX == 200)
    }

    @Test func centersWhenRoomIsShorterThanScreen() {
        // 箱庭高 256，畫面高 291：上下固定置中，不能捲
        #expect(Self.camera(x: 200, y: 0).centerY == 128)
        #expect(Self.camera(x: 200, y: 999).centerY == 128)
    }

    @Test func topLeftSnapsToWholePixels() {
        var cam = Self.camera(x: 200, y: 0)
        cam.moveTo(x: 200.4, y: 0)
        #expect(cam.topLeft == PixelPoint(x: 133, y: -18))
        cam.moveTo(x: 200.6, y: 0)
        #expect(cam.topLeft == PixelPoint(x: 134, y: -18))
    }

    @Test func approachGetsCloserThenArrives() {
        var cam = Self.camera(x: 67, y: 0)
        let first = cam.approach(x: 300, y: 0, fraction: 0.1)
        #expect(!first)
        #expect(abs(cam.centerX - 90.3) < 0.0001)
        var steps = 1
        while !cam.approach(x: 300, y: 0, fraction: 0.1) { steps += 1 }
        #expect(cam.centerX == 300)
        #expect(steps < 100)
    }

    @Test func approachTargetIsClampedToo() {
        var cam = Self.camera(x: 200, y: 0)
        while !cam.approach(x: 9999, y: 0, fraction: 0.5) {}
        #expect(cam.centerX == 317)
    }
}
