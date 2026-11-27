import Foundation
import Testing
@testable import PenguinFamily

/// 點一下的反應（A1 第 14 項，作者 2026-11-25～27 決定）：資料檔讀得進來、不合理的數字擋下來；背對主人一律嚇一跳、
/// 看得到臉時歪頭（每次隨機一邊）、走路中停下來反應再接著走、背對時耐心已經不夠就直接不耐煩；耐心值（點下去時已經低於門檻就不耐煩、一直戳就一直是、
/// 回升到門檻以上才好，反應播放中的點也扣、等播完再不耐煩）；離開一陣子後第一次點是開心哈囉（背對時留到下一次、
/// 睡著時醒來再接、沒有回應的點不用掉）；箱庭送進模擬的「離上一次點多久」、事件紀錄讀每隻最後一次被點的時間。
/// 亂數用模擬固定的種子，每次跑結果都一樣。
struct TapReactionTests {
    static let id = CharacterID("tapped")
    static let hours = 3600.0

    /// 和 App 預設相同：看得到臉時歪頭（兩邊）、背對時嚇一跳；4 小時；耐心 100、每點扣 25、每秒回 5、低於 20 不耐煩。
    static let config = InteractionConfig(
        version: 1,
        reactions: .init(facingOwner: [.init(motions: ["tiltLeft", "tiltRight"], weight: 1)],
                         facingAway: [.init(motions: ["startle"], weight: 1)]),
        greeting: .init(motion: "happyHello", afterHours: 4),
        patience: .init(motion: "annoyed", max: 100, perTap: 25, recoverPerSecond: 5, below: 20))

    /// 看得到臉時只會某一種反應、背對時沒有另外的反應（其他照預設）。
    static func only(_ motion: String) -> InteractionConfig {
        var config = config
        config.reactions = .init(facingOwner: [.init(motions: [motion], weight: 1)])
        return config
    }

    /// 反應都是 1 秒（開心哈囉 2 秒），都轉向鏡頭；另外有打瞌睡（模擬只看長度）。
    static let motions = CharacterMotions(motions: [
        "hello": .init(duration: 1, facing: .front),
        "tiltLeft": .init(duration: 1, facing: .front),
        "tiltRight": .init(duration: 1, facing: .front),
        "startle": .init(duration: 1, facing: .front),
        "happyHello": .init(duration: 2, facing: .front),
        "annoyed": .init(duration: 1, facing: .front),
        "sitDown": .init(duration: 1),
        "doze": .init(duration: 2, cycle: 2),
        "standUp": .init(duration: 1),
        "wakeStartled": .init(duration: 1, facing: .front),
    ], gaits: CharacterMotions.defaultGaits)

    // MARK: - 資料

    @Test func bundledDefaultIsValid() throws {
        let config = try #require(InteractionConfig.bundled(), "App 裡的 interactions.json 讀不到或不合理")
        #expect(config == Self.config)
    }

    @Test func numbersMustMakeSense() {
        func problem(_ change: (inout InteractionConfig) -> Void) -> InteractionConfigError? {
            var config = Self.config
            change(&config)
            do {
                try config.validate()
                return nil
            } catch {
                return error as? InteractionConfigError
            }
        }
        #expect(problem { _ in } == nil)
        #expect(problem { $0.version = 2 } == .unsupportedVersion(2))
        #expect(problem { $0.reactions.facingOwner = [] } == .invalid("reactions.facingOwner"))
        #expect(problem { $0.reactions.facingOwner[0].weight = 0 } == .invalid("reactions.facingOwner"))
        #expect(problem { $0.reactions.facingOwner[0].motions = [] } == .invalid("reactions.facingOwner[0].motions"))
        #expect(problem { $0.reactions.facingAway[0].weight = -1 } == .invalid("reactions.facingAway[0].weight"))
        #expect(problem { $0.reactions.facingAway = [] } == nil)        // 背對時可以沒有另外的反應
        #expect(problem { $0.greeting?.afterHours = 0 } == .invalid("greeting.afterHours"))
        #expect(problem { $0.patience?.perTap = 0 } == .invalid("patience.perTap"))
        #expect(problem { $0.patience?.recoverPerSecond = 0 } == .invalid("patience.recoverPerSecond"))   // 不會回升就永遠不會好
        #expect(problem { $0.patience?.below = 101 } == .invalid("patience.below"))
        #expect(problem { $0.greeting = nil; $0.patience = nil } == nil)   // 兩個都可以不寫
    }

