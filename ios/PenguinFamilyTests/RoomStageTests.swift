import CoreGraphics
import Testing
@testable import PenguinFamily

/// 箱庭的即時狀態：要畫什麼、點到哪一隻、拖曳、捏合、各自的動作、閒置後鏡頭回去、什麼時候要重畫、上台與下台。
/// 時間由測試自己給（秒）。用屋內箱庭與 `RigCompositorTests` 的 10×10 假角色。
@MainActor
struct RoomStageTests {
    /// 後台名單的兩隻。
    static let ids = [PenguinID("first"), PenguinID("second")]
    /// 和 `GameView.startPositions` 相同：第一隻腳底在 (192, 136)，第二隻在 (224, 136)。
    static let positions = [TilePosition(i: 4.5, j: 4.5), TilePosition(i: 5.5, j: 3.5)]

    /// iPhone 17 直拿：402×874pt、@3x。後台名單是 `ids` 兩隻，`withCharacter[i]` 為 false 的那隻用灰色剪影；
    /// 依序上台站到 `positions`，給的位置比兩個少時，後面的留在後台。
    static func stage(withCharacter: [Bool] = [true, true], positions: [TilePosition] = positions) throws -> RoomStage {
        let frames = CharacterFrames(compositor: try RigCompositorTests.compositor())
        let cast = zip(ids, withCharacter).map { RoomStage.CastMember(id: $0, frames: $1 ? frames : nil) }
        let stage = RoomStage(room: .indoor, cast: cast)
        for (id, position) in zip(ids, positions) { stage.add(id, at: position) }
        stage.resize(viewport: CGSize(width: 402, height: 874), displayScale: 3)
        return stage
    }

    /// 箱庭圖上的一點在畫面上的位置（pt）。
    static func screenPoint(_ stage: RoomStage, x: Double, y: Double) throws -> CGPoint {
        let t = try #require(stage.viewTransform)
        return CGPoint(x: (x - t.topLeftX) * t.pointsPerPixel, y: (y - t.topLeftY) * t.pointsPerPixel)
    }

    /// 台上某隻企鵝腳底上方 3 像素（在牠的圖裡）在畫面上的位置。
    static func onPenguin(_ stage: RoomStage, _ id: PenguinID) throws -> CGPoint {
        let feet = try #require(stage.feet(of: id))
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
        #expect(Self.hasKey(stage, .penguinRest(Self.ids[0])))
        #expect(Self.hasKey(stage, .placeholder))           // 第二隻沒有角色包
        // 床在企鵝後面（深度較小），先畫
        let bed = try #require(RoomLayout.indoor.furniture.firstIndex { $0.kind == .bed })
        let bedIndex = try #require(sprites.firstIndex { $0.key == .furniture(bed) })
        let penguinIndex = try #require(sprites.firstIndex { $0.key == .penguinRest(Self.ids[0]) })
        #expect(bedIndex < penguinIndex)
    }

    @Test func everySpriteHasABitmap() throws {
        let stage = try Self.stage(withCharacter: [true, false])
        let bitmaps = stage.allBitmaps()
        // 背景＋家具＋第一隻（站好＋哈囉每一格）＋灰色剪影
        #expect(bitmaps.count == 1 + RoomLayout.indoor.furniture.count + 1 + Motion.hello.frameCount + 1)
        stage.setIntent(.hello, for: Self.ids[0], now: 0)
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
        let (first, second) = (Self.ids[0], Self.ids[1])
        _ = stage.update(now: 0)
        stage.setIntent(.hello, for: first, now: 10)
        var tick = stage.update(now: 10.5)
        #expect(Self.hasKey(stage, .penguinFrame(first, motion: "hello", frame: 10)))
        #expect(Self.hasKey(stage, .penguinRest(second)))       // 第二隻沒被點，照樣站著
        #expect(tick.draw && tick.keepRunning && tick.motionFinished.isEmpty)

        stage.setIntent(.hello, for: second, now: 11)
        tick = stage.update(now: 10 + Motion.hello.duration)
        #expect(tick.motionFinished == [first])                  // 只有第一隻播完
        #expect(Self.hasKey(stage, .penguinRest(first)))
        tick = stage.update(now: 11 + Motion.hello.duration)
        #expect(tick.motionFinished == [second])
        tick = stage.update(now: 20)
        #expect(tick.motionFinished.isEmpty && !tick.keepRunning)
    }

    @Test func sameIntentAgainDoesNotRestart() throws {
        let stage = try Self.stage()
        stage.setIntent(.hello, for: Self.ids[0], now: 0)
        stage.setIntent(.hello, for: Self.ids[0], now: 1)
        _ = stage.update(now: 1.5)
        #expect(Self.hasKey(stage, .penguinFrame(Self.ids[0], motion: "hello", frame: 30)))
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
        stage.setPosition(Self.positions[0], for: Self.ids[0])
        #expect(woke == 0)                          // 位置沒變：不叫醒
        stage.panChanged(translation: CGSize(width: 30, height: 0), startLocation: .zero, now: 2)
        #expect(woke == 1)                          // 有變化就叫醒遊戲迴圈
        #expect(stage.update(now: 2).draw)
    }

    // MARK: - 點擊

    @Test func tapFindsWhichPenguin() throws {
        let stage = try Self.stage(withCharacter: [true, false])
        #expect(stage.penguin(at: try Self.onPenguin(stage, Self.ids[0])) == Self.ids[0])
        #expect(stage.penguin(at: try Self.onPenguin(stage, Self.ids[1])) == Self.ids[1])   // 灰色剪影也點得到
        #expect(stage.penguin(at: .zero) == nil)
    }

