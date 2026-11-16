import CoreGraphics
import Testing
@testable import PenguinFamily

/// 箱庭的即時狀態：要畫什麼、點到哪一隻、拖曳、捏合、各自的動作、閒置後鏡頭回去、什麼時候要重畫。
/// 時間由測試自己給（秒）。用屋內箱庭與 `RigCompositorTests` 的 10×10 假角色。
@MainActor
struct RoomStageTests {
    /// 和 `GameView.startPositions` 相同：第一隻腳底在 (192, 136)，第二隻在 (224, 136)。
    static let positions = [TilePosition(i: 4.5, j: 4.5), TilePosition(i: 5.5, j: 3.5)]

    /// iPhone 17 直拿：402×874pt、@3x。`withCharacter[i]` 為 false 的那隻用灰色剪影。
    static func stage(withCharacter: [Bool] = [true, true], positions: [TilePosition] = positions) throws -> RoomStage {
        let frames = CharacterFrames(compositor: try RigCompositorTests.compositor())
        let setups = zip(withCharacter, positions).map { RoomStage.PenguinSetup(frames: $0 ? frames : nil, position: $1) }
        let stage = RoomStage(room: .indoor, penguins: setups)
        stage.resize(viewport: CGSize(width: 402, height: 874), displayScale: 3)
        return stage
    }

    /// 箱庭圖上的一點在畫面上的位置（pt）。
    static func screenPoint(_ stage: RoomStage, x: Double, y: Double) throws -> CGPoint {
        let t = try #require(stage.viewTransform)
        return CGPoint(x: (x - t.topLeftX) * t.pointsPerPixel, y: (y - t.topLeftY) * t.pointsPerPixel)
    }

    /// 某隻企鵝腳底上方 3 像素（在牠的圖裡）在畫面上的位置。
    static func onPenguin(_ stage: RoomStage, _ index: Int) throws -> CGPoint {
        let feet = stage.feet(of: index)
        return try screenPoint(stage, x: Double(feet.x), y: Double(feet.y - 3))
    }

    static func hasKey(_ stage: RoomStage, _ key: RoomStage.SpriteKey) -> Bool {
        stage.sprites().contains { $0.key == key }
    }

    // MARK: - 畫什麼

    @Test func firstLookIsBetweenThePenguins() throws {
        let stage = try Self.stage()
        let camera = try #require(stage.camera)
        #expect(camera.centerX == 208)        // 兩隻腳底 x 的中點
        #expect(camera.centerY == 128)        // 箱庭比畫面矮，上下固定置中
        #expect(stage.zoom == 3)
    }

    @Test func drawsBackgroundFirstThenByDepth() throws {
        let stage = try Self.stage(withCharacter: [true, false])
        let sprites = stage.sprites()
        #expect(sprites.first?.key == .background)
        #expect(sprites.count == 1 + RoomLayout.indoor.furniture.count + 2)
        #expect(Self.hasKey(stage, .penguinRest(penguin: 0)))
        #expect(Self.hasKey(stage, .placeholder))           // 第二隻沒有角色包
        // 床在企鵝後面（深度較小），先畫
        let bed = try #require(RoomLayout.indoor.furniture.firstIndex { $0.kind == .bed })
        let bedIndex = try #require(sprites.firstIndex { $0.key == .furniture(bed) })
        let penguinIndex = try #require(sprites.firstIndex { $0.key == .penguinRest(penguin: 0) })
        #expect(bedIndex < penguinIndex)
    }

