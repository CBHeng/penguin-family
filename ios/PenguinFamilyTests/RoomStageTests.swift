import CoreGraphics
import Testing
@testable import PenguinFamily

/// 箱庭的即時狀態：要畫什麼、點擊、拖曳、捏合、動作播放、閒置後鏡頭回去、什麼時候要重畫。
/// 時間由測試自己給（秒）。用屋內箱庭與 `RigCompositorTests` 的 10×10 假角色。
@MainActor
struct RoomStageTests {
    /// iPhone 17 直拿：402×874pt、@3x。企鵝站在 (4.5, 4.5)，腳底在箱庭圖的 (192, 136)。
    static func stage(character: Bool = true) throws -> RoomStage {
        let frames = character ? CharacterFrames(compositor: try RigCompositorTests.compositor()) : nil
        let stage = RoomStage(room: .indoor, character: frames, penguinPosition: TilePosition(i: 4.5, j: 4.5))
        stage.resize(viewport: CGSize(width: 402, height: 874), displayScale: 3)
        return stage
    }

    /// 箱庭圖上的一點在畫面上的位置（pt）。
    static func screenPoint(_ stage: RoomStage, x: Double, y: Double) throws -> CGPoint {
        let t = try #require(stage.viewTransform)
        return CGPoint(x: (x - t.topLeftX) * t.pointsPerPixel, y: (y - t.topLeftY) * t.pointsPerPixel)
    }

    @Test func firstLookIsAtThePenguin() throws {
        let stage = try Self.stage()
        let camera = try #require(stage.camera)
        #expect(camera.centerX == 192)        // 腳底的 x
        #expect(camera.centerY == 128)        // 箱庭比畫面矮，上下固定置中
        #expect(stage.zoom == 3)
    }

    @Test func drawsBackgroundFirstThenByDepth() throws {
        let stage = try Self.stage()
        let sprites = stage.sprites()
        #expect(sprites.first?.key == .background)
        #expect(sprites.count == 1 + RoomLayout.indoor.furniture.count + 1)
        #expect(sprites.contains { $0.key == .penguinRest })
        // 床在企鵝後面（深度較小），先畫
        let bed = try #require(RoomLayout.indoor.furniture.firstIndex { $0.kind == .bed })
        let bedIndex = try #require(sprites.firstIndex { $0.key == .furniture(bed) })
        let penguinIndex = try #require(sprites.firstIndex { $0.key == .penguinRest })
        #expect(bedIndex < penguinIndex)
    }