    @Test func frontPenguinWinsWhenOverlapping() throws {
        // 站在同一點：後上台的畫在後面，也就是在前面
        let same = try Self.stage(positions: [Self.positions[0], Self.positions[0]])
        #expect(same.penguin(at: try Self.onPenguin(same, Self.ids[0])) == Self.ids[1])
        // 第一隻離主人比較近（畫面比較下方）：牠在前面
        let nearer = try Self.stage(positions: [TilePosition(i: 4.7, j: 4.7), Self.positions[0]])
        let (a, b) = (try #require(nearer.feet(of: Self.ids[0])), try #require(nearer.feet(of: Self.ids[1])))
        #expect(a.y > b.y)
        #expect(nearer.penguin(at: try Self.onPenguin(nearer, Self.ids[1])) == Self.ids[0])
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
        for id in Self.ids {
            let stage = try Self.stage()
            let before = stage.camera
            stage.panChanged(translation: CGSize(width: 30, height: 0), startLocation: try Self.onPenguin(stage, id), now: 0)
            #expect(stage.camera == before, "從 \(id.rawValue) 身上開始拖")
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

    // MARK: - 上台、下台（作者 2026-11-17 決定：用身分加入、移除，不用數量）

    @Test func backstagePenguinIsNotOnStageButItsImagesAreReady() throws {
        let stage = try Self.stage(positions: [Self.positions[0]])    // 第二隻留在後台
        #expect(stage.onStage == [Self.ids[0]])
        #expect(!Self.hasKey(stage, .penguinRest(Self.ids[1])))
        #expect(stage.allBitmaps()[.penguinRest(Self.ids[1])] != nil)  // 圖先準備好，上台時不用再載入
        #expect(stage.feet(of: Self.ids[1]) == nil)
        // 第二隻平常站的地方點下去沒有企鵝
        #expect(stage.penguin(at: try Self.screenPoint(stage, x: 224, y: 133)) == nil)
        // 鏡頭只看台上的那一隻
        #expect(stage.camera?.centerX == 192)
    }

    @Test func addAndRemoveByID() throws {
        let stage = try Self.stage(positions: [Self.positions[0]])
        var woke = 0
        stage.onChange = { woke += 1 }
        stage.add(Self.ids[1], at: Self.positions[1])
        #expect(stage.onStage == Self.ids)
        #expect(woke == 1)                                          // 上台要重畫
        #expect(stage.penguin(at: try Self.onPenguin(stage, Self.ids[1])) == Self.ids[1])
        stage.add(Self.ids[1], at: Self.positions[0])               // 已經在台上：不做事，也不換位置
        #expect(stage.feet(of: Self.ids[1]) == PixelPoint(x: 224, y: 136))
        stage.add(PenguinID("not-in-cast"), at: Self.positions[0])   // 不在後台名單：不做事
        #expect(stage.onStage == Self.ids)
        #expect(woke == 1)

        stage.remove(Self.ids[0])
        #expect(stage.onStage == [Self.ids[1]])
        #expect(!Self.hasKey(stage, .penguinRest(Self.ids[0])))
        stage.remove(Self.ids[0])                                   // 已經下台：不做事
        #expect(woke == 2)
    }

    @Test func removingStopsTheMotionWithoutReportingIt() throws {
        let stage = try Self.stage()
        stage.setIntent(.hello, for: Self.ids[0], now: 0)
        stage.remove(Self.ids[0])
        #expect(stage.update(now: Motion.hello.duration + 1).motionFinished.isEmpty)
        stage.setIntent(.hello, for: Self.ids[0], now: 0)          // 不在台上：不做事
        stage.setPosition(Self.positions[1], for: Self.ids[0])
        #expect(stage.onStage == [Self.ids[1]])
    }

    // MARK: - 舞台只建一次（2026-11-18）

    @Test func recreatingRoomViewDoesNotBuildAStage() {
        // SwiftUI 每次重算上一層的 body 都會重新建立 RoomView；舞台等第一次出現才建，不能跟著重建
        let before = RoomStage.createdCount
        for _ in 0..<3 {
            _ = RoomView(room: .indoor, cast: Self.ids.map { .init(id: $0, frames: nil) },
                         penguins: [.init(id: Self.ids[0], position: Self.positions[0], intent: .idle)])
        }
        #expect(RoomStage.createdCount == before)
    }

    @Test func makeStagePutsTheStartingPenguinsOnStage() {
        let stage = RoomView.makeStage(room: .indoor, cast: Self.ids.map { .init(id: $0, frames: nil) },
                                       penguins: [.init(id: Self.ids[0], position: Self.positions[0], intent: .idle)])
        #expect(stage.onStage == [Self.ids[0]])
        #expect(stage.feet(of: Self.ids[0]) == PixelPoint(x: 192, y: 136))
    }

    // MARK: - 一家

    @Test func eventLogNamesEachPenguin() {
        #expect(PenguinID(character: nil, index: 0).rawValue == "placeholder-1")
        #expect(PenguinID(character: nil, index: 1).rawValue == "placeholder-2")
    }

    @Test func gameStartsWithOnlyTheFirstPenguinOnStage() {
        // A1 第 5 項：寫移動的期間第二隻先留在後台；第 8 項第二隻上台時改這個測試
        #expect(GameView.initialStage(Self.ids) == [Self.ids[0]])
        #expect(GameView.initialStage([]).isEmpty)
    }
}
