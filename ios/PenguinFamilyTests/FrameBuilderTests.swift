import CoreGraphics
import Testing
@testable import PenguinFamily

/// 畫面準備（ADR 0008）：要畫什麼與順序、內插、姿勢、點到哪一隻、拖曳、捏合、閒置後鏡頭回去、繪製清單。
/// 快照由測試自己做；用屋內箱庭、`VectorRigTests` 的 20×20 假角色（有斜向，腳底在 (10, 18)）與 `MotionClipTests` 的動作資料。
@MainActor
struct FrameBuilderTests {
    typealias Activity = SimulationSnapshot.Activity

    /// 後台名單的兩隻。
    static let ids = [CharacterID("first"), CharacterID("second")]
    /// 屋內的前兩個起點：第一隻腳底在 (192, 136)，第二隻在 (224, 136)。
    static let positions = [TilePosition(i: 4.5, j: 4.5), TilePosition(i: 5.5, j: 3.5)]
    static let iso = IsoProjection(room: .indoor)

    /// 假角色的動作資料：哈囉、慢與快的步態（`MotionClipTests.json`）。
    nonisolated static let motions = try! MotionClipTests.motions()

    /// iPhone 17 直拿：402×874pt、@3x。`withCharacter[i]` 為 false 的那隻沒有角色包（和 App 一樣換成替身）；
    /// `rig` 預設是有斜向的假角色。
    static func builder(withCharacter: [Bool] = [true, true], motions: [CharacterMotions] = [motions, motions],
                        rig: VectorRig? = nil, species: [Species] = [.penguin, .penguin]) throws -> FrameBuilder {
        let rig = try rig ?? VectorRigTests.rig(VectorRigTests.walkingJSON)
        let family = (0..<2).map { i in
            FamilyMember(id: ids[i], species: species[i],
                         character: withCharacter[i] ? LoadedCharacter(id: ids[i].rawValue, vector: rig, motions: motions[i]) : nil)
        }
        let cast = RoomScene.Member.cast(family, defaultWander: nil).map {
            FrameBuilder.CastMember(id: $0.id, vector: $0.vector, motions: $0.motions)
        }
        let builder = FrameBuilder(room: .indoor, cast: cast)
        builder.resize(viewport: CGSize(width: 402, height: 874), displayScale: 3)
        return builder
    }

    static func character(_ id: CharacterID, _ position: TilePosition, _ facing: Facing = .front,
                        _ activity: Activity = .still) -> SimulationSnapshot.Character {
        SimulationSnapshot.Character(id: id, position: position, facing: facing, activity: activity)
    }

    static func snapshot(_ characters: [SimulationSnapshot.Character], tick: Int = 0) -> SimulationSnapshot {
        SimulationSnapshot(tick: tick, characters: characters, isActive: false, wakeAt: nil)
    }

    /// 兩隻站在 `positions`。
    static let standing = snapshot(zip(ids, positions).map { character($0, $1) })

    /// 準備一格；沒給 `time` 時畫最新快照的時間點。
    @discardableResult
    static func build(_ builder: FrameBuilder, _ current: SimulationSnapshot, previous: SimulationSnapshot? = nil,
                      at time: Double? = nil, now: Double = 0) -> FrameBuilder.Frame {
        builder.build(previous: previous, current: current, at: time ?? current.time, now: now)
    }

    static func sprite(_ frame: FrameBuilder.Frame, _ id: CharacterID) -> FrameBuilder.Sprite? {
        frame.sprites.first { $0.key == .character(id) }
    }

    /// 箱庭圖上的一點在畫面上的位置（pt）。
    static func screenPoint(_ builder: FrameBuilder, x: Double, y: Double) throws -> CGPoint {
        let t = try #require(builder.viewTransform)
        return CGPoint(x: (x - t.topLeftX) * t.pointsPerUnit, y: (y - t.topLeftY) * t.pointsPerUnit)
    }

