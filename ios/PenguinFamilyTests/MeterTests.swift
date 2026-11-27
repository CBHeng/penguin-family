import Foundation
import Testing
@testable import PenguinFamily

/// 角色的屬性條（作者 2026-11-27 要求）：快照照每隻的資料列出牠有的屬性（睏意、耐心）與門檻線，不寫死有哪些；
/// 往前推算的值和模擬算的相同（模擬停下來時介面照樣看得到在變）；沒有資料的角色沒有屬性；模擬時間的換算。
struct MeterTests {
    static let id = CharacterID("meters")

    /// 打瞌睡 60、睡覺 90 的睏意（每秒降 1、站著時不增加），加上預設的點一下的反應。
    static func wander() -> WanderConfig {
        var config = DozeTests.config(idle: true)
        config.sleepiness?.sleep = .init(above: 90, chance: 0.5, fallPerMinute: 40, wakeBelow: 15, cooldown: 60)
        return config
    }

    static func simulation(wander: WanderConfig? = wander(), interactions: InteractionConfig? = TapReactionTests.config) -> Simulation {
        var sim = Simulation(room: .indoor, cast: [.init(id: id, motions: TapReactionTests.motions, wander: wander,
                                                          interactions: interactions)], seed: 1)
        sim.send(.enter(id, at: TilePosition(i: 4.5, j: 4.5)))
        _ = sim.step()
        return sim
    }

    static func meters(_ sim: Simulation) -> [SimulationSnapshot.Meter] { sim.snapshot.character(id)?.meters ?? [] }

    @Test func snapshotListsWhatTheCharactersDataHas() {
        let meters = Self.meters(Self.simulation())
        #expect(meters.map(\.id) == ["sleepiness", "patience"])
        #expect(meters.map(\.label) == ["睏意", "耐心"])
        #expect(meters[0].range == 0...100 && meters[1].range == 0...100)
        // 門檻線從這隻自己的資料讀
        #expect(meters[0].marks == [.init(value: 60, label: "打瞌睡"), .init(value: 90, label: "睡覺")])
        #expect(meters[1].marks == [.init(value: 20, label: "不耐煩")])
    }

    @Test func onlyWhatTheDataHas() {
        #expect(Self.meters(Self.simulation(wander: nil, interactions: nil)).isEmpty)
        #expect(Self.meters(Self.simulation(interactions: nil)).map(\.id) == ["sleepiness"])
        #expect(Self.meters(Self.simulation(wander: nil)).map(\.id) == ["patience"])
        var noSleep = Self.wander()
        noSleep.sleepiness?.sleep = nil
        #expect(Self.meters(Self.simulation(wander: noSleep)).first?.marks.map(\.value) == [60])   // 沒有睡覺就沒有那條線
    }

    @Test func extrapolatedLevelsMatchTheSimulation() {
        var sim = Self.simulation()
        sim.send(.ownerTapped(Self.id, at: .now))
        _ = sim.step()
        let tappedAt = sim.time
        let patience = Self.meters(sim)[1]
        // 快照只在耐心改變時記下一次；之後介面照每秒回升往前推算，和模擬算的一樣
        for later in [0.0, 1, 3, 10] {
            let t = tappedAt + later
            var copy = sim
            while copy.time < t - 1e-9 { _ = copy.step() }
            #expect(abs(patience.level(at: copy.time) - (copy.patience(of: Self.id) ?? -1)) < 1e-9)
        }
        #expect(patience.level(at: tappedAt + 1000) == 100)   // 回滿就停
        // 打瞌睡時睏意在降：一樣照快照往前推算
        var dozing = Self.simulation(wander: DozeTests.config(wakeBelow: 0))
        while dozing.time < 1.5 { _ = dozing.step() }
        let sleepiness = Self.meters(dozing)[0]
        #expect(sleepiness.perSecond < 0)
        #expect(abs(sleepiness.level(at: dozing.time + 5) - ((dozing.sleepiness(of: Self.id) ?? 0) - 5)) < 1e-9)
    }

    @Test func levelStaysInRange() {
        let meter = SimulationSnapshot.Meter(id: "x", label: "x", range: 0...100, value: 50, since: 10, perSecond: -2, marks: [])
        #expect(meter.level(at: 10) == 50)
        #expect(meter.level(at: 20) == 30)
        #expect(meter.level(at: 100) == 0)
    }

    @Test func runnerTellsTheSimulationTime() {
        let runner = SimulationRunner(simulation: Self.simulation(), now: 100, extraTickDelay: 0)
        let start = runner.current.time
        #expect(abs(runner.simulationTime(at: 103) - (start + 3)) < 1e-9)
    }
}