    @Test func everySpriteHasABitmap() throws {
        let stage = try Self.stage()
        let bitmaps = stage.allBitmaps()
        #expect(bitmaps.count == 1 + RoomLayout.indoor.furniture.count + 1 + Motion.hello.frameCount)
        stage.setIntent(.hello, now: 0)
        for t in stride(from: 0.0, through: Motion.hello.duration, by: 0.05) {
            _ = stage.update(now: t)
            for sprite in stage.sprites() { #expect(bitmaps[sprite.key] != nil, "\(sprite.key) 沒有圖") }
        }
    }

    @Test func placeholderWhenNoCharacter() throws {
        let stage = try Self.stage(character: false)
        #expect(stage.sprites().contains { $0.key == .placeholder })
        #expect(stage.allBitmaps()[.placeholder] == PlaceholderSilhouette.bitmap)
    }

    @Test func helloPlaysFrameByFrameThenReportsFinishedOnce() throws {
        let stage = try Self.stage()
        _ = stage.update(now: 0)
        stage.setIntent(.hello, now: 10)
        var tick = stage.update(now: 10.5)
        #expect(stage.sprites().contains { $0.key == .penguinFrame(motion: "hello", frame: 10) })
        #expect(tick.draw && tick.keepRunning && !tick.motionFinished)
        tick = stage.update(now: 10 + Motion.hello.duration)
        #expect(tick.motionFinished)
        #expect(stage.sprites().contains { $0.key == .penguinRest })
        tick = stage.update(now: 20)
        #expect(!tick.motionFinished)
        #expect(!tick.keepRunning)
    }

    @Test func sameIntentAgainDoesNotRestart() throws {
        let stage = try Self.stage()
        stage.setIntent(.hello, now: 0)
        stage.setIntent(.hello, now: 1)
        _ = stage.update(now: 1.5)
        #expect(stage.sprites().contains { $0.key == .penguinFrame(motion: "hello", frame: 30) })
        #expect(RoomStage.motion(for: .idle) == nil)
        #expect(RoomStage.motion(for: .hello)?.name == "hello")
    }

    @Test func drawsOnlyWhenSomethingChanged() throws {
        let stage = try Self.stage()
        var woke = 0
        stage.onChange = { woke += 1 }
        #expect(stage.update(now: 0).draw)          // 第一次一定要畫
        let idle = stage.update(now: 1)
        #expect(!idle.draw && !idle.keepRunning)    // 沒事：不畫、可以暫停
        stage.panChanged(translation: CGSize(width: 30, height: 0), startLocation: .zero, now: 2)
        #expect(woke == 1)                          // 有變化就叫醒遊戲迴圈
        #expect(stage.update(now: 2).draw)
    }

    @Test func dragMovesTheCameraTheOtherWay() throws {
        let stage = try Self.stage()
        let start = try #require(stage.camera?.centerX)
        stage.panChanged(translation: CGSize(width: 30, height: 0), startLocation: .zero, now: 0)
        #expect(stage.camera?.centerX == start - 10)    // 30pt ÷ 每像素 3pt
        stage.panChanged(translation: CGSize(width: 45, height: 0), startLocation: .zero, now: 0)
        #expect(stage.camera?.centerX == start - 15)    // 只套用這一下多移的 15pt
        stage.panEnded(now: 0)
    }

    @Test func dragStartingOnPenguinDoesNotScroll() throws {
        let stage = try Self.stage()
        let onPenguin = try Self.screenPoint(stage, x: 192, y: 133)
        #expect(stage.hitsPenguin(at: onPenguin))
        #expect(!stage.hitsPenguin(at: .zero))
        let before = stage.camera
        stage.panChanged(translation: CGSize(width: 30, height: 0), startLocation: onPenguin, now: 0)
        #expect(stage.camera == before)
    }

    @Test func pinchStaysInRangeAndSnapsOnRelease() throws {
        let stage = try Self.stage()
        let anchor = CGPoint(x: 201, y: 437)
        stage.pinchChanged(magnification: 0.5, anchor: anchor, now: 0)
        #expect(stage.zoom == 1.5)
        stage.pinchChanged(magnification: 0.1, anchor: anchor, now: 0)
        #expect(stage.zoom == 1)                    // 最小：房間左右塞滿畫面
        stage.pinchEnded(magnification: 0.45, anchor: anchor, now: 0)
        #expect(stage.zoom == 4.0 / 3)              // 1.35pt → 吸附到 4 個實體像素
    }

    @Test func cameraReturnsToPenguinAfterIdle() throws {
        let stage = try Self.stage()
        let home = try #require(stage.camera)
        stage.panChanged(translation: CGSize(width: 150, height: 0), startLocation: .zero, now: 100)
        stage.panEnded(now: 100)
        _ = stage.update(now: 100)
        let waiting = stage.update(now: 101)
        #expect(!waiting.keepRunning)
        #expect(waiting.wakeAt == 100 + RoomStage.idleSecondsBeforeReturn)
        #expect(stage.camera != home)

        var now = 105.0
        var tick = stage.update(now: now)
        #expect(tick.keepRunning && tick.draw)
        var frames = 0
        while tick.keepRunning && frames < 600 {
            now += 1.0 / 60
            tick = stage.update(now: now)
            frames += 1
        }
        #expect(stage.camera == home)
        #expect(frames < 600)
    }

    @Test func touchingAgainPostponesTheReturn() throws {
        let stage = try Self.stage()
        stage.panChanged(translation: CGSize(width: 150, height: 0), startLocation: .zero, now: 0)
        stage.panEnded(now: 0)
        stage.ownerTouched(now: 4)
        #expect(stage.update(now: 5).wakeAt == 4 + RoomStage.idleSecondsBeforeReturn)
    }
}
