import Foundation
import Testing
@testable import PenguinFamily

/// 模擬（ADR 0008）：上台與下台、各自的動作、走路、站著、走路中被點、讓路、一起閒晃、結果固定、跳過節拍。
/// 時間都是模擬的時間（節拍數換算的秒）；不碰畫面，所以不用造型。用屋內箱庭。
struct SimulationTests {
    /// 後台名單的兩隻。
    static let ids = [PenguinID("first"), PenguinID("second")]
    /// 和 `GameView.startPositions` 相同。
    static let positions = [TilePosition(i: 4.5, j: 4.5), TilePosition(i: 5.5, j: 3.5)]
    /// 一個節拍幾秒：跨節拍才發生的事，時間允許差這麼多。
    static let tick = 1.0 / Double(Simulation.ticksPerSecond)

    typealias Timed = (time: Double, output: Simulation.Output)

    /// 後台名單是 `ids`，送出依序上台到 `positions` 的事件（給的位置比兩個少時，後面的留在後台）。
    /// 還沒跑節拍：第一次 `step` 時上台，和同一批送的事件一起在模擬時間 0 生效。預設不閒晃，只照事件動。
    static func simulation(positions: [TilePosition] = positions, motions: [PenguinMotions] = [.standard, .standard],
                           wander: WanderConfig? = nil, seed: UInt64 = 1) -> Simulation {
        var sim = Simulation(room: .indoor, cast: zip(ids, motions).map { .init(id: $0, motions: $1, wander: wander) },
                             seed: seed)
        for (id, position) in zip(ids, positions) { sim.send(.enter(id, at: position)) }
        return sim
    }

    /// 送出事件、跑一個節拍：事件在這個節拍開頭（跑之前的模擬時間）生效。
    @discardableResult
    static func step(_ sim: inout Simulation, _ events: Simulation.Event...) -> [Simulation.Output] {
        for event in events { sim.send(event) }
        return sim.step()
    }

    /// 一直跑到模擬時間 `seconds`，回傳每個輸出與它發生的時間；每個節拍記下兩隻的距離（格）。
    @discardableResult
    static func run(_ sim: inout Simulation, until seconds: Double, closest: inout Double) -> [Timed] {
        var outputs: [Timed] = []
        while sim.time < seconds - 1e-9 {
            let out = sim.step()
            let time = sim.time
            outputs += out.map { (time, $0) }
            let snapshot = sim.snapshot
            if let a = snapshot.penguin(ids[0])?.position, let b = snapshot.penguin(ids[1])?.position {
                closest = min(closest, ((a.i - b.i) * (a.i - b.i) + (a.j - b.j) * (a.j - b.j)).squareRoot())
            }
        }
        return outputs
    }

    @discardableResult
    static func run(_ sim: inout Simulation, until seconds: Double) -> [Timed] {
        var closest = Double.infinity
        return run(&sim, until: seconds, closest: &closest)
    }

    /// 一直跑，直到某個輸出出現（最多 `limit` 秒）；回傳它發生的時間。
    static func run(_ sim: inout Simulation, untilOutput match: (Simulation.Output) -> Bool, limit: Double = 60) -> Double? {
        let end = sim.time + limit
        while sim.time < end {
            if sim.step().contains(where: match) { return sim.time }
        }
        return nil
    }

    static func finished(_ outputs: [Timed]) -> [(time: Double, id: PenguinID)] {
        outputs.compactMap { timed -> (time: Double, id: PenguinID)? in
            guard case .finished(let id) = timed.output else { return nil }
            return (timed.time, id)
        }
    }

    static func arrivals(_ outputs: [Timed]) -> [(time: Double, id: PenguinID, tile: Tile)] {
        outputs.compactMap { timed -> (time: Double, id: PenguinID, tile: Tile)? in
            guard case .arrived(let id, let tile) = timed.output else { return nil }
            return (timed.time, id, tile)
        }
    }

    static func walk(_ id: PenguinID = SimulationTests.ids[0], to tile: Tile,
                     _ pace: PenguinBehavior.Pace = .walk) -> Simulation.Event {
        .input(id, .walkRequested(to: tile, pace: pace))
    }

