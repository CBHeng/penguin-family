import CoreGraphics
import Testing
@testable import PenguinFamily

/// 箱庭的即時狀態：要畫什麼、點到哪一隻、拖曳、捏合、各自的動作、閒置後鏡頭回去、什麼時候要重畫、上台與下台。
/// 時間由測試自己給（秒）。用屋內箱庭與 `VectorRigTests` 的 20×20 假角色（有斜向，腳底在 (10, 18)）。
@MainActor
struct RoomStageTests {
    /// 後台名單的兩隻。
    static let ids = [PenguinID("first"), PenguinID("second")]
    /// 和 `GameView.startPositions` 相同：第一隻腳底在 (192, 136)，第二隻在 (224, 136)。
    static let positions = [TilePosition(i: 4.5, j: 4.5), TilePosition(i: 5.5, j: 3.5)]

    /// iPhone 17 直拿：402×874pt、@3x。後台名單是 `ids` 兩隻，`withCharacter[i]` 為 false 的那隻用灰色剪影；
    /// 依序上台站到 `positions`，給的位置比兩個少時，後面的留在後台。
    static func stage(withCharacter: [Bool] = [true, true], positions: [TilePosition] = positions) throws -> RoomStage {
        let rig = try VectorRigTests.rig(VectorRigTests.walkingJSON)
        let cast = zip(ids, withCharacter).map { RoomStage.CastMember(id: $0, vector: $1 ? rig : nil) }
        let stage = RoomStage(room: .indoor, cast: cast)
        for (id, position) in zip(ids, positions) { stage.add(id, at: position) }
        stage.resize(viewport: CGSize(width: 402, height: 874), displayScale: 3)
        return stage
    }

    /// 箱庭圖上的一點在畫面上的位置（pt）。
    static func screenPoint(_ stage: RoomStage, x: Double, y: Double) throws -> CGPoint {
        let t = try #require(stage.viewTransform)
        return CGPoint(x: (x - t.topLeftX) * t.pointsPerUnit, y: (y - t.topLeftY) * t.pointsPerUnit)
    }

    /// 台上某隻企鵝腳底上方 3 個單位（在牠的圖裡）在畫面上的位置。
    static func onPenguin(_ stage: RoomStage, _ id: PenguinID) throws -> CGPoint {
        let feet = try #require(stage.feet(of: id))
        return try screenPoint(stage, x: Double(feet.x), y: Double(feet.y - 3))
    }

    static func hasKey(_ stage: RoomStage, _ key: RoomStage.SpriteKey) -> Bool {
        stage.sprites().contains { $0.key == key }
    }

    /// 繪圖層畫得出這一樣：箱庭的多邊形，或企鵝的造型。
    static func canDraw(_ stage: RoomStage, _ key: RoomStage.SpriteKey) -> Bool {
        if case .penguin(let id) = key { return stage.rigs()[id] != nil }
        return stage.polygons()[key] != nil
    }

    /// 灰色剪影的畫布大小（假角色是 20×20）。
    static let placeholderCanvas = VectorRig.placeholder.front.canvas

    static func sprite(_ stage: RoomStage, _ id: PenguinID) -> RoomStage.Sprite? {
        stage.sprites().first { $0.key == .penguin(id) }
    }

    // MARK: - 畫什麼

    @Test func firstLookIsAtTheFirstPenguin() throws {
        // 作者 2026-11-19 決定：鏡頭優先看第一隻
        let stage = try Self.stage()
        let camera = try #require(stage.camera)
        #expect(camera.centerX == 192)        // 第一隻腳底的 x
        #expect(camera.centerY == 128)        // 箱庭比畫面矮，上下固定置中
        #expect(stage.zoom == 3)
    }

    @Test func cameraLooksAtTheNextOneWhenTheFirstIsNotOnStage() throws {
        let stage = try Self.stage(positions: [])                   // 一開始台上沒有企鵝
        stage.add(Self.ids[1], at: Self.positions[1])
        var now = 100.0
        var tick = stage.update(now: now)
        while tick.keepRunning && now < 200 {
            now += 1.0 / 60
            tick = stage.update(now: now)
        }
        #expect(stage.camera?.centerX == 224)                       // 閒置後回到台上的第二隻
    }

    @Test func drawsBackgroundFirstThenByDepth() throws {
        let stage = try Self.stage(withCharacter: [true, false])
        let sprites = stage.sprites()
        #expect(sprites.first?.key == .background)
        #expect(sprites.count == 1 + RoomLayout.indoor.furniture.count + 2)
        #expect(Self.sprite(stage, Self.ids[0])?.width == 20)
        #expect(Self.sprite(stage, Self.ids[1])?.width == 20)      // 第二隻沒有角色包：借第一隻的形狀塗灰
        // 床在企鵝後面（深度較小），先畫
        let bed = try #require(RoomLayout.indoor.furniture.firstIndex { $0.kind == .bed })
        let bedIndex = try #require(sprites.firstIndex { $0.key == .furniture(bed) })
        let penguinIndex = try #require(sprites.firstIndex { $0.key == .penguin(Self.ids[0]) })
        #expect(bedIndex < penguinIndex)
    }