    @Test func decodesTheDocumentedFormat() throws {
        let json = """
        { "version": 1,
          "reactions": { "facingOwner": [{ "motions": ["tiltLeft", "tiltRight"], "weight": 1 }],
                         "facingAway": [{ "motions": ["startle"], "weight": 1 }] },
          "greeting": { "motion": "happyHello", "afterHours": 4 },
          "patience": { "motion": "annoyed", "max": 100, "perTap": 25, "recoverPerSecond": 5, "below": 20 } }
        """
        #expect(try InteractionConfig.decode(Data(json.utf8)) == Self.config)
        #expect(throws: InteractionConfigError.invalid("patience.below")) {
            try InteractionConfig.decode(Data(json.replacingOccurrences(of: "\"below\": 20", with: "\"below\": 0").utf8))
        }
    }

    @Test func picksBySideOfTheFace() {
        var rng = WanderTests.SeededGenerator(seed: 3)
        var count: [String: Int] = [:]
        for _ in 0..<2_000 { count[Self.config.pickReaction(facingAway: false, has: { _ in true }, using: &rng)!, default: 0] += 1 }
        #expect(Set(count.keys) == ["tiltLeft", "tiltRight"])                       // 看得到臉：一律歪頭
        #expect(abs(count["tiltLeft", default: 0] - count["tiltRight", default: 0]) < 200)   // 每次隨機歪一邊
        let away = Set((0..<100).compactMap { _ in Self.config.pickReaction(facingAway: true, has: { _ in true }, using: &rng) })
        #expect(away == ["startle"])                                                 // 背對：一律嚇一跳
    }

    @Test func onlyPicksMotionsTheCharacterHas() {
        var rng = WanderTests.SeededGenerator(seed: 3)
        let picks = Set((0..<200).compactMap { _ in Self.config.pickReaction(facingAway: false, has: { $0 != "tiltLeft" }, using: &rng) })
        #expect(picks == ["tiltRight"])
        #expect(Self.config.pickReaction(facingAway: true, has: { $0 != "startle" }, using: &rng) == nil)
        #expect(Self.only("hello").pickReaction(facingAway: true, has: { _ in true }, using: &rng) == nil)
    }

    @Test func patienceSpendsAndRecovers() {
        var patience = Patience(max: 100, recoverPerSecond: 5, at: 0)
        #expect(patience.level(at: 0) == 100)
        patience.spend(25, at: 1)
        #expect(patience.level(at: 1) == 75)
        #expect(patience.level(at: 3) == 85)
        patience.spend(200, at: 3)
        #expect(patience.level(at: 3) == 0)                 // 不低於 0
        #expect(patience.level(at: 4) == 5)
        #expect(patience.level(at: 60) == 100)              // 回到滿就停
    }

    // MARK: - 模擬

    /// 一隻上台（第一個節拍、面向鏡頭），不閒晃。
    static func simulation(_ interactions: InteractionConfig? = config, motions: CharacterMotions = motions,
                           wander: WanderConfig? = nil, seed: UInt64 = 1) -> Simulation {
        var sim = Simulation(room: .indoor, cast: [.init(id: id, motions: motions, wander: wander, interactions: interactions)],
                             seed: seed)
        sim.send(.enter(id, at: TilePosition(i: 4.5, j: 4.5)))
        _ = sim.step()
        return sim
    }

    static func intent(_ sim: Simulation) -> CharacterBehavior.Intent? { sim.behavior(of: id)?.intent }
    static func isTilt(_ intent: CharacterBehavior.Intent?) -> Bool { intent == .react("tiltLeft") || intent == .react("tiltRight") }

    /// 點一下，跑一個節拍。
    static func tap(_ sim: inout Simulation, sinceLastTap: Double = 0) {
        sim.send(.ownerTapped(id, at: .now, sinceLastTap: sinceLastTap))
        _ = sim.step()
    }

    static func run(_ sim: inout Simulation, for seconds: Double) {
        let end = sim.time + seconds
        while sim.time < end - 1e-9 { _ = sim.step() }
    }

    @Test func facingTheCameraTilts() {
        var sim = Self.simulation()
        Self.tap(&sim)
        #expect(Self.isTilt(Self.intent(sim)))
        Self.run(&sim, for: 1.1)
        #expect(Self.intent(sim) == .idle)
    }

    @Test func standingWithBackTurnedStartlesFacingTheCamera() {
        var sim = Self.simulation()
        sim.send(.input(Self.id, .standRequested(facing: .backLeft, seconds: 10)))   // 例如在窗邊看窗外
        _ = sim.step()
        Self.tap(&sim)
        #expect(Self.intent(sim) == .react("startle"))
        #expect(sim.snapshot.character(Self.id)?.facing == .front)   // 先轉向鏡頭
    }

    @Test func walkingAwayStartlesThenKeepsWalking() {
        var sim = Self.simulation()
        let goal = Tile(i: 1, j: 4)                                  // 往左後走：背對主人
        sim.send(.input(Self.id, .moveRequested(to: goal, pace: .slow)))
        Self.run(&sim, for: 1.3)
        #expect(sim.snapshot.character(Self.id)?.facing == .backLeft)
        let stopped = sim.snapshot.character(Self.id)?.position
        Self.tap(&sim)
        #expect(Self.intent(sim) == .react("startle"))
        Self.run(&sim, for: 0.9)
        #expect(sim.snapshot.character(Self.id)?.position == stopped)   // 停在原地播
        Self.run(&sim, for: 0.2)
        guard case .move(let to, _)? = Self.intent(sim) else {
            Issue.record("播完沒有接著走：\(String(describing: Self.intent(sim)))")
            return
        }
        #expect(to == goal)
    }

    @Test func walkingTowardTheCameraTilts() {
        var sim = Self.simulation()
        sim.send(.input(Self.id, .moveRequested(to: Tile(i: 8, j: 4), pace: .fast)))   // 往右前小跑：看得到臉
        Self.run(&sim, for: 0.6)
        #expect(sim.snapshot.character(Self.id)?.facing == .frontRight)
        Self.tap(&sim)
        #expect(Self.isTilt(Self.intent(sim)))
        Self.run(&sim, for: 1.1)
        guard case .move? = Self.intent(sim) else {
            Issue.record("播完沒有接著走：\(String(describing: Self.intent(sim)))")
            return
        }
    }

    @Test func sameSeedSameSides() {
        func reactions(seed: UInt64) -> [String] {
            var sim = Self.simulation(seed: seed)
            return (0..<20).compactMap { _ in
                Self.tap(&sim)
                defer { Self.run(&sim, for: 6) }
                if case .react(let name)? = Self.intent(sim) { return name }
                return nil
            }
        }
        let sides = reactions(seed: 4)
        #expect(sides == reactions(seed: 4))
        #expect(Set(sides) == ["tiltLeft", "tiltRight"])
    }

    @Test func quickTapsWaitForTheReactionThenStayAnnoyedUntilRecovered() {
        var sim = Self.simulation(Self.only("hello"))
        for _ in 0..<5 {                                    // 0.4 秒內點 5 下：耐心 100 → 75 → 50 → 25 → 0，第 5 下已經低於 20
            Self.tap(&sim)
            Self.run(&sim, for: 0.1)
        }
        #expect(Self.intent(sim) == .hello)                 // 不打斷當下的反應
        Self.run(&sim, for: 0.6)
        #expect(Self.intent(sim) == .react("annoyed"))      // 播完才不耐煩
        let before = sim.patience(of: Self.id) ?? 0
        for _ in 0..<5 { Self.tap(&sim) }                   // 不耐煩時的點不扣
        #expect((sim.patience(of: Self.id) ?? 0) > before)
        Self.run(&sim, for: 1.1)
        #expect(Self.intent(sim) == .idle)
        Self.tap(&sim)                                      // 還沒回升到 20：每點一下都不耐煩
        #expect(Self.intent(sim) == .react("annoyed"))
        Self.run(&sim, for: 4.1)                            // 被扣到 0 之後，不碰牠 4 秒回到 20
        Self.tap(&sim)
        #expect(Self.intent(sim) == .hello)
    }

    @Test func steadyTappingRunsOutOnTheSixthTap() {
        var sim = Self.simulation(Self.only("hello"))
        for n in 1...5 {                                    // 每 1.13 秒一下：每次都播完了才點，回升比扣的慢
            Self.tap(&sim)
            #expect(Self.intent(sim) == .hello, "第 \(n) 下")
            Self.run(&sim, for: 1.1)
        }
        Self.tap(&sim)
        #expect(Self.intent(sim) == .react("annoyed"))
    }

    @Test func slowTapsNeverRunOut() {
        var sim = Self.simulation(Self.only("hello"))
        for n in 1...10 {
            Self.tap(&sim)
            #expect(Self.intent(sim) == .hello, "第 \(n) 下")
            Self.run(&sim, for: 5.1)                        // 5 秒回 25，扣多少回多少
        }
    }

    @Test func pokingABackTurnedWalkerStartlesThenAnnoyed() {
        // 背對一律嚇一跳；嚇一跳時的點照樣扣耐心，第 5 下已經低於門檻，播完變不耐煩，之後接著走（作者 2026-11-27 決定）
        var sim = Self.simulation()
        sim.send(.input(Self.id, .moveRequested(to: Tile(i: 0, j: 4), pace: .slow)))
        Self.run(&sim, for: 0.5)
        for _ in 0..<5 { Self.tap(&sim) }
        #expect(Self.intent(sim) == .react("startle"))
        Self.run(&sim, for: 1)
        #expect(Self.intent(sim) == .react("annoyed"))
        Self.run(&sim, for: 1.05)
        guard case .move? = Self.intent(sim) else {
            Issue.record("不耐煩完沒有接著走：\(String(describing: Self.intent(sim)))")
            return
        }
    }

    @Test func backTurnedWhileOutOfPatienceIsAnnoyedRightAway() {
        // 背對時耐心已經低於門檻：直接不耐煩，不嚇一跳（作者 2026-11-27 決定），走路、站著都一樣
        for (label, request) in [("走路", CharacterBehavior.Input.moveRequested(to: Tile(i: 0, j: 4), pace: .slow)),
                                 ("站著", .standRequested(facing: .backRight, seconds: 10))] {
            var sim = Self.simulation()
            for _ in 0..<4 { Self.tap(&sim) }               // 看得到臉時扣到 0（第 1 下歪頭，其他在播放中）
            Self.run(&sim, for: 1.1)
            sim.send(.input(Self.id, request))
            Self.run(&sim, for: 0.5)
            #expect(sim.snapshot.character(Self.id)?.facing.facesAway == true, "\(label)")
            Self.tap(&sim)
            #expect(Self.intent(sim) == .react("annoyed"), "\(label)")
        }
    }

    @Test func firstTapAfterBeingAwayIsTheHappyHello() {
        var sim = Self.simulation()
        Self.tap(&sim, sinceLastTap: 4 * Self.hours)
        #expect(Self.intent(sim) == .react("happyHello"))
        #expect(sim.patience(of: Self.id) == 100)           // 開心哈囉不扣耐心
        for _ in 0..<6 { Self.tap(&sim) }                   // 開心哈囉時的點也不扣
        #expect((sim.patience(of: Self.id) ?? 0) == 100)
        Self.run(&sim, for: 2.1)
        #expect(Self.intent(sim) == .idle)
        Self.tap(&sim)                                      // 剛點過：平常的反應
        #expect(Self.isTilt(Self.intent(sim)))

        var notYet = Self.simulation()
        Self.tap(&notYet, sinceLastTap: 4 * Self.hours - 60)
        #expect(Self.isTilt(Self.intent(notYet)))

        var never = Self.simulation()
        Self.tap(&never, sinceLastTap: .infinity)           // 從來沒被點過也算
        #expect(Self.intent(never) == .react("happyHello"))
    }

    @Test func backTurnedFirstTapStartlesAndKeepsTheGreeting() {
        var sim = Self.simulation()
        sim.send(.input(Self.id, .standRequested(facing: .backLeft, seconds: 10)))
        _ = sim.step()
        Self.tap(&sim, sinceLastTap: 5 * Self.hours)        // 背對一律嚇一跳，連離開後的第一次點也是
        #expect(Self.intent(sim) == .react("startle"))
        Self.run(&sim, for: 1.1)
        Self.tap(&sim)                                      // 嚇一跳時轉向鏡頭了：開心哈囉留到這一次
        #expect(Self.intent(sim) == .react("happyHello"))
    }

    /// 坐著打瞌睡（睏意 70、一定打瞌睡，不會自己醒）。
    static func dozing() -> Simulation {
        var sim = Self.simulation(wander: DozeTests.config(wakeBelow: 0))
        Self.run(&sim, for: 1.2)
        return sim
    }

    @Test func dozingWakesFirstThenTheHappyHello() {
        var sim = Self.dozing()
        #expect(Self.intent(sim) == .doze)
        Self.tap(&sim, sinceLastTap: 5 * Self.hours)
        #expect(Self.intent(sim) == .wakeStartled)          // 照原本的規則醒來
        Self.run(&sim, for: 1)
        #expect(Self.intent(sim) == .react("happyHello"))   // 接著開心哈囉
    }

    @Test func tapWithoutResponseKeepsTheGreetingForLater() {
        var sim = Self.dozing()
        Self.tap(&sim)                                      // 剛點過：只醒來
        #expect(Self.intent(sim) == .wakeStartled)
        Self.tap(&sim, sinceLastTap: .infinity)             // 醒來時的點沒有回應：不用掉、也不扣耐心
        #expect(sim.patience(of: Self.id) == 100)
        Self.run(&sim, for: 1)
        #expect(Self.intent(sim) != .react("happyHello"))
        Self.tap(&sim)
        #expect(Self.intent(sim) == .react("happyHello"))   // 下一次回應才是
    }

    @Test func plainDozeWakeHasNoFollowUp() {
        var sim = Self.dozing()
        Self.tap(&sim)
        Self.run(&sim, for: 1)
        #expect(Self.intent(sim)?.isReaction == false)      // 沒欠開心哈囉：醒來後照閒晃做下一件事，不接反應
    }

    @Test func withoutInteractionDataTapIsHello() {
        var sim = Self.simulation(nil)
        Self.tap(&sim, sinceLastTap: .infinity)
        #expect(Self.intent(sim) == .hello)
        #expect(sim.patience(of: Self.id) == nil)
        // 資料裡的動作這隻都沒有（例如替身）：照舊哈囉，背對時也是，不會開心哈囉、不耐煩
        let helloOnly = CharacterMotions(motions: ["hello": .init(duration: 1, facing: .front)], gaits: CharacterMotions.defaultGaits)
        var standIn = Self.simulation(motions: helloOnly)
        standIn.send(.input(Self.id, .standRequested(facing: .backLeft, seconds: 10)))
        _ = standIn.step()
        Self.tap(&standIn, sinceLastTap: .infinity)
        #expect(Self.intent(standIn) == .hello)
        Self.run(&standIn, for: 1.1)
        for _ in 0..<10 { Self.tap(&standIn) }
        Self.run(&standIn, for: 1.1)
        #expect(Self.intent(standIn) == .idle)
    }

    // MARK: - 狀態機

    @Test func behaviorReactsOnlyWhenFree() {
        var behavior = CharacterBehavior()
        let changes = [behavior.handle(.reactRequested("tiltLeft"))]
        #expect(behavior.intent == .react("tiltLeft"))
        let busy = [behavior.handle(.reactRequested("startle")), behavior.handle(.ownerTapped)]   // 反應播放中不接
        let finished = behavior.handle(.motionFinished)
        #expect(behavior.intent == .idle)
        _ = behavior.handle(.dozeRequested)
        let dozing = behavior.handle(.reactRequested("hello"))   // 坐下、打瞌睡時不接（被點要醒來）
        #expect(changes == [true] && busy == [false, false] && finished && !dozing)
    }

    @Test func behaviorResumesTheWalkAfterAnyReaction() {
        var behavior = CharacterBehavior()
        let move = CharacterBehavior.Intent.move(to: Tile(i: 2, j: 2), pace: .slow)
        _ = behavior.handle(.moveRequested(to: Tile(i: 2, j: 2), pace: .slow))
        let startled = behavior.handle(.reactRequested("startle"))
        #expect(startled && behavior.interruptedMove == move)
        _ = behavior.handle(.motionFinished)
        #expect(behavior.intent == move)
        let annoyed = behavior.handle(.reactRequested("annoyed"))   // 播完接著走的當下又被叫去不耐煩
        _ = behavior.handle(.motionFinished)
        #expect(annoyed && behavior.intent == move)
    }
}