    static func penguin(_ sim: Simulation, _ id: PenguinID = SimulationTests.ids[0]) -> SimulationSnapshot.Penguin? {
        sim.snapshot.penguin(id)
    }

    /// 位置差不到 1e-9 格。
    static func isAt(_ penguin: SimulationSnapshot.Penguin?, i: Double, j: Double) -> Bool {
        guard let p = penguin?.position else { return false }
        return abs(p.i - i) < 1e-9 && abs(p.j - j) < 1e-9
    }

    /// 正在走，步態是 `pace`、走了 `elapsed` 秒（差不到 1e-9）。
    static func isWalking(_ penguin: SimulationSnapshot.Penguin?, _ pace: PenguinBehavior.Pace, elapsed: Double) -> Bool {
        guard case .walking(let p, let e)? = penguin?.activity else { return false }
        return p == pace && abs(e - elapsed) < 1e-9
    }

    /// `time` 是 `expected` 之後的第一個節拍（允許差一個節拍）。
    static func near(_ time: Double?, _ expected: Double) -> Bool {
        guard let time else { return false }
        return time >= expected - 1e-9 && time <= expected + tick + 1e-9
    }

    // MARK: - 上台、下台（作者 2026-11-17 決定：用身分加入、移除）

    @Test func entersByIDOnce() {
        var sim = Self.simulation(positions: [Self.positions[0]])                   // 第二隻留在後台
        Self.step(&sim)
        #expect(sim.onStage == [Self.ids[0]])
        Self.step(&sim, .enter(Self.ids[0], at: Self.positions[1]),                 // 已經在台上：不做事，也不換位置
                  .enter(PenguinID("not-in-cast"), at: Self.positions[1]))          // 不在後台名單：不做事
        #expect(sim.onStage == [Self.ids[0]])
        #expect(Self.penguin(sim)?.position == Self.positions[0])
        Self.step(&sim, .enter(Self.ids[1], at: Self.positions[1]))
        #expect(sim.onStage == Self.ids)
        #expect(sim.snapshot.penguins.map(\.id) == Self.ids)                        // 依上台先後
    }

    @Test func leavingStopsTheMotionWithoutReportingIt() {
        var sim = Self.simulation()
        Self.step(&sim, .input(Self.ids[0], .ownerTapped))
        Self.step(&sim, .leave(Self.ids[0]))
        #expect(Self.run(&sim, until: 10).isEmpty)
        #expect(sim.onStage == [Self.ids[1]])
        Self.step(&sim, .input(Self.ids[0], .ownerTapped), .place(Self.ids[0], at: Self.positions[1]))   // 不在台上：不做事
        #expect(sim.onStage == [Self.ids[1]] && Self.penguin(sim) == nil)
    }

    // MARK: - 正面的動作

    @Test func eachPenguinPlaysItsOwnHello() {
        var sim = Self.simulation()
        let (first, second) = (Self.ids[0], Self.ids[1])
        Self.run(&sim, until: 10)
        Self.step(&sim, .ownerTapped(first, at: .distantPast))
        Self.run(&sim, until: 10.5)
        #expect(Self.penguin(sim, first)?.activity == .motion(.hello, since: 10))
        #expect(Self.penguin(sim, first)?.facing == .front)
        #expect(Self.penguin(sim, second)?.activity == .still)                      // 第二隻沒被點，照樣站著
        #expect(sim.isActive)
        Self.run(&sim, until: 11)
        Self.step(&sim, .ownerTapped(second, at: .distantPast))
        let finished = Self.finished(Self.run(&sim, until: 20))
        let duration = HelloMotion.standard.duration
        #expect(finished.map(\.id) == [first, second])                             // 各自播完，各回報一次
        #expect(Self.near(finished.first?.time, 10 + duration) && Self.near(finished.last?.time, 11 + duration))
        #expect(sim.behavior(of: first)?.intent == .idle && !sim.isActive)
    }