    /// 站在 `position` 的企鵝腳底上方 3 個單位（在牠的圖裡）在畫面上的位置。
    static func onCharacter(_ builder: FrameBuilder, at position: TilePosition) throws -> CGPoint {
        let feet = iso.feet(at: position)
        return try screenPoint(builder, x: feet.x, y: feet.y - 3)
    }

    /// 假角色往某個方向移動時，片段在第幾秒的樣子（翻轉的方向用來源的片段）。
    static func moving(_ pace: CharacterBehavior.Pace, _ facing: Facing, at t: Double,
                       motions: CharacterMotions = motions) throws -> CharacterPose {
        let source = try #require(try VectorRigTests.rig(VectorRigTests.walkingJSON).look(facing.rawValue)?.source)
        let gait = motions.gait(for: pace)
        return CharacterPose(facing: facing, parts: try #require(gait.clips[source]).poses(at: t, cycle: gait.cycle))
    }

    /// 哈囉第幾秒的樣子。
    static func hello(at t: Double, motions: CharacterMotions = motions) throws -> CharacterPose {
        let hello = try #require(motions.motion(named: "hello"))
        return CharacterPose(facing: .front, parts: try #require(hello.clips["front"]).poses(at: t))
    }

    /// 灰色剪影的畫布大小（假角色是 20×20）。
    static let placeholderCanvas = VectorRig.placeholder.front.canvas

    // MARK: - 畫什麼

    @Test func firstLookIsAtTheFirstCharacter() throws {
        // 作者 2026-11-19 決定：鏡頭優先看第一隻
        let builder = try Self.builder()
        Self.build(builder, Self.standing)
        let camera = try #require(builder.camera)
        #expect(camera.centerX == 192)        // 第一隻腳底的 x
        #expect(camera.centerY == 128)        // 箱庭比畫面矮，上下固定置中
        #expect(builder.zoom == 3)
    }

    @Test func cameraLooksAtTheNextOneWhenTheFirstIsNotOnStage() throws {
        let builder = try Self.builder()
        Self.build(builder, Self.snapshot([Self.character(Self.ids[1], Self.positions[1])]))
        #expect(builder.camera?.centerX == 224)
    }

    @Test func drawsBackgroundFirstThenByDepth() throws {
        let builder = try Self.builder(withCharacter: [true, false])
        let frame = Self.build(builder, Self.standing)
        #expect(frame.sprites.first?.key == .background)
        #expect(frame.sprites.count == 1 + RoomLayout.indoor.furniture.count + 2)
        #expect(Self.sprite(frame, Self.ids[0])?.width == 20)
        #expect(Self.sprite(frame, Self.ids[1])?.width == 20)      // 第二隻沒有角色包：借第一隻的形狀塗灰
        // 床在企鵝後面（深度較小），先畫
        let bed = try #require(RoomLayout.indoor.furniture.firstIndex { $0.kind == .bed })
        let bedIndex = try #require(frame.sprites.firstIndex { $0.key == .furniture(bed) })
        let penguinIndex = try #require(frame.sprites.firstIndex { $0.key == .character(Self.ids[0]) })
        #expect(bedIndex < penguinIndex)
    }

    @Test func everyItemCanBeDrawn() throws {
        let builder = try Self.builder(withCharacter: [true, false])
        #expect(builder.rigs().count == 2)
        #expect(builder.polygons().count == 1 + RoomLayout.indoor.furniture.count)
        var snapshots = stride(from: 0.0, through: Self.motions.motion(named: "hello")!.duration, by: 0.05).map { t in
            (Self.snapshot([Self.character(Self.ids[0], Self.positions[0], .front, .motion(.hello, since: 0)),
                            Self.character(Self.ids[1], Self.positions[1])]), t)
        }
        for facing in Facing.oblique {
            snapshots += stride(from: 0.0, through: 2, by: 0.1).map { t in
                (Self.snapshot([Self.character(Self.ids[0], Self.positions[0], facing, .moving(.fast, elapsed: t)),
                                Self.character(Self.ids[1], Self.positions[1], facing, .moving(.slow, elapsed: t))]), t)
            }
        }
        for (snapshot, time) in snapshots {
            let list = try #require(Self.build(builder, snapshot, at: time).drawList)
            #expect(list.items.count == 1 + RoomLayout.indoor.furniture.count + 2)
            for item in list.items {
                switch item {
                case .polygons(let key):
                    #expect(builder.polygons()[key] != nil, "\(key) 畫不出來")
                case .character(let id, let look, let parts):
                    let facing = try #require(builder.rigs()[id]?.facings[look], "\(id.rawValue) 沒有 \(look) 的圖")
                    #expect(parts.allSatisfy { facing.parts[$0.name] != nil })
                case .effect(let name, _, _):
                    #expect(builder.effectLibrary().effects[name] != nil, "沒有特效 \(name) 的形狀")
                }
            }
        }
    }

    @Test func placeholdersWhenNoCharacters() throws {
        let builder = try Self.builder(withCharacter: [false, false])
        let frame = Self.build(builder, Self.standing)
        for id in Self.ids {
            let sprite = try #require(Self.sprite(frame, id))
            #expect(sprite.width == Self.placeholderCanvas.width && sprite.height == Self.placeholderCanvas.height)
            #expect(builder.rigs()[id]?.front.canvas == Self.placeholderCanvas)
        }
    }

    @Test func missingPackBorrowsTheOtherShapeInGray() throws {
        // 作者 2026-11-19 決定：第二隻沒有角色包時，借第一隻的形狀塗灰，斜向與走路都和第一隻一樣
        let builder = try Self.builder(withCharacter: [true, false])
        let standIn = try #require(builder.rigs()[Self.ids[1]])
        #expect(standIn.outline.color == VectorRig.placeholderOutline)
        #expect(Set(standIn.facings.keys) == Set(try VectorRigTests.rig(VectorRigTests.walkingJSON).facings.keys))
        let frame = Self.build(builder, Self.snapshot([
            Self.character(Self.ids[1], TilePosition(i: 5.0, j: 3.5), .frontRight, .moving(.slow, elapsed: 1)),
        ]))
        #expect(Self.sprite(frame, Self.ids[1])?.pose == (try Self.moving(.slow, .frontRight, at: 1)))   // 斜著走，用借來的動作
        // 第一隻沒有、第二隻有時也一樣：替身借第二隻的形狀
        let flipped = try Self.builder(withCharacter: [false, true])
        #expect(flipped.rigs()[Self.ids[0]]?.outline.color == VectorRig.placeholderOutline)
        #expect(flipped.rigs()[Self.ids[0]]?.facings.count == standIn.facings.count)
    }

    @Test func standInOnlyBorrowsFromTheSameSpecies() throws {
        // ADR 0009：第二隻是別種動物、沒有角色包時，不借第一隻的形狀，用灰色剪影
        let builder = try Self.builder(withCharacter: [true, false], species: [.penguin, Species("shark")])
        #expect(builder.rigs()[Self.ids[1]]?.front.canvas == Self.placeholderCanvas)
        let frame = Self.build(builder, Self.standing)
        #expect(Self.sprite(frame, Self.ids[1])?.width == Self.placeholderCanvas.width)
    }

    // MARK: - 姿勢

    @Test func eachCharacterMovesWithItsOwnMotions() throws {
        // 作者 2026-11-19 決定：怎麼動每隻各一份；改第二隻的片段，第一隻照舊
        var quick = Self.motions
        quick.gaits.slow.cycle = 0.5
        quick.motions["hello"]?.clips["front"] = MotionClip(tracks: ["arm": [MotionClipTests.key(0, 0), MotionClipTests.key(2, -40)]])
        let builder = try Self.builder(motions: [Self.motions, quick])
        let hello = Self.build(builder, Self.snapshot([
            Self.character(Self.ids[0], Self.positions[0], .front, .motion(.hello, since: 0)),
            Self.character(Self.ids[1], Self.positions[1], .front, .motion(.hello, since: 0)),
        ]), at: 1)
        #expect(Self.sprite(hello, Self.ids[0])?.pose == (try Self.hello(at: 1)))
        #expect(Self.sprite(hello, Self.ids[1])?.pose == (try Self.hello(at: 1, motions: quick)))
        #expect(Self.sprite(hello, Self.ids[1])?.pose?.parts["arm"]?.rotate == -20)
        let walk = Self.build(builder, Self.snapshot([
            Self.character(Self.ids[0], Self.positions[0], .frontRight, .moving(.slow, elapsed: 1)),
            Self.character(Self.ids[1], Self.positions[1], .frontRight, .moving(.slow, elapsed: 1)),
        ]))
        #expect(Self.sprite(walk, Self.ids[0])?.pose == (try Self.moving(.slow, .frontRight, at: 1)))
        #expect(Self.sprite(walk, Self.ids[1])?.pose == (try Self.moving(.slow, .frontRight, at: 1, motions: quick)))
    }

    @Test func helloPoseFollowsTheTimeEveryFrame() throws {
        // ADR 0007：每一格照時間轉；ADR 0008：用畫的時間（比模擬晚一個節拍）
        let builder = try Self.builder()
        let hello = Self.snapshot([Self.character(Self.ids[0], Self.positions[0], .front, .motion(.hello, since: 10))], tick: 316)
        #expect(Self.sprite(Self.build(builder, hello, at: 10.5), Self.ids[0])?.pose == (try Self.hello(at: 0.5)))
        #expect(Self.sprite(Self.build(builder, hello, at: 10.51), Self.ids[0])?.pose == (try Self.hello(at: 10.51 - 10)))
        #expect(Self.sprite(Self.build(builder, hello, at: 9.99), Self.ids[0])?.pose == (try Self.hello(at: 0)))   // 還沒開始
        let still = try #require(Self.sprite(Self.build(builder, Self.standing), Self.ids[0]))
        // 角色畫布的腳底對到站的點：(192, 136) − (10, 18)
        #expect(still.x == 182 && still.y == 118 && still.width == 20 && still.height == 20 && still.pose == CharacterPose(facing: .front))
    }

    @Test func obliqueSpriteAlsoPutsTheFeetOnThePoint() throws {
        let builder = try Self.builder()
        let position = TilePosition(i: 5.0, j: 4.5)
        let frame = Self.build(builder, Self.snapshot([Self.character(Self.ids[0], position, .frontRight, .moving(.slow, elapsed: 1))]))
        let sprite = try #require(Self.sprite(frame, Self.ids[0]))
        let feet = Self.iso.feet(at: position)
        #expect(sprite.x == feet.x - 10 && sprite.y == feet.y - 18)
        #expect(sprite.pose == (try Self.moving(.slow, .frontRight, at: 1)))
        // 站著、等別隻讓路時是站姿：每個部件在原位
        let still = Self.build(builder, Self.snapshot([Self.character(Self.ids[0], position, .backRight)]))
        #expect(Self.sprite(still, Self.ids[0])?.pose == CharacterPose(facing: .backRight))
        // 這個方向沒有片段（快步只有左前的片段）：照樣移動，部件在原位
        let noClip = Self.build(builder, Self.snapshot([Self.character(Self.ids[0], position, .backLeft, .moving(.fast, elapsed: 1))]))
        #expect(Self.sprite(noClip, Self.ids[0])?.pose == CharacterPose(facing: .backLeft))
    }

    @Test func placeholderSlidesAlongFacingTheFront() throws {
        // 灰色剪影沒有斜向：面向鏡頭平移
        let builder = try Self.builder(withCharacter: [false, false])
        let frame = Self.build(builder, Self.snapshot([
            Self.character(Self.ids[0], TilePosition(i: 5.5, j: 4.5), .frontRight, .moving(.slow, elapsed: 2)),
        ]))
        let sprite = try #require(Self.sprite(frame, Self.ids[0]))
        #expect(sprite.pose == CharacterPose(facing: .front) && sprite.width == Self.placeholderCanvas.width)
    }

    @Test func rigWithoutObliquesFacesTheFrontWhileWalking() throws {
        let builder = try Self.builder(rig: try VectorRigTests.rig())               // 只有正面的假角色
        let frame = Self.build(builder, Self.snapshot([
            Self.character(Self.ids[0], TilePosition(i: 5.0, j: 4.5), .frontRight, .moving(.slow, elapsed: 1)),
        ]))
        #expect(Self.sprite(frame, Self.ids[0])?.pose == CharacterPose(facing: .front))
    }

    // MARK: - 內插（ADR 0008）

    @Test func interpolatesBetweenTwoSnapshots() throws {
        let builder = try Self.builder()
        let step = 1.0 / Double(Simulation.ticksPerSecond)
        let before = Self.snapshot([Self.character(Self.ids[0], TilePosition(i: 5.0, j: 4.5), .frontRight,
                                                 .moving(.slow, elapsed: 1))], tick: 30)
        let after = Self.snapshot([Self.character(Self.ids[0], TilePosition(i: 5.0 + step / 2, j: 4.5), .frontRight,
                                                .moving(.slow, elapsed: 1 + step))], tick: 31)
        let time = before.time + step / 2                                          // 兩份快照中間
        let sprite = try #require(Self.sprite(Self.build(builder, after, previous: before, at: time), Self.ids[0]))
        let alpha = (time - before.time) / (after.time - before.time)
        let feet = Self.iso.feet(at: TilePosition(i: 5.0 + step / 2 * alpha, j: 4.5))
        #expect(abs(sprite.x - (feet.x - 10)) < 1e-9 && abs(sprite.y - (feet.y - 18)) < 1e-9)
        #expect(sprite.pose == (try Self.moving(.slow, .frontRight, at: 1 + (1 + step - 1) * alpha)))
    }

    @Test func holdsTheLatestSnapshotWhenTheSimulationFallsBehind() throws {
        let builder = try Self.builder()
        let before = Self.snapshot([Self.character(Self.ids[0], TilePosition(i: 5.0, j: 4.5))], tick: 30)
        let after = Self.snapshot([Self.character(Self.ids[0], TilePosition(i: 5.1, j: 4.5))], tick: 31)
        let late = try #require(Self.sprite(Self.build(builder, after, previous: before, at: 5), Self.ids[0]))
        #expect(abs(late.x - (Self.iso.feet(at: TilePosition(i: 5.1, j: 4.5)).x - 10)) < 1e-9)   // 不往前猜，停在最新的
    }

    @Test func newcomersAndRestartedWalksUseTheLatestSnapshot() throws {
        let builder = try Self.builder()
        let before = Self.snapshot([Self.character(Self.ids[0], Self.positions[0], .frontRight, .moving(.slow, elapsed: 3))], tick: 30)
        let after = Self.snapshot([
            Self.character(Self.ids[0], Self.positions[0], .backLeft, .moving(.slow, elapsed: 0)),   // 重新起步：步態不往回算
            Self.character(Self.ids[1], Self.positions[1]),                                           // 剛上台：沒有上一份
        ], tick: 31)
        let frame = Self.build(builder, after, previous: before, at: before.time + 0.5 / Double(Simulation.ticksPerSecond))
        #expect(Self.sprite(frame, Self.ids[0])?.pose == (try Self.moving(.slow, .backLeft, at: 0)))
        #expect(Self.sprite(frame, Self.ids[1])?.x == Self.iso.feet(at: Self.positions[1]).x - 10)
    }

    // MARK: - 繪製清單

    @Test func drawListOnlyChangesWhenSomethingChanges() throws {
        let builder = try Self.builder()
        let first = try #require(Self.build(builder, Self.standing, now: 0).drawList)
        #expect(Self.build(builder, Self.standing, now: 1.0 / 60).drawList == first)     // 沒變：不用重畫
        builder.panChanged(translation: CGSize(width: 30, height: 0), startLocation: .zero, now: 1)
        #expect(Self.build(builder, Self.standing, now: 1).drawList != first)          // 鏡頭動了
    }

    @Test func drawListPutsThePartsOnTheScreen() throws {
        // 站好的企鵝：身體的矩陣把畫布上的腳底 (10, 18) 放到腳底在畫面上的位置
        let builder = try Self.builder()
        let list = try #require(Self.build(builder, Self.standing).drawList)
        let transform = try #require(builder.viewTransform)
        guard case .character(_, let look, let parts)? = list.items.first(where: {
            if case .character(Self.ids[0], _, _) = $0 { return true }
            return false
        }) else { Issue.record("第一隻不在繪製清單裡"); return }
        #expect(look == "front")
        let body = try #require(parts.first { $0.name == "body" })
        let feet = body.transform.apply(10, 18)
        #expect(abs(feet.x - (192 - transform.topLeftX) * 3) < 1e-9 && abs(feet.y - (136 - transform.topLeftY) * 3) < 1e-9)
        #expect(list.viewportWidth == 402 && list.pointsPerUnit == 3)
    }

    // MARK: - 點擊

    @Test func tapFindsWhichCharacter() throws {
        let builder = try Self.builder(withCharacter: [true, false])
        Self.build(builder, Self.standing)
        #expect(builder.character(at: try Self.onCharacter(builder, at: Self.positions[0])) == Self.ids[0])
        #expect(builder.character(at: try Self.onCharacter(builder, at: Self.positions[1])) == Self.ids[1])   // 替身也點得到
        #expect(builder.character(at: .zero) == nil)
    }

    @Test func frontCharacterWinsWhenOverlapping() throws {
        // 站在同一點：後上台的畫在後面，也就是在前面
        let same = try Self.builder()
        Self.build(same, Self.snapshot(Self.ids.map { Self.character($0, Self.positions[0]) }))
        #expect(same.character(at: try Self.onCharacter(same, at: Self.positions[0])) == Self.ids[1])
        // 第一隻離主人比較近（畫面比較下方）：牠在前面
        let nearer = try Self.builder()
        let near = TilePosition(i: 4.7, j: 4.7)
        Self.build(nearer, Self.snapshot([Self.character(Self.ids[0], near), Self.character(Self.ids[1], Self.positions[0])]))
        #expect(Self.iso.feet(at: near).y > Self.iso.feet(at: Self.positions[0]).y)
        #expect(nearer.character(at: try Self.onCharacter(nearer, at: Self.positions[0])) == Self.ids[0])
    }

    @Test func backstageCharacterIsNotDrawnButItsImagesAreReady() throws {
        let builder = try Self.builder()
        let frame = Self.build(builder, Self.snapshot([Self.character(Self.ids[0], Self.positions[0])]))   // 第二隻在後台
        #expect(Self.sprite(frame, Self.ids[1]) == nil)
        #expect(builder.rigs()[Self.ids[1]] != nil)                                  // 造型先準備好，上台時不用再載入
        #expect(builder.character(at: try Self.onCharacter(builder, at: Self.positions[1])) == nil)
        #expect(builder.camera?.centerX == 192)                                      // 鏡頭只看台上的那一隻
    }

    // MARK: - 拖曳與捏合

    @Test func dragMovesTheCameraTheOtherWay() throws {
        let builder = try Self.builder()
        Self.build(builder, Self.standing)
        let start = try #require(builder.camera?.centerX)
        var woke = 0
        builder.onChange = { woke += 1 }
        builder.panChanged(translation: CGSize(width: 30, height: 0), startLocation: .zero, now: 0)
        #expect(builder.camera?.centerX == start - 10)    // 30pt ÷ 每單位 3pt
        builder.panChanged(translation: CGSize(width: 45, height: 0), startLocation: .zero, now: 0)
        #expect(builder.camera?.centerX == start - 15)    // 只套用這一下多移的 15pt
        builder.panEnded(now: 0)
        #expect(woke == 3)                                // 有變化就叫醒遊戲迴圈
    }

    @Test func dragStartingOnEitherCharacterDoesNotScroll() throws {
        for (id, position) in zip(Self.ids, Self.positions) {
            let builder = try Self.builder()
            Self.build(builder, Self.standing)
            let before = builder.camera
            builder.panChanged(translation: CGSize(width: 30, height: 0),
                               startLocation: try Self.onCharacter(builder, at: position), now: 0)
            #expect(builder.camera == before, "從 \(id.rawValue) 身上開始拖")
        }
    }

    @Test func pinchStaysInRangeAndStopsWhereReleased() throws {
        let builder = try Self.builder()
        let anchor = CGPoint(x: 201, y: 437)
        builder.pinchChanged(magnification: 0.5, anchor: anchor, now: 0)
        #expect(builder.zoom == 1.5)
        builder.pinchChanged(magnification: 0.1, anchor: anchor, now: 0)
        #expect(builder.zoom == 402.0 / Double(Self.iso.canvasWidth))                // 最小：房間左右塞滿畫面
        builder.pinchEnded(magnification: 0.45, anchor: anchor, now: 0)
        #expect(builder.zoom == 1.35)                                                // 向量不用吸附，停在放開時的倍率
    }

    // MARK: - 閒置後鏡頭回去

    @Test func cameraReturnsToTheFirstCharacterAfterIdle() throws {
        let builder = try Self.builder()
        Self.build(builder, Self.standing, now: 99)
        let home = try #require(builder.camera)
        builder.panChanged(translation: CGSize(width: 150, height: 0), startLocation: .zero, now: 100)
        builder.panEnded(now: 100)
        Self.build(builder, Self.standing, now: 100)
        let waiting = Self.build(builder, Self.standing, now: 101)
        #expect(!waiting.keepRunning)
        #expect(waiting.wakeAt == 100 + FrameBuilder.idleSecondsBeforeReturn)
        #expect(builder.camera != home)

        var now = 105.0
        var frame = Self.build(builder, Self.standing, now: now)
        #expect(frame.keepRunning)
        var frames = 0
        while frame.keepRunning && frames < 600 {
            now += 1.0 / 60
            frame = Self.build(builder, Self.standing, now: now)
            frames += 1
        }
        #expect(builder.camera == home)
        #expect(frames < 600)
    }

    @Test func touchingAgainPostponesTheReturn() throws {
        let builder = try Self.builder()
        Self.build(builder, Self.standing)
        builder.panChanged(translation: CGSize(width: 150, height: 0), startLocation: .zero, now: 0)
        builder.panEnded(now: 0)
        builder.ownerTouched(now: 4)
        #expect(Self.build(builder, Self.standing, now: 5).wakeAt == 4 + FrameBuilder.idleSecondsBeforeReturn)
    }

    // MARK: - 家具前後

    @Test func penguinBesideTheSofaIsDrawnInFront() throws {
        // 沙發佔 i = 7、j = 6～8，最靠近主人的角很低；站在它右前方 (8, 7) 的企鵝要畫在沙發前面
        let sofa = try #require(RoomLayout.indoor.furniture.firstIndex { $0.kind == .sofa })
        func order(at position: TilePosition) throws -> (sofa: Int, penguin: Int) {
            let frame = Self.build(try Self.builder(), Self.snapshot([Self.character(Self.ids[0], position)]))
            return (try #require(frame.sprites.firstIndex { $0.key == .furniture(sofa) }),
                    try #require(frame.sprites.firstIndex { $0.key == .character(Self.ids[0]) }))
        }
        let beside = try order(at: Tile(i: 8, j: 7).center)
        #expect(beside.penguin > beside.sofa)
        let behind = try order(at: Tile(i: 6, j: 7).center)                          // 左後方：在沙發後面
        #expect(behind.penguin < behind.sofa)
        let between = try order(at: TilePosition(i: 8.5, j: 7.0))                     // 走在兩格中間也一樣
        #expect(between.penguin > between.sofa)
    }

    @Test func relationToFurnitureByTiles() {
        let sofa = TileRect(x: 7, y: 6, width: 1, height: 3)
        #expect(FrameBuilder.relation(of: Tile(i: 8, j: 7).center, to: sofa) == .front)
        #expect(FrameBuilder.relation(of: Tile(i: 7, j: 9).center, to: sofa) == .front)
        #expect(FrameBuilder.relation(of: Tile(i: 6, j: 7).center, to: sofa) == .behind)
        #expect(FrameBuilder.relation(of: Tile(i: 7, j: 5).center, to: sofa) == .behind)
        #expect(FrameBuilder.relation(of: Tile(i: 8, j: 5).center, to: sofa) == .unknown)   // 斜對角
    }

    // MARK: - 換部件與特效（ADR 0010）

    /// 有閉眼部件的假角色與第 3 版的動作，加上一個特效 z（只用轉軸）。
    static func dozingBuilder() throws -> FrameBuilder {
        let rig = try VectorRigTests.rig(VectorRigTests.dozingJSON)
        let motions = try MotionClipTests.motions(MotionClipTests.v3JSON)
        let z = VectorRig.Part(pivot: .init(x: 0, y: 0), silhouette: [],
                               layers: [.init(fill: "#525e70", stroke: nil, width: nil, shapes: [.ellipse(cx: 0, cy: 0, rx: 1, ry: 1)], clip: nil)])
        let builder = FrameBuilder(room: .indoor, cast: [.init(id: ids[0], vector: rig, motions: motions)],
                                   effects: EffectLibrary(effects: ["z": z]))
        builder.resize(viewport: CGSize(width: 402, height: 874), displayScale: 3)
        return builder
    }

    @Test func hiddenPartsAndEffectsFollowTheClip() throws {
        let builder = try Self.dozingBuilder()
        func items(_ activity: Activity, at time: Double) throws -> [DrawList.Item] {
            try #require(Self.build(builder, Self.snapshot([Self.character(Self.ids[0], Self.positions[0], .front, activity)]),
                                    at: time).drawList).items
        }
        /// 角色後面緊接著的特效（在家具前後都一樣）。
        func effects(_ items: [DrawList.Item]) -> [(name: String, m: Affine2D, alpha: Double)] {
            guard let at = items.firstIndex(where: { if case .character = $0 { true } else { false } }) else { return [] }
            return items[(at + 1)...].prefix { if case .effect = $0 { true } else { false } }.compactMap {
                guard case .effect(let name, let m, let alpha) = $0 else { return nil }
                return (name, m, alpha)
            }
        }
        func parts(_ items: [DrawList.Item]) -> [String] {
            items.flatMap { item -> [String] in
                guard case .character(_, _, let parts) = item else { return [] }
                return parts.map(\.name)
            }
        }
        // 站著：閉眼藏起來，沒有特效
        let still = try items(.still, at: 0)
        #expect(parts(still) == ["body", "arm", "head"])
        #expect(!still.contains { if case .effect = $0 { true } else { false } })
        // 打瞌睡第 1 秒：閉眼顯示，Z 緊接在角色後面、不透明
        let dozing = try items(.motion(.doze, since: 0), at: 1)
        #expect(parts(dozing) == ["body", "arm", "head", "eyesClosed"])
        let z = effects(dozing)
        #expect(z.map(\.name) == ["z"] && z.first?.alpha == 1)
        #expect(dozing.filter { if case .effect = $0 { true } else { false } }.count == 1)
        // 循環：第 0 秒的 Z 看不到；第 2.5 秒和第 0.5 秒一樣（半透明）
        #expect(effects(try items(.motion(.doze, since: 0), at: 0)).isEmpty)
        let later = effects(try items(.motion(.doze, since: 0), at: 2.5))
        let earlier = effects(try items(.motion(.doze, since: 0), at: 0.5))
        #expect(later.count == 1 && earlier.count == 1)
        if let a = later.first, let b = earlier.first {
            #expect(abs(a.alpha - 0.5) < 1e-12 && a.alpha == b.alpha && a.m == b.m)
        }
    }
}
