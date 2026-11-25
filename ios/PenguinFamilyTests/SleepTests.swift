import CoreGraphics
import Foundation
import Testing
@testable import PenguinFamily

/// 去床上睡（A1 第 13 項，ADR 0011；作者 2026-11-24 決定）：狀態機、閒晃照睏意決定、床位先到先選、上床與下床的位移、
/// 睡飽與被點醒、落地的格子被佔住、姿勢的造型與觸控範圍、畫在床的前面。
struct SleepTests {
    // MARK: - 狀態機

    @Test func climbsInSleepsAndGetsUpRested() {
        #expect(DozeTests.intents([.sleepRequested, .motionFinished, .motionFinished, .sleepEnded, .motionFinished])
                == [.climbIn, .sleep, .sleep, .wakeRested, .idle])
    }

    @Test func tapWakesASleeperButIsIgnoredWhileClimbing() {
        // 上床、下床途中被點不理（作者 2026-11-24 決定）
        #expect(DozeTests.intents([.sleepRequested, .ownerTapped, .motionFinished, .ownerTapped, .ownerTapped, .motionFinished])
                == [.climbIn, .climbIn, .sleep, .wakeTapped, .wakeTapped, .idle])
        #expect(DozeTests.intents([.sleepRequested, .motionFinished, .sleepEnded, .ownerTapped]) == [.climbIn, .sleep, .wakeRested, .wakeRested])
    }

    @Test func aSleeperTakesNoOtherRequests() {
        #expect(DozeTests.intents([.sleepRequested, .motionFinished, .dozeRequested, .dozeEnded, .sleepRequested,
                                   .moveRequested(to: Tile(i: 1, j: 1), pace: .slow)])
                == [.climbIn, .sleep, .sleep, .sleep, .sleep, .sleep])
        #expect(DozeTests.intents([.sleepEnded]) == [.idle])
    }

    // MARK: - 閒晃照睏意決定

    static let here = Tile(i: 4, j: 4)
    static let slots = RoomLayout.indoor.slotIDs

    /// 睡覺：90 有 50%、每多 5 加 25%；每分鐘降 60（每秒 1）。打瞌睡：60 以上一定打（`doze` 是 0 時不打）。
    /// 閒晃只有發呆 5 秒（`idle` 時什麼都不做，一直待機）。
    static func config(start: Double = 100, wakeBelow: Double = 80, doze: Double = 0, idle: Bool = false, cooldown: Double = 1000) -> WanderConfig {
        WanderConfig(version: 4, pace: .init(slow: 1, fast: 0),
                     activities: [WanderTests.activity("z", .zoneOut, weight: idle ? 0 : 1, seconds: 5...5)],
                     sleepiness: .init(start: start...start, risePerMinute: .init(still: 0, slow: 0, fast: 0),
                                       doze: .init(above: 60, chance: doze, fallPerMinute: 60, wakeBelow: 50, cooldown: 0),
                                       sleep: .init(above: 90, chance: 0.5, fallPerMinute: 60, wakeBelow: wakeBelow, cooldown: cooldown,
                                                    chanceRise: .init(every: 5, add: 0.25))))
    }

    /// 作者 2026-11-24 決定：90 有 50%，100 一定去。
    @Test func sleepChanceIsHalfAtNinetyAndCertainAtAHundred() {
        let sleep = Self.config().sleepiness!.sleep!
        #expect(sleep.chance(at: 89.9) == 0)
        #expect(sleep.chance(at: 90) == 0.5 && sleep.chance(at: 94.9) == 0.5)
        #expect(sleep.chance(at: 95) == 0.75)
        #expect(sleep.chance(at: 100) == 1)
    }

    /// App 裡的預設與每個角色包的數字就是作者決定的。
    @Test func bundledNumbersMatchTheDecision() throws {
        let packs = VectorPackParityTests.allPacks.compactMap { try? CharacterPackLibrary.load($0).wander }
        for config in [try #require(WanderConfig.bundled())] + packs {
            let sleepiness = try #require(config.sleepiness), sleep = try #require(sleepiness.sleep)
            #expect(sleep.chance(at: 90) == 0.5 && sleep.chance(at: 100) == 1 && sleep.chance(at: 89) == 0)
            #expect(sleepiness.doze.cooldown == 600)
        }
    }

    @Test func wanderWalksToTheNearestFreeBedAndClimbsIn() throws {
        var rng = WanderTests.SeededGenerator(seed: 3)
        var routine = WanderRoutine(config: Self.config(), room: .indoor)
        // (4, 4) 離第二個床位的 (3, 3) 2 步，離第一個床位的 (3, 1) 4 步
        #expect(routine.next(from: Self.here, now: 0, sleepiness: 100, freeSlots: Self.slots, using: &rng)
                == .move(to: Tile(i: 3, j: 3), pace: .slow))
        #expect(routine.activity == "sleep")
        #expect(routine.next(from: Tile(i: 3, j: 3), now: 5, sleepiness: 100, freeSlots: Self.slots, using: &rng) == .sleep)
        // 那一格被別隻站著：用第二個選擇 (3, 2)
        var blocked = WanderRoutine(config: Self.config(), room: .indoor)
        #expect(blocked.next(from: Self.here, others: [Tile(i: 3, j: 3)], now: 0, sleepiness: 100, freeSlots: Self.slots, using: &rng)
                == .move(to: Tile(i: 3, j: 2), pace: .slow))
        // 只剩第一個床位
        var first = WanderRoutine(config: Self.config(), room: .indoor)
        #expect(first.next(from: Self.here, now: 0, sleepiness: 100, freeSlots: [Self.slots[0]], using: &rng)
                == .move(to: Tile(i: 3, j: 1), pace: .slow))
    }

    @Test func wanderDozesInsteadWhenThereIsNoBed() {
        var rng = WanderTests.SeededGenerator(seed: 3)
        var routine = WanderRoutine(config: Self.config(doze: 1), room: .indoor)
        #expect(routine.next(from: Self.here, now: 0, sleepiness: 100, freeSlots: [], using: &rng) == .doze)
        #expect(routine.next(from: Self.here, now: 0, sleepiness: 89, freeSlots: Self.slots, using: &rng) == .doze)   // 還沒到睡覺的門檻
        routine.sleepEnded(at: 100)                                                                                    // 冷卻中
        #expect(routine.next(from: Self.here, now: 101, sleepiness: 100, freeSlots: Self.slots, using: &rng) == .doze)
    }

    @Test func sleepNumbersMustMakeSense() {
        func problem(_ change: (inout WanderConfig.SleepinessConfig.Rest) -> Void) -> WanderConfigError? {
            var config = Self.config()
            change(&config.sleepiness!.sleep!)
            do {
                try config.validate()
                return nil
            } catch {
                return error as? WanderConfigError
            }
        }
        #expect(problem { _ in } == nil)
        #expect(problem { $0.wakeBelow = 95 } == .invalid("sleepiness.sleep.above"))
        #expect(problem { $0.chance = 2 } == .invalid("sleepiness.sleep.chance"))
        #expect(problem { $0.fallPerMinute = 0 } == .invalid("sleepiness.sleep.fallPerMinute"))
    }

    // MARK: - 箱庭的床

    @Test func bedSlotsMustBeOnTheBedAndReachable() {
        #expect(RoomLayout.indoor.slotIDs.count == 2)
        func problems(_ slot: FurnitureSlot) -> [String] {
            RoomLayout(widthTiles: 6, depthTiles: 6, wallHeight: 40, furniture: [
                Furniture(kind: .bed, footprint: TileRect(x: 0, y: 0, width: 3, height: 3), height: 10, slots: [slot]),
            ], wallItems: []).problems()
        }
        let good = FurnitureSlot(position: TilePosition(i: 1.5, j: 1), edge: TilePosition(i: 2.5, j: 1), entries: [Tile(i: 3, j: 1)])
        #expect(problems(good).isEmpty)
        #expect(problems(FurnitureSlot(position: good.position, edge: TilePosition(i: 3.5, j: 1), entries: good.entries))
                == ["bed 的第 1 個位置不在家具上"])
        #expect(problems(FurnitureSlot(position: good.position, edge: good.edge, entries: [])) == ["bed 的第 1 個位置上不去"])
        #expect(problems(FurnitureSlot(position: good.position, edge: good.edge, entries: [Tile(i: 2, j: 1)])) == ["bed 的第 1 個位置上不去"])
    }

    // MARK: - 動作資料（第 4 版）

    /// 上床 2 秒：跳上床 1 秒（多跳 5）、走到床位 1 秒、躺下 0.5 秒；睡覺 2 秒一個循環；被點醒與睡飽各是坐 1 秒、走到床邊 1 秒、跳下床 1 秒。
    static let motionJSON = """
    { "version": 4,
      "motions": {
        "hello": { "duration": 1, "facing": "front", "clips": {} },
        "sitDown": { "duration": 1 }, "doze": { "cycle": 2 }, "standUp": { "duration": 1 }, "wakeStartled": { "duration": 1 },
        "climbIn": { "stages": [
          { "look": "backLeft", "duration": 1, "clip": { "tracks": {} },
            "travel": { "from": "entry", "to": "edge", "keys": [[0, 0, 0], [0.5, 0.5, 5], [1, 1, 0]] } },
          { "look": "backLeft", "duration": 1, "clip": { "tracks": { "head": [[0, 10, 1, 1, 0, 0]] } },
            "travel": { "from": "edge", "to": "slot", "keys": [[0, 0, 0], [1, 1, 0]] } },
          { "look": "lie", "duration": 0.5, "clip": { "tracks": {} } } ] },
        "sleep": { "cycle": 2, "look": "lie", "clips": { "lie": { "tracks": { "body": [[0, 0, 1, 1, 0, 0], [1, 0, 1, 1.1, 0, 0]] } } } },
        "wakeTapped": { "stages": \(wakeStages) }, "wakeRested": { "stages": \(wakeStages) } },
      "gaits": { "slow": { "tilesPerSecond": 0.5, "cycle": 1 }, "fast": { "tilesPerSecond": 1, "cycle": 0.5 } } }
    """
    static let wakeStages = """
    [ { "look": "front", "duration": 1, "clip": { "tracks": {} } },
      { "look": "frontRight", "duration": 1, "clip": { "tracks": { "head": [[0, 0, 1, 1, 0, 0], [1, 30, 1, 1, 0, 0]] } },
        "travel": { "from": "slot", "to": "edge", "keys": [[0, 0, 0], [1, 1, 0]] } },
      { "look": "frontRight", "duration": 1, "clip": { "tracks": {} },
        "travel": { "from": "edge", "to": "entry", "keys": [[0, 0, 0], [1, 1, 0]] } } ]
    """
    static let motions = try! CharacterMotions.decode(Data(motionJSON.utf8))

    /// 假角色加上躺著的姿勢：30×20，放在床位那一點是 (15, 12)；身體、頭，與平常藏起來的眼睛。
    static let lyingJSON = String(VectorRigTests.walkingJSON.dropLast(1)) + """
    , "postures": { "lie": { "canvas": { "width": 30, "height": 20 }, "feet": { "x": 15, "y": 12 }, "drawOrder": ["body", "head", "eyes"],
      "parts": {
        "body": { "pivot": { "x": 15, "y": 12 }, "silhouette": [{ "ellipse": [18, 10, 8, 5] }], "layers": [{ "fill": "#baccdc", "shapes": [{ "ellipse": [18, 10, 8, 5] }] }] },
        "head": { "pivot": { "x": 8, "y": 8 }, "silhouette": [{ "ellipse": [8, 8, 5, 5] }], "layers": [{ "fill": "#baccdc", "shapes": [{ "ellipse": [8, 8, 5, 5] }] }] },
        "eyes": { "pivot": { "x": 8, "y": 8 }, "hidden": true, "silhouette": [], "layers": [{ "fill": "#26262c", "shapes": [{ "ellipse": [8, 8, 1, 1] }] }] } },
      "shadow": { "color": "#5a4636", "opacity": 0.16, "shapes": [{ "ellipse": [16, 13, 9, 4] }] },
      "touch": [{ "x": 2, "y": 2 }, { "x": 12, "y": 2 }, { "x": 28, "y": 10 }, { "x": 24, "y": 17 }, { "x": 10, "y": 16 }] } } }
    """

    static func lyingRig() throws -> VectorRig { try VectorRigTests.rig(lyingJSON) }

    @Test func stagedMotionsReadAndAddUp() throws {
        let climb = try #require(Self.motions.motion(named: "climbIn"))
        #expect(climb.duration == 2.5 && climb.stages.count == 3 && !climb.loops)
        #expect(climb.stageStart(2) == 2)
        #expect(climb.stage(at: 0.25)! == (0, 0.25) && climb.stage(at: 1)! == (1, 0) && climb.stage(at: 9)! == (2, 0.5))
        #expect(Self.motions.canSleep && !CharacterMotions.placeholder.canSleep)
        #expect(Self.motions.problem(with: try Self.lyingRig()) == nil)
        #expect(Self.motions.problem(with: try VectorRigTests.rig(VectorRigTests.walkingJSON)) == "climbIn.stages[2].look")   // 沒有姿勢
        let travel = try #require(climb.stages[0].travel)
        #expect(travel.at(0.25) == (0.25, 2.5) && travel.at(-1) == (0, 0) && travel.at(2) == (1, 0))
    }

    @Test func stagedMotionsPlayEachStageOnItsOwnLook() throws {
        let rig = try Self.lyingRig()
        let climb = try #require(Self.motions.motion(named: "climbIn")), sleep = try #require(Self.motions.motion(named: "sleep"))
        #expect(climb.pose(facing: .front, rig: rig, at: 0.5)?.look == "backLeft")
        #expect(climb.pose(facing: .front, rig: rig, at: 1.5)?.parts["head"]?.rotate == 10)
        #expect(climb.pose(facing: .front, rig: rig, at: 2.2)?.look == "lie")
        #expect(sleep.pose(facing: .backLeft, rig: rig, at: 5)?.look == "lie")
        #expect(abs(try #require(sleep.pose(facing: .backLeft, rig: rig, at: 5)?.parts["body"]?.scaleY) - 1.1) < 1e-12)      // 循環接回
        #expect(climb.pose(facing: .front, rig: try VectorRigTests.rig(VectorRigTests.walkingJSON), at: 2.2) == nil)
    }

    @Test func rejectsBadStages() {
        func problem(_ old: String, _ new: String) -> CharacterMotionsError? {
            do {
                _ = try CharacterMotions.decode(Data(Self.motionJSON.replacingOccurrences(of: old, with: new).utf8))
                return nil
            } catch {
                return error as? CharacterMotionsError
            }
        }
        #expect(problem("\"version\": 4", "\"version\": 5") == .unsupportedVersion(5))
        #expect(problem("[0.5, 0.5, 5], [1, 1, 0]", "[0.5, 0.5, 5], [1, 0.9, 0]") == .invalid("climbIn.stages[0].travel"))   // 沒走到底
        #expect(problem("[0.5, 0.5, 5], [1, 1, 0]", "[0.5, 0.5, 5], [2, 1, 0]") == .invalid("climbIn.stages[0].travel"))     // 超過那一段
        #expect(problem("\"look\": \"lie\", \"duration\": 0.5", "\"look\": \"lie\", \"duration\": 0") == .invalid("climbIn.stages[2].duration"))
    }

    // MARK: - 姿勢的造型

    @Test func posturesAreCheckedAndDrawn() throws {
        let rig = try Self.lyingRig()
        let look = try #require(rig.look("lie"))
        #expect(look.source == "lie" && look.mirror == nil)
        #expect(rig.shownParts(look, CharacterPose(look: "lie")) == ["body", "head"])
        #expect(rig.shownParts(look, CharacterPose(look: "lie", shown: ["eyes": true])) == ["body", "head", "eyes"])
        #expect(try #require(rig.frame(CharacterPose(look: "lie"))).transforms["head"] == .identity)
        #expect(throws: VectorRigError.invalidDirection("lie.shadow")) { try VectorRigTests.rig(Self.lyingJSON.replacingOccurrences(of: "0.16", with: "0")) }
        #expect(throws: VectorRigError.invalidDirection("lie.touch")) {
            try VectorRigTests.rig(Self.lyingJSON.replacingOccurrences(of: ", { \"x\": 28, \"y\": 10 }, { \"x\": 24, \"y\": 17 }, { \"x\": 10, \"y\": 16 }", with: ""))
        }
        #expect(throws: VectorRigError.invalidDirection("front")) { try VectorRigTests.rig(Self.lyingJSON.replacingOccurrences(of: "\"lie\"", with: "\"front\"")) }
        // 貼圖：姿勢的部件與影子都算進用量
        let plain = try VectorRigTests.rig(VectorRigTests.walkingJSON)
        let drawn = VectorRasterizer.rasterize(rig, facing: "lie", pixelsPerUnit: 4).reduce(0) { $0 + $1.byteCount * 4 / 3 }
            + (try #require(VectorRasterizer.rasterizeShadow(rig, facing: "lie", pixelsPerUnit: 4))).byteCount * 4 / 3
        #expect(VectorRasterizer.textureBytes(rig, pixelsPerUnit: 4) - VectorRasterizer.textureBytes(plain, pixelsPerUnit: 4) == drawn)
        #expect(VectorRasterizer.rasterizeShadow(rig, facing: "front", pixelsPerUnit: 4) == nil)
    }

    @Test func standInKeepsThePosture() throws {
        let gray = try Self.lyingRig().graySilhouette()
        #expect(gray.postures["lie"]?.shadow != nil && gray.postures["lie"]?.touch?.count == 5)
        #expect(gray.postures["lie"]?.parts["body"]?.layers.first?.fill == VectorRig.placeholderFill)
        #expect(gray.postures["lie"]?.parts["eyes"]?.hidden == true)
    }

    // MARK: - 模擬

    static let ids = [CharacterID("first"), CharacterID("second"), CharacterID("third")]

    /// 站在 `tiles` 上台，睏意 100（機率 1，一上台就要去睡）。
    static func simulation(_ tiles: [Tile], wander: [WanderConfig], motions: CharacterMotions = motions) -> Simulation {
        var sim = Simulation(room: .indoor, cast: zip(ids, wander).map { .init(id: $0, motions: motions, wander: $1) }, seed: 1)
        for (id, tile) in zip(ids, tiles) { sim.send(.enter(id, at: tile.center)) }
        return sim
    }

    static func character(_ sim: Simulation, _ i: Int = 0) -> SimulationSnapshot.Character? { sim.snapshot.character(ids[i]) }
    static func intent(_ sim: Simulation, _ i: Int = 0) -> CharacterBehavior.Intent? { sim.behavior(of: ids[i])?.intent }
    static let bed = RoomLayout.indoor.furniture.firstIndex { $0.kind == .bed }!
    static func near(_ a: TilePosition?, _ b: TilePosition) -> Bool {
        guard let a else { return false }
        return abs(a.i - b.i) < 1e-9 && abs(a.j - b.j) < 1e-9
    }

    @Test func climbsOntoTheBedAndLiesInItsSlot() throws {
        var sim = Self.simulation([Tile(i: 3, j: 3)], wander: [Self.config()])
        _ = sim.step()
        #expect(Self.intent(sim) == .climbIn)                                         // 已經在床邊，馬上上床
        let slot = RoomLayout.indoor.slot(Self.slots[1])
        DozeTests.run(&sim, until: 0.5)
        let jumping = try #require(Self.character(sim))
        #expect(jumping.support == Self.bed && jumping.facing == .backLeft)
        #expect(abs(jumping.height - 10) < 1e-6)                                      // 一半：5，加上多跳的 5
        #expect(Self.near(jumping.position, TilePosition(i: (3.5 + slot.edge.i) / 2, j: (3.5 + slot.edge.j) / 2)))
        DozeTests.run(&sim, until: 1.5)
        #expect(Self.near(Self.character(sim)?.position, TilePosition(i: (slot.edge.i + slot.position.i) / 2, j: 3.45)))
        DozeTests.run(&sim, until: 2.6)
        #expect(Self.intent(sim) == .sleep)
        #expect(Self.near(Self.character(sim)?.position, slot.position) && Self.character(sim)?.height == 10)
        guard case .motion(.sleep, _)? = Self.character(sim)?.activity else {
            Issue.record("快照沒有在睡覺")
            return
        }
    }

    @Test func wakesRestedAtTheEndOfALoopAndLandsBesideTheBed() throws {
        // 從 100 降到 80 要 20 秒（每秒 1），剛好 10 個循環
        var sim = Self.simulation([Tile(i: 3, j: 3)], wander: [Self.config()])
        DozeTests.run(&sim, until: 2.5 + 19.8)
        #expect(Self.intent(sim) == .sleep)
        DozeTests.run(&sim, until: 2.5 + 20.2)
        #expect(Self.intent(sim) == .wakeRested)
        DozeTests.run(&sim, until: 2.5 + 20.2 + 3.1)
        let up = try #require(Self.character(sim))
        #expect(Self.intent(sim) == .stand(facing: nil, seconds: 5))                  // 冷卻中，回到閒晃（發呆）
        #expect(Self.near(up.position, Tile(i: 3, j: 3).center) && up.height == 0 && up.support == nil && up.facing == .frontRight)
    }

    @Test func tapWakesOnlyTheTappedOne() throws {
        var sim = Self.simulation([Tile(i: 3, j: 1), Tile(i: 3, j: 3)], wander: [Self.config(), Self.config()])
        DozeTests.run(&sim, until: 4)
        #expect(Self.intent(sim, 0) == .sleep && Self.intent(sim, 1) == .sleep)
        sim.send(.ownerTapped(Self.ids[0], at: .now))
        _ = sim.step()
        #expect(Self.intent(sim, 0) == .wakeTapped && Self.intent(sim, 1) == .sleep)
        #expect(Self.character(sim, 0)?.facing == .front)
        DozeTests.run(&sim, until: 8)
        #expect(Self.character(sim, 0)?.support == nil && Self.intent(sim, 1) == .sleep)
        #expect(try #require(sim.sleepiness(of: Self.ids[0])) > 90)                   // 還很睏，冷卻中不會馬上又去睡
        #expect(Self.intent(sim, 0) == .stand(facing: nil, seconds: 5))
    }

    /// 先到先選（作者 2026-11-24 決定）：兩隻都往近的那個走，先到的佔住，後到的改去另一個。
    @Test func firstToArrivePicksTheBedAndTheOtherTakesWhatIsLeft() throws {
        var sim = Self.simulation([Tile(i: 4, j: 3), Tile(i: 8, j: 3)], wander: [Self.config(wakeBelow: 1), Self.config(wakeBelow: 1)])
        DozeTests.run(&sim, until: 30)
        #expect(Self.intent(sim, 0) == .sleep && Self.intent(sim, 1) == .sleep)
        #expect(Self.near(Self.character(sim, 0)?.position, RoomLayout.indoor.slot(Self.slots[1]).position))
        #expect(Self.near(Self.character(sim, 1)?.position, RoomLayout.indoor.slot(Self.slots[0]).position))
    }

    @Test func theThirdOneDozesWhenTheBedIsFull() {
        var sim = Self.simulation([Tile(i: 3, j: 1), Tile(i: 3, j: 3), Tile(i: 8, j: 8)],
                                  wander: [Self.config(wakeBelow: 1), Self.config(wakeBelow: 1), Self.config(doze: 1, cooldown: 0)])
        DozeTests.run(&sim, until: 20)
        #expect(Self.intent(sim, 0) == .sleep && Self.intent(sim, 1) == .sleep)
        #expect([.sitDown, .doze].contains(Self.intent(sim, 2)))
    }

    @Test func tapOnTheWayToBedSaysHelloAndGoesOn() {
        var sim = Self.simulation([Tile(i: 8, j: 3)], wander: [Self.config()])
        DozeTests.run(&sim, until: 2)
        guard case .move? = Self.intent(sim) else {
            Issue.record("沒有走去床邊")
            return
        }
        sim.send(.ownerTapped(Self.ids[0], at: .now))
        _ = sim.step()
        #expect(Self.intent(sim) == .hello)
        DozeTests.run(&sim, until: 30)
        #expect(Self.intent(sim) == .sleep)
    }

    /// 下床時落地的格子都被佔住：停在床邊等，空出來再跳下去。
    @Test func waitsAtTheEdgeUntilAFloorTileIsFree() throws {
        var sim = Self.simulation([Tile(i: 3, j: 3), Tile(i: 9, j: 3), Tile(i: 9, j: 4)],
                                  wander: [Self.config(wakeBelow: 1), Self.config(start: 0, idle: true), Self.config(start: 0, idle: true)])
        DozeTests.run(&sim, until: 4)
        #expect(Self.intent(sim, 0) == .sleep)
        // 兩個可以落地的格子都站了別隻
        sim.send(.place(Self.ids[1], at: Tile(i: 3, j: 3).center))
        sim.send(.place(Self.ids[2], at: Tile(i: 3, j: 2).center))
        sim.send(.ownerTapped(Self.ids[0], at: .now))
        DozeTests.run(&sim, until: 10)
        #expect(Self.intent(sim, 0) == .wakeTapped)
        let waiting = try #require(Self.character(sim, 0))
        #expect(waiting.activity == .paused(.wakeTapped, at: 2))
        #expect(Self.near(waiting.position, RoomLayout.indoor.slot(Self.slots[1]).edge) && waiting.height == 10)
        // 第二個選擇空出來
        sim.send(.place(Self.ids[2], at: Tile(i: 9, j: 4).center))
        DozeTests.run(&sim, until: 10.5)
        guard case .motion(.wakeTapped, _)? = Self.character(sim, 0)?.activity else {
            Issue.record("沒有接著播")
            return
        }
        DozeTests.run(&sim, until: 11.2)
        let landed = try #require(Self.character(sim, 0))
        #expect(Self.near(landed.position, Tile(i: 3, j: 2).center) && landed.height == 0 && landed.support == nil)
    }

    @Test func aBedRequestAwayFromTheBedIsIgnored() {
        var sim = Self.simulation([Tile(i: 8, j: 8)], wander: [Self.config(start: 0, idle: true)])
        sim.send(.input(Self.ids[0], .sleepRequested))
        _ = sim.step()
        #expect(Self.intent(sim) == .idle)
    }

    @Test func charactersWithoutSleepMotionsNeverGoToBed() {
        var sim = Self.simulation([Tile(i: 3, j: 3)], wander: [Self.config()], motions: DozeTests.motions)
        DozeTests.run(&sim, until: 20)
        #expect(Self.character(sim)?.support == nil)
        #expect(Self.intent(sim).map(\.isInBed) == false)
    }

    @Test func debugButtonMakesTheSleepLonger() throws {
        var sim = Self.simulation([Tile(i: 3, j: 3)], wander: [Self.config()])
        DozeTests.run(&sim, until: 10)
        let before = try #require(sim.wakeAt)
        sim.send(.addSleepiness(25))
        _ = sim.step()
        #expect(try #require(sim.wakeAt) > before)
    }
}