    @Test func everyTapIsRecordedEvenWhenIgnored() {
        var sim = Self.simulation()
        let tapped = Date(timeIntervalSince1970: 1000)
        #expect(Self.step(&sim, .ownerTapped(Self.ids[0], at: tapped)) == [.ownerTapped(Self.ids[0], at: tapped)])
        // 哈囉中再點：狀態機不理，但照樣記下
        #expect(Self.step(&sim, .ownerTapped(Self.ids[0], at: tapped + 1)) == [.ownerTapped(Self.ids[0], at: tapped + 1)])
        #expect(Self.penguin(sim)?.activity == .motion(.hello, since: 0))
    }

    // MARK: - 走路（A1 第 6 項）

    @Test func walksAlongThePathAtTheGaitSpeed() {
        var sim = Self.simulation(positions: [Self.positions[0]])
        let id = Self.ids[0]
        Self.step(&sim, Self.walk(to: Tile(i: 8, j: 4)))                           // 往右下（i 往前）走 4 格
        #expect(Self.penguin(sim)?.facing == .frontRight)
        Self.run(&sim, until: 1)
        #expect(Self.isAt(Self.penguin(sim), i: 5.0, j: 4.5))                       // 慢走每秒半格
        #expect(Self.isWalking(Self.penguin(sim), .walk, elapsed: 1))
        Self.run(&sim, until: 2.5)
        #expect(Self.isAt(Self.penguin(sim), i: 5.75, j: 4.5))
        let arrivals = Self.arrivals(Self.run(&sim, until: 9))
        #expect(arrivals.map(\.tile) == [Tile(i: 8, j: 4)])                         // 只回報一次
        #expect(Self.near(arrivals.first?.time, 8))
        #expect(Self.penguin(sim)?.position == Tile(i: 8, j: 4).center)
        #expect(Self.penguin(sim)?.activity == .still && Self.penguin(sim)?.facing == .frontRight)   // 走到後維持走的方向
        #expect(sim.behavior(of: id)?.intent == .idle && !sim.isActive)
    }

    @Test func turnsAtTheCornerAndGoesAroundTheSofa() {
        // 沙發在 i = 7、j = 6～8，先往 j 走會被擋，所以先往右前（i）再往左前（j）
        var sim = Self.simulation(positions: [Self.positions[0]])
        Self.step(&sim, Self.walk(to: Tile(i: 8, j: 7)))
        Self.run(&sim, until: 7.5)
        #expect(Self.penguin(sim)?.facing == .frontRight)
        Self.run(&sim, until: 8)                                                   // 剛好走到轉角
        #expect(Self.penguin(sim)?.facing == .frontLeft && Self.penguin(sim)?.position == Tile(i: 8, j: 4).center)
        let arrivals = Self.arrivals(Self.run(&sim, until: 15))
        #expect(arrivals.map(\.tile) == [Tile(i: 8, j: 7)] && Self.near(arrivals.first?.time, 14))
    }

    @Test func trotIsTwiceAsFast() {
        var sim = Self.simulation(positions: [Self.positions[0]])
        Self.step(&sim, Self.walk(to: Tile(i: 8, j: 4), .trot))
        Self.run(&sim, until: 1.5)
        #expect(Self.isWalking(Self.penguin(sim), .trot, elapsed: 1.5))
        #expect(Self.near(Self.arrivals(Self.run(&sim, until: 5)).first?.time, 4))
    }