// MARK: - 箱庭與事件紀錄

@MainActor
struct TapSinceLastTests {
    static let id = TapReactionTests.id

    static func scene(lastTaps: [CharacterID: Date]) throws -> RoomScene {
        let rig = try VectorRigTests.rig(VectorRigTests.walkingJSON)
        return RoomScene(room: .indoor, cast: [.init(id: id, vector: rig, motions: TapReactionTests.motions,
                                                     interactions: TapReactionTests.config)],
                         start: [(id: id, position: TilePosition(i: 4.5, j: 4.5))], seed: 1, now: 0, lastTaps: lastTaps)
    }

    static func intent(_ scene: RoomScene) -> CharacterBehavior.Intent? {
        guard case .motion(let intent, _)? = scene.runner.current.character(id)?.activity else { return nil }
        return intent
    }

    @Test func sceneTellsTheSimulationHowLongSinceTheLastTap() throws {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let scene = try Self.scene(lastTaps: [Self.id: now.addingTimeInterval(-5 * 3600)])
        RoomSceneTests.play(scene.runner, until: 0.05)
        scene.tap(Self.id, now: 0.1, date: now)
        RoomSceneTests.play(scene.runner, from: 0.1, until: 0.15)
        #expect(Self.intent(scene) == .react("happyHello"))
        #expect(scene.lastTaps[Self.id] == now)             // 這次記下來
        RoomSceneTests.play(scene.runner, from: 0.15, until: 3)   // 像遊戲迴圈一樣推進：開心哈囉 2 秒播完
        #expect(Self.intent(scene) == nil)
        scene.tap(Self.id, now: 3, date: now.addingTimeInterval(3))
        RoomSceneTests.play(scene.runner, from: 3, until: 3.05)
        #expect(TapReactionTests.isTilt(Self.intent(scene)))   // 剛點過、看得到臉：歪頭
    }

    @Test func neverTappedCountsAsAway() throws {
        let scene = try Self.scene(lastTaps: [:])
        RoomSceneTests.play(scene.runner, until: 0.05)
        scene.tap(Self.id, now: 0.1)
        RoomSceneTests.play(scene.runner, from: 0.1, until: 0.15)
        #expect(Self.intent(scene) == .react("happyHello"))
    }
}

extension EventLogTests {
    @Test func lastTapsAreTheNewestPerCharacter() async throws {
        let (_, log) = try await Self.open()
        let at = { (second: Double) in Date(timeIntervalSince1970: second) }
        await log.record(.ownerTapped, characterID: "a", at: at(10))
        await log.record(.ownerTapped, characterID: "a", at: at(30))
        await log.record(.ownerTapped, characterID: "a", at: at(20))
        await log.record(.ownerTapped, characterID: "b", at: at(5))
        await log.record(.ownerTapped, characterID: nil, at: at(99))
        let taps = await log.lastTaps(of: ["a", "b", "never"])
        #expect(taps == ["a": at(30), "b": at(5)])          // 從來沒被點過的不在裡面
    }
}
