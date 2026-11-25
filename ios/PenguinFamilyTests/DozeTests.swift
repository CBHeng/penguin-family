import Foundation
import Testing
@testable import PenguinFamily

/// 打瞌睡（A1 第 13 項，作者 2026-11-20、11-23 決定）：睏意怎麼增減、狀態機（坐下 → 打瞌睡 → 自己醒來或被點驚醒）、
/// 閒晃照睏意決定要不要打瞌睡、模擬算好什麼時候醒、除錯用的加睏意。時間都是模擬的秒，不碰畫面。
struct DozeTests {
    // MARK: - 睏意

    @Test func sleepinessChangesAtTheCurrentRate() {
        var s = Sleepiness(value: 40, at: 10, perSecond: 0.5)
        #expect(s.level(at: 10) == 40)
        #expect(s.level(at: 20) == 45)
        s.change(perSecond: -1, at: 20)          // 之前的照舊的速度算到 20 秒
        #expect(s.level(at: 20) == 45)
        #expect(s.level(at: 30) == 35)
        #expect(s.secondsUntil(fallingTo: 30, from: 20) == 15)
        #expect(s.secondsUntil(fallingTo: 50, from: 20) == 0)       // 已經比它低
        s.add(30, at: 30)
        #expect(s.level(at: 30) == 65)
    }

    @Test func sleepinessStaysBetweenZeroAndHundred() {
        var s = Sleepiness(value: 150, at: 0, perSecond: 1)
        #expect(s.level(at: 0) == 100 && s.level(at: 50) == 100)
        s.change(perSecond: -10, at: 0)
        #expect(s.level(at: 20) == 0)
        s.add(-5, at: 20)
        #expect(s.level(at: 20) == 0)
        #expect(Sleepiness(value: 50, at: 0).secondsUntil(fallingTo: 10, from: 0) == 0)   // 沒在降
    }

    // MARK: - 狀態機

    static func intents(_ inputs: [CharacterBehavior.Input]) -> [CharacterBehavior.Intent] {
        var behavior = CharacterBehavior()
        return inputs.map { input in
            behavior.handle(input)
            return behavior.intent
        }
    }