    @Test func eachPenguinMovesWithItsOwnMotions() {
        // 作者 2026-11-19 決定：狀態兩隻共用，怎麼動每隻各一份；改第二隻的數字，第一隻照舊
        var quick = PenguinMotions.standard
        quick.walk.cycle = 0.5        // 慢走快一倍：每秒一格
        quick.hello.wave = 0.4        // 哈囉少揮 1 秒
        var sim = Self.simulation(positions: [TilePosition(i: 4.5, j: 4.5), TilePosition(i: 4.5, j: 2.5)],
                                  motions: [.standard, quick])
        let (first, second) = (Self.ids[0], Self.ids[1])
        Self.step(&sim, .input(first, .ownerTapped), .input(second, .ownerTapped))
        let hellos = Self.finished(Self.run(&sim, until: 10))
        #expect(hellos.map(\.id) == [second, first])                               // 第二隻先播完
        #expect(Self.near(hellos.first?.time, quick.hello.duration) && Self.near(hellos.last?.time, HelloMotion.standard.duration))

        Self.step(&sim, Self.walk(first, to: Tile(i: 8, j: 4)), Self.walk(second, to: Tile(i: 8, j: 2)))
        Self.run(&sim, until: 11)
        #expect(Self.isAt(Self.penguin(sim, first), i: 5.0, j: 4.5))               // 每秒半格
        #expect(Self.isAt(Self.penguin(sim, second), i: 5.5, j: 2.5))              // 每秒一格
        let arrivals = Self.arrivals(Self.run(&sim, until: 19))
        #expect(arrivals.map(\.id) == [second, first])
        #expect(Self.near(arrivals.first?.time, 14) && Self.near(arrivals.last?.time, 18))
    }

    @Test func unreachableGoalArrivesRightAwayWhereItStands() {
        var sim = Self.simulation(positions: [Self.positions[0]])
        let outputs = Self.step(&sim, Self.walk(to: Tile(i: 7, j: 7)))             // 沙發上
        #expect(outputs == [.arrived(Self.ids[0], Tile(i: 4, j: 4))])
        #expect(Self.penguin(sim)?.facing == .front)
    }

    @Test func placingIsIgnoredWhileWalking() {
        var sim = Self.simulation(positions: [Self.positions[0]])
        Self.step(&sim, Self.walk(to: Tile(i: 8, j: 4)))
        Self.run(&sim, until: 2)
        Self.step(&sim, .place(Self.ids[0], at: Self.positions[0]))
        #expect((Self.penguin(sim)?.position.i ?? 0) > 5.5)
    }

    // MARK: - 走路中被點（作者 2026-11-19 決定：當場停下哈囉，揮完接著走）

    @Test func helloStopsTheWalkWhereItIsThenKeepsWalking() throws {
        // 從 (4, 4) 往右前慢走到 (8, 4)，在第 2.5 秒（走了 1.25 格，在 (5, 4) 與 (6, 4) 之間）被點
        var sim = Self.simulation(positions: [Self.positions[0]])
        let id = Self.ids[0]
        Self.step(&sim, Self.walk(to: Tile(i: 8, j: 4)))
        Self.run(&sim, until: 2.5)
        Self.step(&sim, .ownerTapped(id, at: .distantPast))
        #expect(Self.isAt(Self.penguin(sim), i: 5.75, j: 4.5))                      // 停在當下的位置
        #expect(Self.penguin(sim)?.facing == .front && Self.penguin(sim)?.activity == .motion(.hello, since: 2.5))

        // 揮完：狀態機接回同一段路，從停的地方接著走、不跳回格子中心
        let resumed = try #require(Self.run(&sim, untilOutput: { $0 == .finished(id) }))
        #expect(Self.near(resumed, 2.5 + HelloMotion.standard.duration))
        #expect(Self.isAt(Self.penguin(sim), i: 5.75, j: 4.5))
        #expect(Self.penguin(sim)?.facing == .frontRight && Self.isWalking(Self.penguin(sim), .walk, elapsed: 0.5))
        Self.run(&sim, until: resumed + 0.5)
        #expect(Self.isAt(Self.penguin(sim), i: 6.0, j: 4.5))
        // 還剩 2.75 格，慢走 5.5 秒
        let arrived = Self.run(&sim, untilOutput: { $0 == .arrived(id, Tile(i: 8, j: 4)) })
        #expect(Self.near(arrived, resumed + 5.5))
    }

    @Test func goalAheadFromMidwayKeepsGoing() {
        let midway = Simulation.Midway(from: Tile(i: 5, j: 4), to: Tile(i: 6, j: 4), fraction: 0.25)
        let route = Simulation.route(from: TilePosition(i: 5.75, j: 4.5), midway: midway, to: Tile(i: 8, j: 4),
                                     avoiding: [], in: .indoor)
        #expect(route.path.tiles == [Tile(i: 5, j: 4), Tile(i: 6, j: 4), Tile(i: 7, j: 4), Tile(i: 8, j: 4)])
        #expect(route.walked == 0.25)
    }