/// 畫面準備：躺在床上的角色畫在床前面、站在床尾的畫在牠前面、影子先畫、離地高度、觸控範圍。
@MainActor
struct SleepFrameTests {
    static let slots = [RoomLayout.indoor.slot(SleepTests.slots[0]), RoomLayout.indoor.slot(SleepTests.slots[1])]
    static let ids = FrameBuilderTests.ids

    static func builder() throws -> FrameBuilder {
        try FrameBuilderTests.builder(motions: [SleepTests.motions, SleepTests.motions], rig: try SleepTests.lyingRig())
    }

    static func sleeping(_ id: CharacterID, slot: Int, at start: Double = 0) -> SimulationSnapshot.Character {
        .init(id: id, position: slots[slot].position, facing: .backLeft, activity: .motion(.sleep, since: start), height: 10,
              support: SleepTests.bed)
    }

    static func index(_ frame: FrameBuilder.Frame, _ key: DrawKey) -> Int? { frame.sprites.firstIndex { $0.key == key } }

    @Test func sleepersAreDrawnOnTheBedAndTheNearOneInFront() throws {
        let builder = try Self.builder()
        for swapped in [false, true] {   // 先到先選，兩隻可能對調
            let frame = FrameBuilderTests.build(builder, FrameBuilderTests.snapshot([
                Self.sleeping(Self.ids[0], slot: swapped ? 1 : 0), Self.sleeping(Self.ids[1], slot: swapped ? 0 : 1)]))
            let bed = try #require(Self.index(frame, .furniture(SleepTests.bed)))
            let far = try #require(Self.index(frame, .character(Self.ids[swapped ? 1 : 0])))
            let near = try #require(Self.index(frame, .character(Self.ids[swapped ? 0 : 1])))
            #expect(bed < far && far < near)
        }
    }