    @Test func dozeSitsDownDozesAndStandsUpByItself() {
        #expect(Self.intents([.dozeRequested, .motionFinished, .motionFinished, .dozeEnded, .motionFinished])
                == [.sitDown, .doze, .doze, .standUp, .idle])
    }

    @Test func tapWhileDozingWakesWithAStart() {
        #expect(Self.intents([.dozeRequested, .ownerTapped, .motionFinished]) == [.sitDown, .wakeStartled, .idle])
        #expect(Self.intents([.dozeRequested, .motionFinished, .ownerTapped, .ownerTapped, .motionFinished])
                == [.sitDown, .doze, .wakeStartled, .wakeStartled, .idle])
    }

    @Test func standingUpIgnoresTapsAndRequests() {
        #expect(Self.intents([.dozeRequested, .motionFinished, .dozeEnded, .ownerTapped, .standRequested(facing: nil, seconds: 1)])
                == [.sitDown, .doze, .standUp, .standUp, .standUp])
        // 打瞌睡時不接別的事；沒在打瞌睡時「醒來」不理
        #expect(Self.intents([.dozeRequested, .motionFinished, .moveRequested(to: Tile(i: 1, j: 1), pace: .slow), .dozeRequested])
                == [.sitDown, .doze, .doze, .doze])
        #expect(Self.intents([.dozeEnded]) == [.idle])
    }

    @Test func dozeIntentsPlayTheirOwnMotions() {
        #expect(CharacterBehavior.Intent.playing.compactMap(\.motionName) == ["hello", "sitDown", "doze", "standUp", "wakeStartled",
                                                                                "climbIn", "sleep", "wakeTapped", "wakeRested"])
    }

    // MARK: - 閒晃照睏意決定

    /// 打瞌睡的門檻 60、每分鐘降 60（每秒 1）、降到 `wakeBelow` 醒；閒晃只有發呆 5 秒（`idle` 時什麼都不做，一直待機）。
    static func config(chance: Double = 1, cooldown: Double = 30, start: Double = 70, wakeBelow: Double = 50, idle: Bool = false,
                       rise: WanderConfig.SleepinessConfig.Rise = .init(still: 0, slow: 0, fast: 0)) -> WanderConfig {
        WanderConfig(version: 3, pace: .init(slow: 1, fast: 0),
                     activities: [WanderTests.activity("z", .zoneOut, weight: idle ? 0 : 1, seconds: 5...5)],
                     sleepiness: .init(start: start...start, risePerMinute: rise,
                                       doze: .init(above: 60, chance: chance, fallPerMinute: 60, wakeBelow: wakeBelow,
                                                   cooldown: cooldown)))
    }

    @Test func wanderDozesOnlyWhenSleepyEnough() {
        var routine = WanderRoutine(config: Self.config(), room: .indoor)
        var rng = WanderTests.SeededGenerator(seed: 3)
        #expect(routine.next(from: WanderTests.here, now: 0, sleepiness: 59, using: &rng) != .doze)
        #expect(routine.next(from: WanderTests.here, now: 0, sleepiness: nil, using: &rng) != .doze)   // 沒有打瞌睡的動作
        #expect(routine.next(from: WanderTests.here, now: 0, sleepiness: 60, using: &rng) == .doze)
        #expect(routine.activity == "doze")
    }

    @Test func wanderWaitsForTheCooldownAfterWaking() {
        var routine = WanderRoutine(config: Self.config(cooldown: 30), room: .indoor)
        var rng = WanderTests.SeededGenerator(seed: 3)
        routine.dozeEnded(at: 100)
        #expect(routine.next(from: WanderTests.here, now: 129, sleepiness: 90, using: &rng) != .doze)
        #expect(routine.next(from: WanderTests.here, now: 130, sleepiness: 90, using: &rng) == .doze)
    }

    /// 越睏越容易打瞌睡（作者 2026-11-23 要求）：門檻是 `chance`，之後每多滿 5 再加 10%，最多 100%。
    @Test func chanceRisesWithSleepiness() {
        var doze = Self.config(chance: 0.3).sleepiness!.doze
        #expect(doze.chance(at: 70) == 0.3)                       // 沒寫 chanceRise：固定
        doze.chanceRise = .init(every: 5, add: 0.1)
        #expect(doze.chance(at: 59.9) == 0)
        #expect(doze.chance(at: 60) == 0.3 && doze.chance(at: 64.9) == 0.3)
        #expect(abs(doze.chance(at: 65) - 0.4) < 1e-12 && abs(doze.chance(at: 79) - 0.6) < 1e-12)
        #expect(doze.chance(at: 95) == 1 && doze.chance(at: 100) == 1)
    }

    @Test func wanderDozesByChance() {
        var routine = WanderRoutine(config: Self.config(chance: 0.3), room: .indoor)
        var rng = WanderTests.SeededGenerator(seed: 7)
        let dozes = (0..<1000).filter { _ in routine.next(from: WanderTests.here, now: 0, sleepiness: 80, using: &rng) == .doze }
        #expect((250...350).contains(dozes.count), "1000 次裡打瞌睡 \(dozes.count) 次")
    }

    @Test func sleepinessNumbersMustMakeSense() {
        func problem(_ change: (inout WanderConfig.SleepinessConfig) -> Void) -> WanderConfigError? {
            var config = Self.config()
            change(&config.sleepiness!)
            do {
                try config.validate()
                return nil
            } catch {
                return error as? WanderConfigError
            }
        }
        #expect(problem { _ in } == nil)
        #expect(problem { $0.start = -1...10 } == .invalid("sleepiness.start"))
        #expect(problem { $0.risePerMinute.slow = -1 } == .invalid("sleepiness.risePerMinute"))
        #expect(problem { $0.doze.wakeBelow = 60 } == .invalid("sleepiness.doze.above"))
        #expect(problem { $0.doze.chance = 1.5 } == .invalid("sleepiness.doze.chance"))
        #expect(problem { $0.doze.chanceRise = .init(every: 0, add: 0.1) } == .invalid("sleepiness.doze.chanceRise"))
        #expect(problem { $0.doze.chanceRise = .init(every: 5, add: -0.1) } == .invalid("sleepiness.doze.chanceRise"))
        #expect(problem { $0.doze.fallPerMinute = 0 } == .invalid("sleepiness.doze.fallPerMinute"))
        #expect(problem { $0.doze.cooldown = -1 } == .invalid("sleepiness.doze.cooldown"))
    }

    // MARK: - 模擬

    static let id = CharacterID("sleepy")
    /// 打瞌睡用的動作資料（只要長度與循環，模擬不看片段）：坐下 1 秒、打瞌睡 2 秒一個循環、自己醒來 1 秒、驚醒 1 秒。
    static let motions = CharacterMotions(motions: [
        "hello": .init(duration: 1, facing: .front),
        "sitDown": .init(duration: 1),
        "doze": .init(duration: 2, cycle: 2),
        "standUp": .init(duration: 1),
        "wakeStartled": .init(duration: 1, facing: .front),
    ], gaits: CharacterMotions.defaultGaits)

    /// 一隻上台（第一個節拍），面向左前。
    static func simulation(motions: CharacterMotions = motions, wander: WanderConfig = config()) -> Simulation {
        var sim = Simulation(room: .indoor, cast: [.init(id: id, motions: motions, wander: wander)], seed: 1)
        sim.send(.enter(id, at: TilePosition(i: 4.5, j: 4.5)))
        sim.send(.input(id, .standRequested(facing: .frontLeft, seconds: 0)))
        return sim
    }

    static func run(_ sim: inout Simulation, until seconds: Double) {
        while sim.time < seconds - 1e-9 { _ = sim.step() }
    }

    static func intent(_ sim: Simulation) -> CharacterBehavior.Intent? { sim.behavior(of: id)?.intent }

    @Test func sleepyCharacterSitsDownDozesAndWakesWhenRested() throws {
        var sim = Self.simulation()
        _ = sim.step()
        #expect(Self.intent(sim) == .sitDown)                     // 一上台就睏（70），機率 1
        Self.run(&sim, until: 1.1)
        #expect(Self.intent(sim) == .doze)
        guard case .motion(.doze, let since)? = sim.snapshot.character(Self.id)?.activity else {
            Issue.record("快照沒有在打瞌睡")
            return
        }
        #expect(abs(since - 1) <= 2 * SimulationTests.tick)         // 上台後第一個節拍坐下，坐 1 秒
        #expect(sim.snapshot.character(Self.id)?.facing == .frontLeft)   // 維持原本的方向
        // 每秒降 1：降到 50 要 20 秒，剛好是 10 個循環，第 21 秒自己醒來
        Self.run(&sim, until: 11)
        #expect(abs(try #require(sim.sleepiness(of: Self.id)) - 60) < 0.1)
        Self.run(&sim, until: 20.9)
        #expect(Self.intent(sim) == .doze)
        Self.run(&sim, until: 21.1)
        #expect(Self.intent(sim) == .standUp)
        Self.run(&sim, until: 22.1)
        #expect(Self.intent(sim) == .stand(facing: nil, seconds: 5))   // 不睏了，回到閒晃（發呆）
        #expect(abs(try #require(sim.sleepiness(of: Self.id)) - 50) < 0.1)
    }

    @Test func wakingWaitsForTheEndOfTheDozeLoop() throws {
        // 從 61 降到 58 要 3 秒，循環 2 秒：等到第 2 個循環結束（4 秒）才醒，頭剛抬起來
        var sim = Self.simulation(wander: Self.config(start: 61, wakeBelow: 58))
        Self.run(&sim, until: 1 + 3.9)
        #expect(Self.intent(sim) == .doze)
        Self.run(&sim, until: 1 + 4.1)
        #expect(Self.intent(sim) == .standUp)
        // 多睡的那 1 秒照樣在降：醒來時比 58 再低一點（最多低一個循環降的量，這裡是 2）
        let level = try #require(sim.sleepiness(of: Self.id))
        #expect(abs(level - 57) < 0.1)
    }

    /// 只有打瞌睡的循環在降：坐下、驚醒揉眼睛、之後站著，都照「站著」的速度增加。
    @Test func sleepinessFallsOnlyWhileDozing() throws {
        // 站著每分鐘 +6（每秒 0.1），打瞌睡每分鐘 -60（每秒 1）
        var sim = Self.simulation(wander: Self.config(cooldown: 30, rise: .init(still: 6, slow: 6, fast: 6)))
        Self.run(&sim, until: 0.5)
        #expect(Self.intent(sim) == .sitDown)
        let sitting = try #require(sim.sleepiness(of: Self.id))
        Self.run(&sim, until: 0.9)
        #expect(Self.intent(sim) == .sitDown)
        #expect(abs(try #require(sim.sleepiness(of: Self.id)) - (sitting + 0.04)) < 1e-6)   // 坐下時還在增加
        Self.run(&sim, until: 2)
        #expect(Self.intent(sim) == .doze)
        let dozing = try #require(sim.sleepiness(of: Self.id))
        Self.run(&sim, until: 4)
        #expect(abs(try #require(sim.sleepiness(of: Self.id)) - (dozing - 2)) < 1e-6)       // 打瞌睡時每秒降 1
        sim.send(.ownerTapped(Self.id, at: .now))
        _ = sim.step()
        #expect(Self.intent(sim) == .wakeStartled)
        let woke = try #require(sim.sleepiness(of: Self.id))
        Self.run(&sim, until: 6)
        #expect(abs(try #require(sim.sleepiness(of: Self.id)) - (woke + 0.1 * (6 - 4 - SimulationTests.tick))) < 1e-6)  // 醒來後照站著增加
    }

    @Test func tapWhileDozingWakesWithAStartAndCoolsDown() throws {
        var sim = Self.simulation(wander: Self.config(cooldown: 30))
        Self.run(&sim, until: 3)
        #expect(Self.intent(sim) == .doze)
        _ = sim.step()
        sim.send(.ownerTapped(Self.id, at: .now))
        _ = sim.step()
        #expect(Self.intent(sim) == .wakeStartled)
        #expect(sim.snapshot.character(Self.id)?.facing == .front)      // 轉向鏡頭
        let level = try #require(sim.sleepiness(of: Self.id))
        Self.run(&sim, until: 5)
        // 醒了不再降；還很睏，但冷卻中不會馬上又打瞌睡
        #expect(abs(try #require(sim.sleepiness(of: Self.id)) - level) < 1e-9)
        #expect(level > 60)
        #expect(Self.intent(sim) == .stand(facing: nil, seconds: 5))
        Self.run(&sim, until: 34.5)
        #expect([.sitDown, .doze].contains(Self.intent(sim)))
    }

    @Test func sleepinessRisesFasterWhileWalking() throws {
        let rise = WanderConfig.SleepinessConfig.Rise(still: 6, slow: 60, fast: 120)
        var sim = Self.simulation(wander: Self.config(start: 10, idle: true, rise: rise))
        _ = sim.step()
        #expect(abs(try #require(sim.sleepiness(of: Self.id)) - 10) < 0.01)
        sim.send(.input(Self.id, .moveRequested(to: Tile(i: 4, j: 10), pace: .slow)))
        let start = sim.time
        Self.run(&sim, until: start + 2)
        // 慢走每分鐘 60，走了 2 秒：多 2（站著的話只多 0.2）
        #expect(abs(try #require(sim.sleepiness(of: Self.id)) - 12) < 0.05)
    }

    @Test func charactersWithoutADozeMotionNeverDoze() {
        var sim = Self.simulation(motions: .placeholder)
        Self.run(&sim, until: 10)
        #expect(![.sitDown, .doze].contains(Self.intent(sim)))
    }

    @Test func debugButtonAddsSleepinessAndExtendsTheDoze() throws {
        var sim = Self.simulation(wander: Self.config(chance: 0, start: 30))
        _ = sim.step()
        sim.send(.addSleepiness(25))
        _ = sim.step()
        #expect(abs(try #require(sim.sleepiness(of: Self.id)) - 55) < 0.01)
        sim.send(.addSleepiness(80))
        _ = sim.step()
        #expect(try #require(sim.sleepiness(of: Self.id)) == 100)     // 最多 100

        // 打瞌睡時加：醒的時間往後延（每秒降 1，從 70 加到 95，要多睡 25 秒）
        var dozing = Self.simulation()
        Self.run(&dozing, until: 2)
        let before = try #require(dozing.wakeAt)
        dozing.send(.addSleepiness(25))
        _ = dozing.step()
        #expect(try #require(dozing.wakeAt) >= before + 24)
    }
}