    @Test func goalBehindTurnsBackWithoutJumping() {
        // 停在 (5, 4) 往 (6, 4) 走了 1/4 的地方，要回 (4, 4)：回頭比較近，路的第一步就是停的那一步
        let midway = Simulation.Midway(from: Tile(i: 5, j: 4), to: Tile(i: 6, j: 4), fraction: 0.25)
        let route = Simulation.route(from: TilePosition(i: 5.75, j: 4.5), midway: midway, to: Tile(i: 4, j: 4),
                                     avoiding: [], in: .indoor)
        #expect(route.path.tiles == [Tile(i: 6, j: 4), Tile(i: 5, j: 4), Tile(i: 4, j: 4)])
        #expect(route.walked == 0.75)
    }

    @Test func unreachableGoalFromMidwayStopsAtTheNearerTile() {
        let midway = Simulation.Midway(from: Tile(i: 5, j: 4), to: Tile(i: 6, j: 4), fraction: 0.25)
        let route = Simulation.route(from: TilePosition(i: 5.75, j: 4.5), midway: midway, to: Tile(i: 7, j: 7),
                                     avoiding: [], in: .indoor)                     // 沙發上
        #expect(route.path.tiles == [Tile(i: 6, j: 4), Tile(i: 5, j: 4)] && route.walked == 0.75)
    }

    // MARK: - 站著（A1 第 11 項：發呆、東張西望、在家具旁邊待一下）

    @Test func standTurnsThenReportsWhenDone() {
        var sim = Self.simulation(positions: [Self.positions[0]])
        let id = Self.ids[0]
        Self.run(&sim, until: 10)
        Self.step(&sim, .input(id, .standRequested(facing: .backRight, seconds: 3)))
        #expect(Self.penguin(sim)?.facing == .backRight && Self.penguin(sim)?.activity == .still)
        #expect(!sim.isActive && sim.wakeAt == 13)                                 // 不在動：可以停下來，站滿時再醒來
        let finished = Self.finished(Self.run(&sim, until: 14))
        #expect(finished.map(\.id) == [id] && Self.near(finished.first?.time, 13))  // 只回報一次
        #expect(Self.penguin(sim)?.facing == .backRight && sim.wakeAt == nil)       // 站滿後維持方向
    }

    @Test func sameStandTwiceStartsOver() {
        // 站滿回到待機，馬上又要牠往同一個方向站一樣久：要重新站、再回報一次，不能當作沒變而卡住
        var sim = Self.simulation(positions: [Self.positions[0]])
        let id = Self.ids[0]
        let stand = PenguinBehavior.Input.standRequested(facing: .front, seconds: 2)
        Self.step(&sim, .input(id, stand))
        let first = Self.finished(Self.run(&sim, until: 2.1))
        #expect(first.map(\.id) == [id] && Self.near(first.first?.time, 2))
        Self.step(&sim, .input(id, stand))                                         // 在 2.1 秒又要一次
        #expect(abs((sim.wakeAt ?? 0) - 4.1) < 1e-9)
        let second = Self.finished(Self.run(&sim, until: 5))
        #expect(second.map(\.id) == [id] && Self.near(second.first?.time, 4.1))
    }

    @Test func standWithoutFacingKeepsTheWalkingDirection() {
        var sim = Self.simulation(positions: [Self.positions[0]])
        Self.step(&sim, Self.walk(to: Tile(i: 5, j: 4)))
        #expect(Self.arrivals(Self.run(&sim, until: 2.1)).count == 1)
        Self.step(&sim, .input(Self.ids[0], .standRequested(facing: nil, seconds: 1)))
        #expect(Self.penguin(sim)?.facing == .frontRight)
    }