    @Test func aCharacterAtTheFootOfTheBedIsDrawnInFrontOfTheSleeper() throws {
        let builder = try Self.builder()
        let frame = FrameBuilderTests.build(builder, FrameBuilderTests.snapshot([
            Self.sleeping(Self.ids[0], slot: 0), FrameBuilderTests.character(Self.ids[1], Tile(i: 3, j: 1).center, .backLeft)]))
        #expect(try #require(Self.index(frame, .character(Self.ids[0]))) < (try #require(Self.index(frame, .character(Self.ids[1])))))
        // 站在床後面（靠右牆那一排）的畫在床後面
        let behind = FrameBuilderTests.build(builder, FrameBuilderTests.snapshot([
            Self.sleeping(Self.ids[0], slot: 0), FrameBuilderTests.character(Self.ids[1], Tile(i: 1, j: 0).center)]))
        #expect(try #require(Self.index(behind, .character(Self.ids[1]))) < (try #require(Self.index(behind, .furniture(SleepTests.bed)))))
    }

    @Test func theShadowComesJustBeforeTheSleeper() throws {
        let builder = try Self.builder()
        let list = try #require(FrameBuilderTests.build(builder, FrameBuilderTests.snapshot([Self.sleeping(Self.ids[0], slot: 0)])).drawList)
        let at = try #require(list.items.firstIndex {
            if case .character = $0 { return true }
            return false
        })
        guard case .shadow(let id, let look, let transform, let alpha) = list.items[at - 1],
              case .character(_, let drawn, let parts) = list.items[at] else {
            Issue.record("影子沒有在角色前面")
            return
        }
        #expect(id == Self.ids[0] && look == "lie" && drawn == "lie" && alpha == 0.16)
        #expect(parts.map(\.name) == ["body", "head"])
        // 影子不跟著部件動：只有放到箱庭、鏡頭與縮放
        let t = try #require(builder.viewTransform), p = FrameBuilderTests.iso.screen(1.85, 2, 10)
        let shift = transform.apply(15, 12)
        #expect(abs(shift.x - (p.x - t.topLeftX) * t.pointsPerUnit) < 1e-6 && abs(shift.y - (p.y - t.topLeftY) * t.pointsPerUnit) < 1e-6)
    }

    @Test func heightMovesBetweenSnapshots() throws {
        let builder = try Self.builder()
        func jumping(_ height: Double) -> SimulationSnapshot.Character {
            .init(id: Self.ids[0], position: Self.slots[0].edge, facing: .backLeft, activity: .motion(.climbIn, since: 0), height: height,
                  support: SleepTests.bed)
        }
        let frame = FrameBuilderTests.build(builder, FrameBuilderTests.snapshot([jumping(6)], tick: 1),
                                            previous: FrameBuilderTests.snapshot([jumping(4)]), at: 0.5 / 30)
        let sprite = try #require(FrameBuilderTests.sprite(frame, Self.ids[0]))
        #expect(abs(sprite.y - (FrameBuilderTests.iso.screen(2.6, 2, 5).y - 18)) < 1e-9)
    }

    @Test func pausedMotionHoldsItsFrameAndResumesWithoutJumpingBack() throws {
        let rig = try SleepTests.lyingRig()
        func character(_ activity: SimulationSnapshot.Activity) -> SimulationSnapshot.Character {
            .init(id: Self.ids[0], position: Self.slots[0].edge, facing: .frontRight, activity: activity, height: 10, support: SleepTests.bed)
        }
        func rotation(_ now: SimulationSnapshot.Character, before: SimulationSnapshot.Character?, at time: Double) -> Double? {
            let pose = FrameBuilder.pose(of: now, before: before, alpha: 0.5, at: time, rig: rig, motions: SleepTests.motions)
            return pose.look == "frontRight" ? pose.parts["head"]?.rotate : nil
        }
        let paused = character(.paused(.wakeTapped, at: 1.5))
        #expect(abs(try #require(rotation(paused, before: paused, at: 99)) - 15) < 1e-9)
        // 剛接著播：畫的時間還在開始之前，停在停住的那一刻
        #expect(abs(try #require(rotation(character(.motion(.wakeTapped, since: 98.5)), before: paused, at: 99.9)) - 15) < 1e-9)
    }

    @Test func tappingASleeperUsesTheTouchShape() throws {
        let builder = try Self.builder()
        FrameBuilderTests.build(builder, FrameBuilderTests.snapshot([Self.sleeping(Self.ids[0], slot: 0), Self.sleeping(Self.ids[1], slot: 1)]))
        func hit(_ slot: Int, _ x: Double, _ y: Double) throws -> CharacterID? {   // 姿勢畫布上的一點
            let p = FrameBuilderTests.iso.screen(Self.slots[slot].position.i, Self.slots[slot].position.j, 10)
            return builder.character(at: try FrameBuilderTests.screenPoint(builder, x: p.x - 15 + x, y: p.y - 12 + y))
        }
        #expect(try hit(0, 18, 10) == Self.ids[0])
        #expect(try hit(1, 8, 8) == Self.ids[1])
        #expect(try hit(1, 28, 1) != Self.ids[1])      // 在近的那隻的畫布裡，但不在牠的觸控範圍
        #expect(FrameBuilder.contains([.init(x: 0, y: 0), .init(x: 4, y: 0), .init(x: 0, y: 4)], x: 1, y: 1))
        #expect(!FrameBuilder.contains([.init(x: 0, y: 0), .init(x: 4, y: 0), .init(x: 0, y: 4)], x: 3, y: 3))
    }
}