    @Test func everySpriteHasABitmap() throws {
        let stage = try Self.stage(withCharacter: [true, false])
        let bitmaps = stage.allBitmaps()
        // 背景＋家具＋第一隻（站好＋哈囉每一格）＋灰色剪影
        #expect(bitmaps.count == 1 + RoomLayout.indoor.furniture.count + 1 + Motion.hello.frameCount + 1)
        stage.setIntent(.hello, for: 0, now: 0)
        for t in stride(from: 0.0, through: Motion.hello.duration, by: 0.05) {
            _ = stage.update(now: t)
            for sprite in stage.sprites() { #expect(bitmaps[sprite.key] != nil, "\(sprite.key) 沒有圖") }
        }
    }

    @Test func placeholdersWhenNoCharacters() throws {
        let stage = try Self.stage(withCharacter: [false, false])
        #expect(stage.sprites().filter { $0.key == .placeholder }.count == 2)
        #expect(stage.allBitmaps()[.placeholder] == PlaceholderSilhouette.bitmap)
    }

    // MARK: - 各自的動作

    @Test func eachPenguinPlaysItsOwnMotion() throws {
        let stage = try Self.stage()
        _ = stage.update(now: 0)
        stage.setIntent(.hello, for: 0, now: 10)
        var tick = stage.update(now: 10.5)
        #expect(Self.hasKey(stage, .penguinFrame(penguin: 0, motion: "hello", frame: 10)))
        #expect(Self.hasKey(stage, .penguinRest(penguin: 1)))    // 第二隻沒被點，照樣站著
        #expect(tick.draw && tick.keepRunning && tick.motionFinished.isEmpty)

        stage.setIntent(.hello, for: 1, now: 11)
        tick = stage.update(now: 10 + Motion.hello.duration)
        #expect(tick.motionFinished == [0])                      // 只有第一隻播完
        #expect(Self.hasKey(stage, .penguinRest(penguin: 0)))
        tick = stage.update(now: 11 + Motion.hello.duration)
        #expect(tick.motionFinished == [1])
        tick = stage.update(now: 20)
        #expect(tick.motionFinished.isEmpty && !tick.keepRunning)
    }

    @Test func sameIntentAgainDoesNotRestart() throws {
        let stage = try Self.stage()
        stage.setIntent(.hello, for: 0, now: 0)
        stage.setIntent(.hello, for: 0, now: 1)
        _ = stage.update(now: 1.5)
        #expect(Self.hasKey(stage, .penguinFrame(penguin: 0, motion: "hello", frame: 30)))
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

    // MARK: - 點擊

    @Test func tapFindsWhichPenguin() throws {
        let stage = try Self.stage(withCharacter: [true, false])
        #expect(stage.penguin(at: try Self.onPenguin(stage, 0)) == 0)
        #expect(stage.penguin(at: try Self.onPenguin(stage, 1)) == 1)   // 灰色剪影也點得到
        #expect(stage.penguin(at: .zero) == nil)
    }

    @Test func frontPenguinWinsWhenOverlapping() throws {
        // 站在同一點：後畫的（編號大）在前面
        let same = try Self.stage(positions: [Self.positions[0], Self.positions[0]])
        #expect(same.penguin(at: try Self.onPenguin(same, 0)) == 1)
        // 第一隻離主人比較近（畫面比較下方）：它在前面
        let nearer = try Self.stage(positions: [TilePosition(i: 4.7, j: 4.7), Self.positions[0]])
        #expect(nearer.feet(of: 0).y > nearer.feet(of: 1).y)
        #expect(nearer.penguin(at: try Self.onPenguin(nearer, 1)) == 0)
    }

    // MARK: - 拖曳與捏合

    @Test func dragMovesTheCameraTheOtherWay() throws {
        let stage = try Self.stage()
        let start = try #require(stage.camera?.centerX)
        stage.panChanged(translation: CGSize(width: 30, height: 0), startLocation: .zero, now: 0)
        #expect(stage.camera?.centerX == start - 10)    // 30pt ÷ 每像素 3pt
        stage.panChanged(translation: CGSize(width: 45, height: 0), startLocation: .zero, now: 0)
        #expect(stage.camera?.centerX == start - 15)    // 只套用這一下多移的 15pt
        stage.panEnded(now: 0)
    }

    @Test func dragStartingOnEitherPenguinDoesNotScroll() throws {
        for index in 0..<2 {
            let stage = try Self.stage()
            let before = stage.camera
            stage.panChanged(translation: CGSize(width: 30, height: 0), startLocation: try Self.onPenguin(stage, index), now: 0)
            #expect(stage.camera == before, "從第 \(index + 1) 隻身上開始拖")
        }
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

    // MARK: - 閒置後鏡頭回去

    @Test func cameraReturnsBetweenPenguinsAfterIdle() throws {
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

    @Test func eventLogNamesEachPenguin() {
        #expect(GameView.penguinID(of: nil, at: 0) == "placeholder-1")
        #expect(GameView.penguinID(of: nil, at: 1) == "placeholder-2")
    }
}