    @Test func helloInterruptsStanding() {
        var sim = Self.simulation(positions: [Self.positions[0]])
        let id = Self.ids[0]
        Self.step(&sim, .input(id, .standRequested(facing: .backLeft, seconds: 10)))
        Self.run(&sim, until: 1)
        Self.step(&sim, .input(id, .ownerTapped))
        #expect(Self.penguin(sim)?.facing == .front)
        let finished = Self.finished(Self.run(&sim, until: 20))
        #expect(finished.map(\.id) == [id])                                         // 哈囉播完；原本的站著不再回報
        #expect(Self.near(finished.first?.time, 1 + HelloMotion.standard.duration))
    }

    // MARK: - 兩隻互相讓路（A1 第 12 項，作者 2026-11-19 決定：先等、等不到再繞路）

    @Test func routeGoesAroundAPenguinStandingInTheWay() {
        // 第一隻站在 (6, 4)，第二隻從 (4, 4) 走到 (8, 4)：一開始就繞開，不用停下來等
        var sim = Self.simulation(positions: [Tile(i: 6, j: 4).center, Tile(i: 4, j: 4).center])
        Self.step(&sim, Self.walk(Self.ids[1], to: Tile(i: 8, j: 4)))
        var closest = Double.infinity
        let arrivals = Self.arrivals(Self.run(&sim, until: 14, closest: &closest))
        #expect(arrivals.map(\.tile) == [Tile(i: 8, j: 4)])
        #expect(Self.near(arrivals.first?.time, 12))                               // 繞一圈 6 步，慢走每秒半格
        #expect(closest >= 0.999)
    }

    @Test func waitsWhenSomeoneStepsInTheWayThenGoesAround() {
        // 第二隻從 (4, 4) 走向 (8, 4)，走到一半第一隻被放到 (6, 4) 擋住
        var sim = Self.simulation(positions: [Tile(i: 6, j: 7).center, Tile(i: 4, j: 4).center])
        let id = Self.ids[1]
        Self.step(&sim, Self.walk(id, to: Tile(i: 8, j: 4)))
        Self.run(&sim, until: 1)
        Self.step(&sim, .place(Self.ids[0], at: Tile(i: 6, j: 4).center))
        var closest = Double.infinity
        Self.run(&sim, until: 2.5, closest: &closest)
        // 停在 (5, 4) 的中心等，站姿、面向擋住的那一格；模擬繼續跑，看對方走開了沒
        #expect(Self.penguin(sim, id)?.position == Tile(i: 5, j: 4).center)
        #expect(Self.penguin(sim, id)?.activity == .still && Self.penguin(sim, id)?.facing == .frontRight)
        #expect(sim.isActive)
        // 第二隻等 1 秒後繞路（第一隻等 1.5 秒）
        Self.run(&sim, until: 3.0, closest: &closest)
        #expect(Self.penguin(sim, id)?.position == Tile(i: 5, j: 4).center)
        Self.run(&sim, until: 3.5, closest: &closest)
        #expect(Self.penguin(sim, id)?.position != Tile(i: 5, j: 4).center)
        #expect(Self.penguin(sim, id)?.facing != .frontRight)                      // 往旁邊繞
        let arrivals = Self.arrivals(Self.run(&sim, until: 20, closest: &closest))
        #expect(arrivals.map(\.tile) == [Tile(i: 8, j: 4)])
        #expect(closest >= 0.999)
    }

    @Test func givesUpWhenTheGoalIsTaken() {
        // 第一隻站在終點 (8, 4)：第二隻走到 (7, 4) 等，繞不過去，等滿 4 秒就停在那裡算走到
        var sim = Self.simulation(positions: [Tile(i: 8, j: 4).center, Tile(i: 4, j: 4).center])
        Self.step(&sim, Self.walk(Self.ids[1], to: Tile(i: 8, j: 4)))
        var closest = Double.infinity
        let arrivals = Self.arrivals(Self.run(&sim, until: 12, closest: &closest))
        #expect(arrivals.map(\.tile) == [Tile(i: 7, j: 4)])
        let time = arrivals.first?.time ?? 0
        #expect(time >= 6 + Simulation.giveUpAfter && time < 6.1 + Simulation.giveUpAfter)   // 6 秒走到 (7, 4)，再等 4 秒
        #expect(Self.penguin(sim, Self.ids[1])?.position == Tile(i: 7, j: 4).center)
        #expect(closest >= 0.999)
    }