    @Test func everySpriteCanBeDrawn() throws {
        let stage = try Self.stage(withCharacter: [true, false])
        // 兩隻的造型（第二隻是借第一隻形狀塗灰的替身）；箱庭的背景與家具是多邊形
        #expect(stage.rigs().count == 2)
        #expect(stage.polygons().count == 1 + RoomLayout.indoor.furniture.count)
        stage.setIntent(.hello, for: Self.ids[0], now: 0)
        for t in stride(from: 0.0, through: HelloMotion.standard.duration, by: 0.05) {
            _ = stage.update(now: t)
            for sprite in stage.sprites() { #expect(Self.canDraw(stage, sprite.key), "\(sprite.key) 畫不出來") }
        }
    }

    @Test func placeholdersWhenNoCharacters() throws {
        let stage = try Self.stage(withCharacter: [false, false])
        for id in Self.ids {
            let sprite = try #require(Self.sprite(stage, id))
            #expect(sprite.width == Self.placeholderCanvas.width && sprite.height == Self.placeholderCanvas.height)
            #expect(stage.rigs()[id]?.front.canvas == Self.placeholderCanvas)
        }
    }

    @Test func missingPackBorrowsTheOtherShapeInGray() throws {
        // 作者 2026-11-19 決定：第二隻沒有角色包時，借第一隻的形狀塗灰，斜向與走路都和第一隻一樣
        let stage = try Self.stage(withCharacter: [true, false])
        let standIn = try #require(stage.rigs()[Self.ids[1]])
        #expect(standIn.outline.color == VectorRig.placeholderOutline)
        #expect(Set(standIn.facings.keys) == Set(try VectorRigTests.rig(VectorRigTests.walkingJSON).facings.keys))
        stage.setIntent(.walk(to: Tile(i: 8, j: 3), pace: .walk), for: Self.ids[1], now: 0)
        _ = stage.update(now: 1)
        #expect(stage.pose(of: Self.ids[1]) == (try Self.walking(.walk, .frontRight, at: 1)))   // 斜著走，不是面向鏡頭
        // 第一隻沒有、第二隻有時也一樣：替身借第二隻的形狀
        let flipped = try Self.stage(withCharacter: [false, true])
        #expect(flipped.rigs()[Self.ids[0]]?.outline.color == VectorRig.placeholderOutline)
        #expect(flipped.rigs()[Self.ids[0]]?.facings.count == standIn.facings.count)
    }

    // MARK: - 各自的動作

    @Test func eachPenguinPlaysItsOwnMotion() throws {
        let stage = try Self.stage()
        let (first, second) = (Self.ids[0], Self.ids[1])
        _ = stage.update(now: 0)
        stage.setIntent(.hello, for: first, now: 10)
        var tick = stage.update(now: 10.5)
        #expect(stage.pose(of: first) == .front(HelloMotion.standard.pose(at: 0.5)))
        #expect(stage.pose(of: second) == .front(.rest))         // 第二隻沒被點，照樣站著
        #expect(tick.draw && tick.keepRunning && tick.motionFinished.isEmpty)

        stage.setIntent(.hello, for: second, now: 11)
        tick = stage.update(now: 10 + HelloMotion.standard.duration)
        #expect(tick.motionFinished == [first])                  // 只有第一隻播完
        #expect(stage.pose(of: first) == .front(.rest))
        tick = stage.update(now: 11 + HelloMotion.standard.duration)
        #expect(tick.motionFinished == [second])
        tick = stage.update(now: 20)
        #expect(tick.motionFinished.isEmpty && !tick.keepRunning)
    }

    @Test func sameIntentAgainDoesNotRestart() throws {
        let stage = try Self.stage()
        stage.setIntent(.hello, for: Self.ids[0], now: 0)
        stage.setIntent(.hello, for: Self.ids[0], now: 1)
        _ = stage.update(now: 1.5)
        #expect(stage.pose(of: Self.ids[0]) == .front(HelloMotion.standard.pose(at: 1.5)))
        #expect(PenguinMotions.standard.motion(for: .idle) == nil)
        #expect(PenguinMotions.standard.motion(for: .hello)?.name == "hello")
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
        #expect(stage.penguin(at: try Self.onPenguin(stage, Self.ids[1])) == Self.ids[1])   // 替身也點得到
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
        #expect(stage.camera?.centerX == start - 10)    // 30pt ÷ 每單位 3pt
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

    @Test func pinchStaysInRangeAndStopsWhereReleased() throws {
        let stage = try Self.stage()
        let anchor = CGPoint(x: 201, y: 437)
        stage.pinchChanged(magnification: 0.5, anchor: anchor, now: 0)
        #expect(stage.zoom == 1.5)
        stage.pinchChanged(magnification: 0.1, anchor: anchor, now: 0)
        #expect(stage.zoom == 402.0 / Double(IsoProjection(room: .indoor).canvasWidth))   // 最小：房間左右塞滿畫面
        stage.pinchEnded(magnification: 0.45, anchor: anchor, now: 0)
        #expect(stage.zoom == 1.35)                 // 向量不用吸附，停在放開時的倍率
    }

    // MARK: - 閒置後鏡頭回去

    @Test func cameraReturnsToTheFirstPenguinAfterIdle() throws {
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
        #expect(!Self.hasKey(stage, .penguin(Self.ids[1])))
        #expect(stage.rigs()[Self.ids[1]] != nil)                    // 造型先準備好，上台時不用再載入
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
        #expect(stage.feet(of: Self.ids[1]) == ScenePoint(x: 224, y: 136))
        stage.add(PenguinID("not-in-cast"), at: Self.positions[0])   // 不在後台名單：不做事
        #expect(stage.onStage == Self.ids)
        #expect(woke == 1)

        stage.remove(Self.ids[0])
        #expect(stage.onStage == [Self.ids[1]])
        #expect(!Self.hasKey(stage, .penguin(Self.ids[0])))
        stage.remove(Self.ids[0])                                   // 已經下台：不做事
        #expect(woke == 2)
    }

    @Test func removingStopsTheMotionWithoutReportingIt() throws {
        let stage = try Self.stage()
        stage.setIntent(.hello, for: Self.ids[0], now: 0)
        stage.remove(Self.ids[0])
        #expect(stage.update(now: HelloMotion.standard.duration + 1).motionFinished.isEmpty)
        stage.setIntent(.hello, for: Self.ids[0], now: 0)          // 不在台上：不做事
        stage.setPosition(Self.positions[1], for: Self.ids[0])
        #expect(stage.onStage == [Self.ids[1]])
    }

    // MARK: - 舞台只建一次（2026-11-18）

    @Test func recreatingRoomViewDoesNotBuildAStage() {
        // SwiftUI 每次重算上一層的 body 都會重新建立 RoomView；舞台等第一次出現才建，不能跟著重建
        let before = RoomStage.createdCount
        for _ in 0..<3 {
            _ = RoomView(room: .indoor, cast: Self.ids.map { .init(id: $0) },
                         penguins: [.init(id: Self.ids[0], position: Self.positions[0], intent: .idle)])
        }
        #expect(RoomStage.createdCount == before)
    }

    @Test func makeStagePutsTheStartingPenguinsOnStage() {
        let stage = RoomView.makeStage(room: .indoor, cast: Self.ids.map { .init(id: $0) },
                                       penguins: [.init(id: Self.ids[0], position: Self.positions[0], intent: .idle)])
        #expect(stage.onStage == [Self.ids[0]])
        #expect(stage.feet(of: Self.ids[0]) == ScenePoint(x: 192, y: 136))
    }

    // MARK: - 走路（A1 第 6 項）

    /// 只有第一隻在台上，站在 (4.5, 4.5)。`rig` 預設是有斜向的假角色；nil 是灰色剪影。
    /// 主人「剛碰過」，鏡頭不會自己移動，只看走路。
    static func walkingStage(rig: VectorRig? = try? VectorRigTests.rig(VectorRigTests.walkingJSON)) throws -> RoomStage {
        let stage = RoomStage(room: .indoor, cast: [.init(id: ids[0], vector: rig)])
        stage.add(ids[0], at: positions[0])
        stage.resize(viewport: CGSize(width: 402, height: 874), displayScale: 3)
        stage.ownerTouched(now: 1000)
        return stage
    }

    /// 假角色往某個方向走時，作者定案的步態在第幾秒的姿勢。
    static func walking(_ pace: PenguinBehavior.Pace, _ facing: Facing, at t: Double) throws -> VectorPose {
        let gait = PenguinMotions.standard.gait(for: pace)
        let walk = try #require(try VectorRigTests.rig(VectorRigTests.walkingJSON).walk(facing.rawValue))
        return .oblique(facing, gait.vectorPose(at: t, walk: walk))
    }

    @Test func walksAlongThePathAtTheGaitSpeed() throws {
        let stage = try Self.walkingStage()
        let id = Self.ids[0]
        stage.setIntent(.walk(to: Tile(i: 8, j: 4), pace: .walk), for: id, now: 0)   // 往右下（i 往前）走 4 格
        #expect(stage.facing(of: id) == .frontRight)
        _ = stage.update(now: 1)
        #expect(stage.position(of: id) == TilePosition(i: 5.0, j: 4.5))            // 慢走每秒半格
        #expect(stage.pose(of: id) == (try Self.walking(.walk, .frontRight, at: 1)))
        _ = stage.update(now: 2.25)
        #expect(stage.position(of: id) == TilePosition(i: 5.625, j: 4.5))
        #expect(stage.pose(of: id) == (try Self.walking(.walk, .frontRight, at: 2.25)))
        let tick = stage.update(now: 8)
        #expect(tick.arrived == [RoomStage.Arrival(id: id, tile: Tile(i: 8, j: 4))])
        #expect(stage.position(of: id) == Tile(i: 8, j: 4).center)
        #expect(stage.pose(of: id) == .oblique(.frontRight, .rest))               // 走到後維持走的方向，站姿
        #expect(stage.update(now: 9).arrived.isEmpty)                              // 只回報一次
    }

    @Test func positionMovesEveryFrame() throws {
        // ADR 0007：位置與步態每一格都照時間前進
        let stage = try Self.walkingStage()
        let id = Self.ids[0]
        stage.setIntent(.walk(to: Tile(i: 8, j: 4), pace: .walk), for: id, now: 0)
        let first = stage.update(now: 1)
        #expect(first.draw && first.keepRunning)
        let next = stage.update(now: 1.05)
        #expect(next.draw && next.keepRunning)
        let p = try #require(stage.position(of: id))
        #expect(abs(p.i - 5.025) < 1e-12 && p.j == 4.5)
        #expect(stage.pose(of: id) == (try Self.walking(.walk, .frontRight, at: 1.05)))
    }

    @Test func turnsAtTheCornerAndGoesAroundTheSofa() throws {
        let stage = try Self.walkingStage()
        let id = Self.ids[0]
        // 沙發在 i = 7、j = 6～8，先往 j 走會被擋，所以先往右前（i）再往左前（j）
        stage.setIntent(.walk(to: Tile(i: 8, j: 7), pace: .walk), for: id, now: 0)
        _ = stage.update(now: 7.5)
        #expect(stage.facing(of: id) == .frontRight)
        _ = stage.update(now: 8)                                                   // 剛好走到轉角
        #expect(stage.facing(of: id) == .frontLeft && stage.position(of: id) == Tile(i: 8, j: 4).center)
        #expect(stage.update(now: 14).arrived.map(\.tile) == [Tile(i: 8, j: 7)])
    }

    @Test func trotIsTwiceAsFast() throws {
        let stage = try Self.walkingStage()
        stage.setIntent(.walk(to: Tile(i: 8, j: 4), pace: .trot), for: Self.ids[0], now: 0)
        _ = stage.update(now: 1.5)
        #expect(stage.pose(of: Self.ids[0]) == (try Self.walking(.trot, .frontRight, at: 1.5)))
        #expect(stage.update(now: 3.9).arrived.isEmpty)
        #expect(stage.update(now: 4).arrived.count == 1)
    }

    @Test func eachPenguinMovesWithItsOwnMotions() throws {
        // 作者 2026-11-19 決定：狀態兩隻共用，怎麼動每隻各一份；改第二隻的數字，第一隻照舊
        let rig = try VectorRigTests.rig(VectorRigTests.walkingJSON)
        var quick = PenguinMotions.standard
        quick.walk.cycle = 0.5        // 慢走快一倍：每秒一格
        quick.hello.wave = 0.4        // 哈囉少揮 1 秒
        let stage = RoomStage(room: .indoor, cast: [.init(id: Self.ids[0], vector: rig),
                                                    .init(id: Self.ids[1], vector: rig, motions: quick)])
        stage.add(Self.ids[0], at: TilePosition(i: 4.5, j: 4.5))
        stage.add(Self.ids[1], at: TilePosition(i: 4.5, j: 2.5))
        stage.resize(viewport: CGSize(width: 402, height: 874), displayScale: 3)
        stage.ownerTouched(now: 1000)

        // 哈囉：各照自己的時間軸，第二隻先播完
        for id in Self.ids { stage.setIntent(.hello, for: id, now: 0) }
        _ = stage.update(now: 1)
        #expect(stage.pose(of: Self.ids[0]) == .front(HelloMotion.standard.pose(at: 1)))
        #expect(stage.pose(of: Self.ids[1]) == .front(quick.hello.pose(at: 1)))
        #expect(stage.update(now: quick.hello.duration).motionFinished == [Self.ids[1]])
        #expect(stage.update(now: HelloMotion.standard.duration).motionFinished == [Self.ids[0]])

        // 慢走：各照自己的步態與速度，往右前走 4 格
        stage.setIntent(.walk(to: Tile(i: 8, j: 4), pace: .walk), for: Self.ids[0], now: 10)
        stage.setIntent(.walk(to: Tile(i: 8, j: 2), pace: .walk), for: Self.ids[1], now: 10)
        _ = stage.update(now: 11)
        #expect(stage.position(of: Self.ids[0]) == TilePosition(i: 5.0, j: 4.5))      // 每秒半格
        #expect(stage.position(of: Self.ids[1]) == TilePosition(i: 5.5, j: 2.5))      // 每秒一格
        #expect(stage.pose(of: Self.ids[0]) == (try Self.walking(.walk, .frontRight, at: 1)))
        let walk = try #require(rig.walk("frontRight"))
        #expect(stage.pose(of: Self.ids[1]) == .oblique(.frontRight, quick.walk.vectorPose(at: 1, walk: walk)))
        #expect(stage.update(now: 14).arrived.map(\.id) == [Self.ids[1]])
        #expect(stage.update(now: 18).arrived.map(\.id) == [Self.ids[0]])
    }

    @Test func unreachableGoalArrivesRightAwayWhereItStands() throws {
        let stage = try Self.walkingStage()
        stage.setIntent(.walk(to: Tile(i: 7, j: 7), pace: .walk), for: Self.ids[0], now: 0)   // 沙發上
        #expect(stage.update(now: 0.01).arrived.map(\.tile) == [Tile(i: 4, j: 4)])
        #expect(stage.facing(of: Self.ids[0]) == .front)
    }

    @Test func positionFromOutsideIsIgnoredWhileWalking() throws {
        let stage = try Self.walkingStage()
        let id = Self.ids[0]
        stage.setIntent(.walk(to: Tile(i: 8, j: 4), pace: .walk), for: id, now: 0)
        _ = stage.update(now: 2)
        stage.setPosition(Self.positions[0], for: id)                              // 外面還記著出發點
        #expect(stage.position(of: id) == TilePosition(i: 5.5, j: 4.5))
    }

    @Test func helloTurnsToTheFront() throws {
        let stage = try Self.walkingStage()
        let id = Self.ids[0]
        stage.setIntent(.walk(to: Tile(i: 5, j: 4), pace: .walk), for: id, now: 0)
        _ = stage.update(now: 2)
        stage.setIntent(.idle, for: id, now: 2)
        #expect(stage.facing(of: id) == .frontRight)                               // 待機時維持走的方向
        stage.setIntent(.hello, for: id, now: 3)
        _ = stage.update(now: 3.5)
        #expect(stage.facing(of: id) == .front)
        #expect(stage.pose(of: id) == .front(HelloMotion.standard.pose(at: 0.5)))
    }

    // MARK: - 站著（A1 第 11 項：發呆、東張西望、在家具旁邊待一下）

    @Test func standTurnsThenReportsWhenDone() throws {
        let stage = try Self.walkingStage()
        let id = Self.ids[0]
        _ = stage.update(now: 0)
        stage.setIntent(.stand(facing: .backRight, seconds: 3), for: id, now: 10, serial: 1)
        #expect(stage.facing(of: id) == .backRight)
        #expect(stage.pose(of: id) == .oblique(.backRight, .rest))
        var tick = stage.update(now: 10.1)
        #expect(tick.draw && !tick.keepRunning)                                    // 畫面不動：畫一次就可以暫停
        #expect(tick.wakeAt == 13 && tick.motionFinished.isEmpty)                  // 站滿時再醒來
        tick = stage.update(now: 13)
        #expect(tick.motionFinished == [id])
        #expect(stage.update(now: 14).motionFinished.isEmpty)                      // 只回報一次
        #expect(stage.facing(of: id) == .backRight)                                // 站滿後維持方向
        #expect(PenguinMotions.standard.motion(for: .stand(facing: nil, seconds: 1)) == nil)
    }

    @Test func standWithoutFacingKeepsTheWalkingDirection() throws {
        let stage = try Self.walkingStage()
        let id = Self.ids[0]
        stage.setIntent(.walk(to: Tile(i: 5, j: 4), pace: .walk), for: id, now: 0, serial: 1)
        #expect(stage.update(now: 2).arrived.count == 1)
        stage.setIntent(.stand(facing: nil, seconds: 1), for: id, now: 2, serial: 3)
        #expect(stage.facing(of: id) == .frontRight)
    }

    @Test func sameStandAgainWithANewSerialStartsOver() throws {
        // 同樣的站著連續要兩次（中間經過待機）：靠編號才知道要重新站
        let stage = try Self.walkingStage()
        let id = Self.ids[0]
        let stand = PenguinBehavior.Intent.stand(facing: .front, seconds: 2)
        stage.setIntent(stand, for: id, now: 0, serial: 1)
        #expect(stage.update(now: 2).motionFinished == [id])
        stage.setIntent(stand, for: id, now: 5, serial: 1)                         // 同一個編號：當作沒變
        #expect(stage.update(now: 8).motionFinished.isEmpty)
        stage.setIntent(stand, for: id, now: 8, serial: 3)
        #expect(stage.update(now: 10).motionFinished == [id])
    }

    @Test func helloInterruptsStanding() throws {
        let stage = try Self.walkingStage()
        let id = Self.ids[0]
        stage.setIntent(.stand(facing: .backLeft, seconds: 10), for: id, now: 0, serial: 1)
        stage.setIntent(.hello, for: id, now: 1, serial: 2)
        #expect(stage.facing(of: id) == .front)
        #expect(stage.update(now: 1 + HelloMotion.standard.duration).motionFinished == [id])   // 哈囉播完
        #expect(stage.update(now: 20).motionFinished.isEmpty)                          // 原本的站著不再回報
    }

    // MARK: - 走路中被點（作者 2026-11-19 決定：當場停下哈囉，揮完接著走）

    /// 從 (4, 4) 往右前慢走到 (8, 4)，在第 2.5 秒（走了 1.25 格，在 (5, 4) 與 (6, 4) 之間）被點、哈囉。
    static func stoppedMidway() throws -> RoomStage {
        let stage = try walkingStage()
        stage.setIntent(.walk(to: Tile(i: 8, j: 4), pace: .walk), for: ids[0], now: 0, serial: 1)
        _ = stage.update(now: 2.5)
        stage.setIntent(.hello, for: ids[0], now: 2.5, serial: 2)
        return stage
    }

    @Test func helloStopsTheWalkWhereItIs() throws {
        let stage = try Self.stoppedMidway()
        let id = Self.ids[0]
        #expect(stage.position(of: id) == TilePosition(i: 5.75, j: 4.5))
        #expect(stage.facing(of: id) == .front)
        let tick = stage.update(now: 3)
        #expect(tick.arrived.isEmpty)                                              // 停下來不算走到
        #expect(stage.position(of: id) == TilePosition(i: 5.75, j: 4.5))
        stage.setPosition(Self.positions[0], for: id)                              // 外面還記著出發點：不蓋過去
        #expect(stage.position(of: id) == TilePosition(i: 5.75, j: 4.5))
    }

    @Test func keepsWalkingFromWhereItStopped() throws {
        let stage = try Self.stoppedMidway()
        let id = Self.ids[0]
        stage.setIntent(.walk(to: Tile(i: 8, j: 4), pace: .walk), for: id, now: 10, serial: 3)
        #expect(stage.position(of: id) == TilePosition(i: 5.75, j: 4.5))         // 不跳回格子中心
        #expect(stage.facing(of: id) == .frontRight)
        _ = stage.update(now: 10.5)
        #expect(stage.position(of: id) == TilePosition(i: 6.0, j: 4.5))           // 慢走每秒半格，接著走
        #expect(stage.update(now: 15.4).arrived.isEmpty)
        #expect(stage.update(now: 15.5).arrived == [RoomStage.Arrival(id: id, tile: Tile(i: 8, j: 4))])   // 還剩 2.75 格
    }

    @Test func goalBehindTurnsBackWithoutJumping() throws {
        // 停在 (5, 4) 往 (6, 4) 走了 1/4 的地方，要回 (4, 4)：回頭比較近
        let stage = try Self.stoppedMidway()
        let id = Self.ids[0]
        stage.setIntent(.walk(to: Tile(i: 4, j: 4), pace: .walk), for: id, now: 10, serial: 3)
        #expect(stage.position(of: id) == TilePosition(i: 5.75, j: 4.5))
        #expect(stage.facing(of: id) == .backLeft)
        _ = stage.update(now: 10.5)
        #expect(stage.position(of: id) == TilePosition(i: 5.5, j: 4.5))
        #expect(stage.update(now: 12.5).arrived.map(\.tile) == [Tile(i: 4, j: 4)])
    }

    @Test func unreachableGoalFromMidwayStopsAtTheNearerTile() throws {
        let stage = try Self.stoppedMidway()
        stage.setIntent(.walk(to: Tile(i: 7, j: 7), pace: .walk), for: Self.ids[0], now: 10, serial: 3)   // 沙發上
        #expect(stage.update(now: 10.5).arrived.map(\.tile) == [Tile(i: 5, j: 4)])
        #expect(stage.position(of: Self.ids[0]) == Tile(i: 5, j: 4).center)
    }

    @Test func placeholderStandsFacingTheFront() throws {
        let stage = try Self.walkingStage(rig: nil)
        stage.setIntent(.stand(facing: .backRight, seconds: 1), for: Self.ids[0], now: 0)
        #expect(stage.pose(of: Self.ids[0]) == .front(.rest))
    }

    @Test func penguinBesideTheSofaIsDrawnInFront() throws {
        // 沙發佔 i = 7、j = 6～8，最靠近主人的角很低；站在它右前方 (8, 7) 的企鵝要畫在沙發前面
        let sofa = try #require(RoomLayout.indoor.furniture.firstIndex { $0.kind == .sofa })
        func order(at position: TilePosition) throws -> (sofa: Int, penguin: Int) {
            let stage = try Self.stage(positions: [position])
            let sprites = stage.sprites()
            return (try #require(sprites.firstIndex { $0.key == .furniture(sofa) }),
                    try #require(sprites.firstIndex { $0.key == .penguin(Self.ids[0]) }))
        }
        let beside = try order(at: Tile(i: 8, j: 7).center)
        #expect(beside.penguin > beside.sofa)
        let behind = try order(at: Tile(i: 6, j: 7).center)                       // 左後方：在沙發後面
        #expect(behind.penguin < behind.sofa)
        let between = try order(at: TilePosition(i: 8.5, j: 7.0))                  // 走在兩格中間也一樣
        #expect(between.penguin > between.sofa)
    }

    @Test func relationToFurnitureByTiles() {
        let sofa = TileRect(x: 7, y: 6, width: 1, height: 3)
        #expect(RoomStage.relation(of: Tile(i: 8, j: 7).center, to: sofa) == .front)
        #expect(RoomStage.relation(of: Tile(i: 7, j: 9).center, to: sofa) == .front)
        #expect(RoomStage.relation(of: Tile(i: 6, j: 7).center, to: sofa) == .behind)
        #expect(RoomStage.relation(of: Tile(i: 7, j: 5).center, to: sofa) == .behind)
        #expect(RoomStage.relation(of: Tile(i: 8, j: 5).center, to: sofa) == .unknown)   // 斜對角
    }

    @Test func everyWalkingSpriteCanBeDrawn() throws {
        let stage = try Self.walkingStage()
        stage.setIntent(.walk(to: Tile(i: 5, j: 7), pace: .trot), for: Self.ids[0], now: 0)
        for t in stride(from: 0.0, through: 6, by: 1.0 / 30) {
            _ = stage.update(now: t)
            for sprite in stage.sprites() { #expect(Self.canDraw(stage, sprite.key), "\(sprite.key) 畫不出來") }
        }
    }

    @Test func placeholderSlidesAlongFacingTheFront() throws {
        // 灰色剪影沒有斜向：面向鏡頭平移
        let stage = try Self.walkingStage(rig: nil)
        stage.setIntent(.walk(to: Tile(i: 6, j: 4), pace: .walk), for: Self.ids[0], now: 0)
        _ = stage.update(now: 2)
        #expect(stage.pose(of: Self.ids[0]) == .front(.rest))
        #expect(Self.sprite(stage, Self.ids[0])?.width == Self.placeholderCanvas.width)
        #expect(stage.feet(of: Self.ids[0]) == IsoProjection(room: .indoor).feet(at: TilePosition(i: 5.5, j: 4.5)))
    }

    // MARK: - 正面的動作每一格照時間轉（ADR 0007）

    @Test func penguinFollowsThePoseEveryFrame() throws {
        let stage = try Self.stage(positions: [Self.positions[0]])
        let id = Self.ids[0]
        _ = stage.update(now: 0)
        let still = try #require(Self.sprite(stage, id))
        // 角色畫布的腳底對到站的點：(192, 136) − (10, 18)
        #expect(still.x == 182 && still.y == 118 && still.width == 20 && still.height == 20 && still.pose == .front(.rest))

        stage.setIntent(.hello, for: id, now: 10)
        #expect(stage.update(now: 10.5).draw)
        #expect(stage.pose(of: id) == .front(HelloMotion.standard.pose(at: 10.5 - 10)))
        let next = stage.update(now: 10.51)                                       // 每一格都照時間轉
        #expect(next.draw && next.keepRunning)
        #expect(Self.sprite(stage, id)?.pose == .front(HelloMotion.standard.pose(at: 10.51 - 10)))

        let end = stage.update(now: 10 + HelloMotion.standard.duration)
        #expect(end.motionFinished == [id] && stage.pose(of: id) == .front(.rest))
        #expect(!stage.update(now: 20).draw)                                      // 站好之後不再重畫
    }

    @Test func obliqueSpriteAlsoPutsTheFeetOnThePoint() throws {
        let stage = try Self.walkingStage()
        let id = Self.ids[0]
        stage.setIntent(.walk(to: Tile(i: 8, j: 4), pace: .walk), for: id, now: 0)
        _ = stage.update(now: 1)
        let sprite = try #require(Self.sprite(stage, id))
        let feet = try #require(stage.feet(of: id))
        #expect(sprite.x == feet.x - 10 && sprite.y == feet.y - 18)
        #expect(sprite.pose == stage.pose(of: id))
        stage.setIntent(.hello, for: id, now: 2)                                   // 哈囉時轉回正面
        #expect(stage.pose(of: id) == .front(.rest))
    }

    @Test func rigWithoutObliquesFacesTheFrontWhileWalking() throws {
        let stage = try Self.walkingStage(rig: try VectorRigTests.rig())           // 只有正面的假角色
        stage.setIntent(.walk(to: Tile(i: 8, j: 4), pace: .walk), for: Self.ids[0], now: 0)
        _ = stage.update(now: 1)
        #expect(stage.facing(of: Self.ids[0]) == .frontRight && stage.pose(of: Self.ids[0]) == .front(.rest))
    }

    // MARK: - 一家

    @Test func eventLogNamesEachPenguin() {
        #expect(PenguinID(character: nil, index: 0).rawValue == "placeholder-1")
        #expect(PenguinID(character: nil, index: 1).rawValue == "placeholder-2")
    }

    @Test func gameStartsWithBothPenguinsOnStage() {
        // A1 第 12 項：第二隻回到畫面
        #expect(GameView.initialStage(Self.ids) == Self.ids)
        #expect(GameView.initialStage([]).isEmpty)
    }

    // MARK: - 兩隻互相讓路（A1 第 12 項，作者 2026-11-19 決定：先等、等不到再繞路）

    /// 每秒 30 格往前跑到 `until` 秒，每一格記下兩隻的距離（格）；回報誰在第幾秒走到哪一格。
    static func run(_ stage: RoomStage, from start: Double = 0, until end: Double,
                    closest: inout Double) throws -> [(time: Double, arrival: RoomStage.Arrival)] {
        var arrivals: [(Double, RoomStage.Arrival)] = []
        for frame in Int(start * 30)...Int(end * 30) {
            let now = Double(frame) / 30
            arrivals += stage.update(now: now).arrived.map { (now, $0) }
            let (a, b) = (try #require(stage.position(of: ids[0])), try #require(stage.position(of: ids[1])))
            closest = min(closest, ((a.i - b.i) * (a.i - b.i) + (a.j - b.j) * (a.j - b.j)).squareRoot())
        }
        return arrivals
    }

    @Test func routeGoesAroundAPenguinStandingInTheWay() throws {
        // 第一隻站在 (6, 4)，第二隻從 (4, 4) 走到 (8, 4)：一開始就繞開，不用停下來等
        let stage = try Self.stage(positions: [Tile(i: 6, j: 4).center, Tile(i: 4, j: 4).center])
        stage.setIntent(.walk(to: Tile(i: 8, j: 4), pace: .walk), for: Self.ids[1], now: 0)
        var closest = Double.infinity
        let arrivals = try Self.run(stage, until: 14, closest: &closest)
        #expect(arrivals.map(\.arrival.tile) == [Tile(i: 8, j: 4)])
        #expect(abs((arrivals.first?.time ?? 0) - 12) < 0.05)                     // 繞一圈 6 步，慢走每秒半格
        #expect(closest >= 0.999)
    }

    @Test func waitsWhenSomeoneStepsInTheWayThenGoesAround() throws {
        // 第二隻從 (4, 4) 走向 (8, 4)，走到一半第一隻站到 (6, 4) 擋住
        let stage = try Self.stage(positions: [Tile(i: 6, j: 7).center, Tile(i: 4, j: 4).center])
        stage.ownerTouched(now: 1000)                                               // 鏡頭不自己移動，只看走路
        let id = Self.ids[1]
        stage.setIntent(.walk(to: Tile(i: 8, j: 4), pace: .walk), for: id, now: 0)
        _ = stage.update(now: 1)
        stage.setPosition(Tile(i: 6, j: 4).center, for: Self.ids[0])
        var closest = Double.infinity
        _ = try Self.run(stage, from: 1, until: 2.5, closest: &closest)
        // 停在 (5, 4) 的中心等，站姿、面向擋住的那一格
        #expect(stage.position(of: id) == Tile(i: 5, j: 4).center)
        #expect(stage.pose(of: id) == .oblique(.frontRight, .rest))
        let waiting = stage.update(now: 2.6)
        #expect(waiting.keepRunning && !waiting.draw)                               // 等的時候畫面不動
        // 第二隻等 1 秒後繞路（第一隻等 1.5 秒）
        _ = try Self.run(stage, from: 2.7, until: 3.0, closest: &closest)
        #expect(stage.position(of: id) == Tile(i: 5, j: 4).center)
        _ = try Self.run(stage, from: 3.1, until: 3.5, closest: &closest)
        #expect(stage.position(of: id) != Tile(i: 5, j: 4).center)
        #expect(stage.facing(of: id) != .frontRight)                                // 往旁邊繞
        let arrivals = try Self.run(stage, from: 3.6, until: 20, closest: &closest)
        #expect(arrivals.map(\.arrival.tile) == [Tile(i: 8, j: 4)])
        #expect(closest >= 0.999)
    }

    @Test func givesUpWhenTheGoalIsTaken() throws {
        // 第一隻站在終點 (8, 4)：第二隻走到 (7, 4) 等，繞不過去，等滿 4 秒就停在那裡算走到
        let stage = try Self.stage(positions: [Tile(i: 8, j: 4).center, Tile(i: 4, j: 4).center])
        stage.setIntent(.walk(to: Tile(i: 8, j: 4), pace: .walk), for: Self.ids[1], now: 0)
        var closest = Double.infinity
        let arrivals = try Self.run(stage, until: 12, closest: &closest)
        #expect(arrivals.map(\.arrival.tile) == [Tile(i: 7, j: 4)])
        let time = try #require(arrivals.first?.time)
        #expect(time >= 6 + RoomStage.giveUpAfter && time < 6.1 + RoomStage.giveUpAfter)   // 6 秒走到 (7, 4)，再等 4 秒
        #expect(stage.position(of: Self.ids[1]) == Tile(i: 7, j: 4).center)
        #expect(closest >= 0.999)
    }

    @Test func headOnTheyGetPastEachOther() throws {
        // 迎面走同一排：一隻停下來等，另一隻繞過去，最後都走到
        let stage = try Self.stage(positions: [Tile(i: 4, j: 4).center, Tile(i: 8, j: 4).center])
        stage.setIntent(.walk(to: Tile(i: 8, j: 4), pace: .walk), for: Self.ids[0], now: 0)
        stage.setIntent(.walk(to: Tile(i: 4, j: 4), pace: .walk), for: Self.ids[1], now: 0)
        var closest = Double.infinity
        let arrivals = try Self.run(stage, until: 30, closest: &closest)
        let tiles = Dictionary(uniqueKeysWithValues: arrivals.map { ($0.arrival.id, $0.arrival.tile) })
        #expect(tiles == [Self.ids[0]: Tile(i: 8, j: 4), Self.ids[1]: Tile(i: 4, j: 4)])
        #expect(closest >= 0.999)
    }

    @Test func twoPenguinsWanderWithoutBumpingIntoEachOther() throws {
        // 和 GameView 一樣接線：兩隻用 App 裡的 wander.json 一起閒晃 5 分鐘（固定亂數），從不疊在一起，也不會卡住
        let config = try #require(WanderConfig.bundled())
        let stage = try Self.stage()
        var behaviors = [PenguinBehavior(), PenguinBehavior()]
        var routines = Self.ids.map { _ in WanderRoutine(config: config, room: .indoor) }
        var tiles = Self.positions.map { Tile(containing: $0) }
        var rng = WanderTests.SeededGenerator(seed: 42)
        var arrivals = [0, 0]
        var closest = Double.infinity
        func send(_ n: Int, _ input: PenguinBehavior.Input, now: Double) {
            behaviors[n].handle(input)
            stage.setIntent(behaviors[n].intent, for: Self.ids[n], now: now, serial: behaviors[n].serial)
        }
        func wander(_ n: Int, now: Double) {
            var other = tiles[1 - n]
            if case .walk(let goal, _) = behaviors[1 - n].intent { other = goal }
            guard behaviors[n].intent == .idle,
                  let step = routines[n].next(from: tiles[n], others: [other], now: now, using: &rng) else { return }
            send(n, step.request, now: now)
        }
        for n in 0..<2 { wander(n, now: 0) }
        for frame in 1...(300 * 30) {
            let now = Double(frame) / 30
            let tick = stage.update(now: now)
            for arrival in tick.arrived {
                let n = try #require(Self.ids.firstIndex(of: arrival.id))
                tiles[n] = arrival.tile
                arrivals[n] += 1
                send(n, .arrived, now: now)
                wander(n, now: now)
            }
            for id in tick.motionFinished {
                let n = try #require(Self.ids.firstIndex(of: id))
                send(n, .motionFinished, now: now)
                wander(n, now: now)
            }
            let (a, b) = (try #require(stage.position(of: Self.ids[0])), try #require(stage.position(of: Self.ids[1])))
            closest = min(closest, ((a.i - b.i) * (a.i - b.i) + (a.j - b.j) * (a.j - b.j)).squareRoot())
        }
        #expect(closest >= 0.999)
        #expect(arrivals.allSatisfy { $0 >= 10 }, "走到的次數：\(arrivals)")
    }
}