/// 拿真實角色包從上床跑到繪製清單：兩隻都睡著、一隻被點醒下床。沒有角色包時跳過。
@MainActor
struct SleepPackTests {
    @Test(.enabled(if: VectorPackParityTests.allPacks.count >= 2, "沒有兩隻的角色包（乾淨 clone），跳過"))
    func bothSleepInTheBedAndOneWakes() throws {
        let packs = VectorPackParityTests.allPacks.prefix(2).map { try! CharacterPackLibrary.load($0) }
        let motions = try packs.map { try #require($0.motions, "motion.json 讀不懂或對不上造型") }
        #expect(motions.allSatisfy { $0.canSleep })
        var sim = Simulation(room: .indoor, cast: (0..<2).map {
            .init(id: SleepTests.ids[$0], motions: motions[$0], wander: SleepTests.config(wakeBelow: 1))
        }, seed: 1)
        sim.send(.enter(SleepTests.ids[0], at: Tile(i: 3, j: 1).center))
        sim.send(.enter(SleepTests.ids[1], at: Tile(i: 3, j: 3).center))
        let builder = FrameBuilder(room: .indoor, cast: (0..<2).map { .init(id: SleepTests.ids[$0], vector: packs[$0].vector, motions: motions[$0]) },
                                   effects: EffectLibrary.bundled())
        builder.resize(viewport: CGSize(width: 402, height: 874), displayScale: 3)
        func looks() throws -> [String] {
            let list = try #require(builder.build(previous: nil, current: sim.snapshot, at: sim.time, now: 0).drawList)
            return list.items.compactMap { if case .character(_, let look, _) = $0 { look } else { nil } }
        }
        while sim.time < 10 {
            _ = sim.step()
            #expect(try looks().count == 2)
        }
        #expect(try looks() == ["lieBack", "lieBack"])
        sim.send(.ownerTapped(SleepTests.ids[1], at: .now))
        _ = sim.step()
        #expect(try looks() == ["lieBack", "front"])
        while sim.time < 16 { _ = sim.step() }
        #expect(sim.snapshot.character(SleepTests.ids[0])?.support != nil && sim.snapshot.character(SleepTests.ids[1])?.support == nil)
    }
}