    @Test func headOnTheyGetPastEachOther() {
        // 迎面走同一排：一隻停下來等，另一隻繞過去，最後都走到
        var sim = Self.simulation(positions: [Tile(i: 4, j: 4).center, Tile(i: 8, j: 4).center])
        Self.step(&sim, Self.walk(Self.ids[0], to: Tile(i: 8, j: 4)), Self.walk(Self.ids[1], to: Tile(i: 4, j: 4)))
        var closest = Double.infinity
        let arrivals = Self.arrivals(Self.run(&sim, until: 30, closest: &closest))
        let tiles = Dictionary(uniqueKeysWithValues: arrivals.map { ($0.id, $0.tile) })
        #expect(tiles == [Self.ids[0]: Tile(i: 8, j: 4), Self.ids[1]: Tile(i: 4, j: 4)])
        #expect(closest >= 0.999)
    }

    // MARK: - 閒晃

    @Test func wanderStartsWhenEntering() throws {
        let config = try #require(WanderConfig.bundled())
        var sim = Self.simulation(wander: config)
        Self.step(&sim)
        for id in Self.ids { #expect(sim.behavior(of: id)?.intent != .idle) }
    }

    @Test func twoPenguinsWanderWithoutBumpingIntoEachOther() throws {
        // 兩隻用 App 裡的 wander.json 一起閒晃 5 分鐘（固定種子）：從不疊在一起，也不會卡住
        let config = try #require(WanderConfig.bundled())
        var sim = Self.simulation(wander: config, seed: 42)
        var closest = Double.infinity
        let arrivals = Self.arrivals(Self.run(&sim, until: 300, closest: &closest))
        #expect(closest >= 0.999)
        for id in Self.ids {
            #expect(arrivals.filter { $0.id == id }.count >= 10, "\(id.rawValue) 走到的次數太少")
        }
    }

    // MARK: - 結果固定、停下來不補跑（ADR 0008）

    @Test func sameSeedAndEventsGiveTheSameResult() throws {
        let config = try #require(WanderConfig.bundled())
        func play(seed: UInt64) -> (outputs: [Simulation.Output], end: SimulationSnapshot) {
            var sim = Self.simulation(wander: config, seed: seed)
            var outputs = Self.run(&sim, until: 30).map(\.output)
            outputs += Self.step(&sim, .ownerTapped(Self.ids[0], at: Date(timeIntervalSince1970: 0)))
            outputs += Self.run(&sim, until: 120).map(\.output)
            return (outputs, sim.snapshot)
        }
        let (a, b) = (play(seed: 7), play(seed: 7))
        #expect(a.outputs == b.outputs && a.end == b.end)
        #expect(play(seed: 8).outputs != a.outputs)
    }

    @Test func idleSimulationSkipsAheadWithoutRunningTicks() {
        var sim = Self.simulation(positions: [Self.positions[0]])
        Self.step(&sim)                                                            // 上台；不閒晃，站著不動
        #expect(!sim.isActive && sim.wakeAt == nil)
        sim.skip(to: 300)
        #expect(sim.tick == 300 && sim.time == 10)
        Self.step(&sim, .input(Self.ids[0], .standRequested(facing: nil, seconds: 2)))
        #expect(!sim.isActive && sim.wakeAt == 12)                                 // 站著也不算在動
        sim.skip(to: 600)                                                          // 跳過站滿的時間：下一個節拍回報
        #expect(Self.step(&sim) == [.finished(Self.ids[0])])
        sim.send(.input(Self.ids[0], .ownerTapped))
        #expect(sim.isActive && !sim.isMoving)                                     // 有事件在等，但沒有東西在動：可以跳
        sim.skip(to: 900)
        Self.step(&sim)
        #expect(Self.penguin(sim)?.activity == .motion(.hello, since: 30))          // 點擊在跳過之後的時間生效
        sim.skip(to: 1000)                                                         // 在播哈囉：不跳
        #expect(sim.tick == 901 && sim.isMoving)
    }
}
