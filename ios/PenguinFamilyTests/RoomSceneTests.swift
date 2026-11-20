import CoreGraphics
import Foundation
import QuartzCore
import Testing
@testable import PenguinFamily

/// 箱庭與模擬的驅動（ADR 0008）：箱庭只建一次、一開始在台上的企鵝、點擊送進模擬、照真實時間跑節拍、
/// 沒事時跳過、落後太多時丟掉時間、畫的時間晚一個節拍；一家的身分與一開始誰在台上。
@MainActor
struct RoomSceneTests {
    static let ids = [PenguinID("first"), PenguinID("second")]
    static let positions = [TilePosition(i: 4.5, j: 4.5), TilePosition(i: 5.5, j: 3.5)]
    static let tick = 1.0 / Double(Simulation.ticksPerSecond)

    /// 兩隻都上台、不閒晃；真實時間從 `now` 開始。
    static func scene(now: Double = 100) throws -> RoomScene {
        let rig = try VectorRigTests.rig(VectorRigTests.walkingJSON)
        return RoomScene(room: .indoor, cast: ids.map { .init(id: $0, vector: rig) },
                         start: zip(ids, positions).map { (id: $0, position: $1) }, seed: 1, now: now)
    }

    /// 模擬只有第一隻、不閒晃；`events` 在第一個節拍生效。真實時間從 0 開始。
    static func runner(_ events: Simulation.Event...) -> SimulationRunner {
        var simulation = Simulation(room: .indoor, cast: [.init(id: ids[0])], seed: 1)
        simulation.send(.enter(ids[0], at: positions[0]))
        for event in events { simulation.send(event) }
        return SimulationRunner(simulation: simulation, now: 0, extraTickDelay: 0)
    }

    /// 不開執行緒，像遊戲迴圈一樣每秒 60 次推進到 `end`（真實時間）；回傳這段期間跑出來的事。
    @discardableResult
    static func play(_ runner: SimulationRunner, from start: Double = 0, until end: Double) -> [Simulation.Output] {
        var frame = Int((start * 60).rounded(.up))
        var outputs: [Simulation.Output] = []
        while Double(frame) / 60 <= end + 1e-9 {
            outputs += runner.advance(to: Double(frame) / 60)
            frame += 1
        }
        return outputs
    }

    // MARK: - 箱庭只建一次（2026-11-18）

    @Test func recreatingRoomViewDoesNotBuildAScene() {
        // SwiftUI 每次重算上一層的 body 都會重新建立 RoomView；箱庭等第一次出現才建，不能跟著重建
        let before = RoomScene.createdCount
        for _ in 0..<3 {
            _ = RoomView(room: .indoor, cast: Self.ids.map { .init(id: $0) }, start: [(Self.ids[0], Self.positions[0])])
        }
        #expect(RoomScene.createdCount == before)
    }

    @Test func sceneStartsWithTheGivenPenguinsOnStage() throws {
        let scene = try Self.scene()
        #expect(scene.runner.current.penguins.isEmpty)                             // 還沒跑節拍
        scene.runner.advance(to: 100.05)
        #expect(scene.runner.current.penguins.map(\.id) == Self.ids)
        #expect(scene.runner.current.penguin(Self.ids[0])?.position == Self.positions[0])
    }

    @Test func tappingAPenguinTellsTheSimulation() throws {
        let scene = try Self.scene()
        var woke = 0
        scene.runner.onWake = { woke += 1 }
        scene.runner.advance(to: 100.05)
        scene.builder.resize(viewport: CGSize(width: 402, height: 874), displayScale: 3)
        let runner = scene.runner
        _ = scene.builder.build(previous: runner.previous, current: runner.current, at: runner.renderTime(at: 100), now: 100)
        let feet = IsoProjection(room: .indoor).feet(at: Self.positions[0])
        let transform = try #require(scene.builder.viewTransform)
        let point = CGPoint(x: (feet.x - transform.topLeftX) * transform.pointsPerUnit,
                            y: (feet.y - 3 - transform.topLeftY) * transform.pointsPerUnit)
        let tapped = Date(timeIntervalSince1970: 1000)
        #expect(scene.tap(at: point, now: 100.1, date: tapped) == Self.ids[0])
        #expect(woke == 1)                                                          // 送了事件：叫醒遊戲迴圈
        #expect(scene.tap(at: .zero, now: 100.1) == nil)                            // 點空地：沒有反應
        #expect(scene.runner.isActive)                                              // 事件還在收件匣：遊戲迴圈要繼續
        #expect(scene.runner.advance(to: 100.2) == [.ownerTapped(Self.ids[0], at: tapped)])
        guard case .motion(.hello, _)? = scene.runner.current.penguin(Self.ids[0])?.activity else {
            Issue.record("第一隻沒有哈囉")
            return
        }
    }

    // MARK: - 驅動模擬

    @Test func runsTicksToTheWallClock() {
        let runner = Self.runner(.input(Self.ids[0], .walkRequested(to: Tile(i: 8, j: 4), pace: .walk)))
        Self.play(runner, until: 1)
        #expect(runner.current.tick == 30)
        #expect(runner.previous.tick == 29)
        let position = runner.current.penguin(Self.ids[0])?.position
        #expect(abs((position?.i ?? 0) - 5.0) < 1e-9)                              // 從模擬時間 0 開始，慢走每秒半格
        #expect(runner.isActive)
        #expect(abs(runner.renderTime(at: 1) - (1 - Self.tick)) < 1e-9)            // 畫的時間晚一個節拍
    }

    @Test func idleTimeIsSkippedAndStandingWakesOnTime() {
        let runner = Self.runner(.input(Self.ids[0], .standRequested(facing: nil, seconds: 2)))
        #expect(Self.play(runner, until: 0.1).isEmpty)
        #expect(!runner.isActive && runner.current.wakeAt == 2)                     // 站著：不用一直跑，站滿再醒來
        #expect(runner.advance(to: 1.5).isEmpty)                                    // 中間不補跑：直接跳過去
        #expect(runner.current.tick == 45)
        #expect(runner.advance(to: 2 + Self.tick) == [.finished(Self.ids[0])])
        runner.advance(to: 60)                                                      // 沒事：直接跳到現在
        #expect(runner.current.tick == 1800 && runner.previous == runner.current)
    }

    @Test func fallingFarBehindDropsTheTime() {
        let runner = Self.runner(.input(Self.ids[0], .walkRequested(to: Tile(i: 8, j: 4), pace: .walk)))
        Self.play(runner, until: 0.5)
        let before = runner.current.tick
        runner.advance(to: 10)                                                      // 例如從背景回來：不快轉
        #expect(runner.current.tick == before + SimulationRunner.maxCatchUpTicks)
        #expect(abs(runner.renderTime(at: 10) - (runner.current.time - Self.tick)) < 1e-9)   // 時間重新對齊
    }

    @Test func simulationRunsOnItsOwnThread() async throws {
        // ADR 0008：模擬在自己的執行緒跑，主執行緒不呼叫 advance；事件從主執行緒送進去，輸出依序交回主執行緒
        var simulation = Simulation(room: .indoor, cast: [.init(id: Self.ids[0])], seed: 1)
        simulation.send(.enter(Self.ids[0], at: Self.positions[0]))
        simulation.send(.input(Self.ids[0], .walkRequested(to: Tile(i: 8, j: 4), pace: .walk)))
        let runner = SimulationRunner(simulation: simulation, now: CACurrentMediaTime(), extraTickDelay: 0)
        var outputs: [Simulation.Output] = []
        var woke = 0
        runner.onOutputs = { outputs += $0 }
        runner.onWake = { woke += 1 }
        runner.start()
        defer { runner.stop() }
        for _ in 0..<150 where runner.current.tick < 15 { try await Task.sleep(for: .milliseconds(20)) }
        #expect(runner.current.tick >= 15)
        #expect(woke > 0)                                                           // 樣子變了：叫醒遊戲迴圈
        let tapped = Date(timeIntervalSince1970: 7)
        runner.send(.ownerTapped(Self.ids[0], at: tapped))
        for _ in 0..<150 where outputs.isEmpty { try await Task.sleep(for: .milliseconds(20)) }
        #expect(outputs == [.ownerTapped(Self.ids[0], at: tapped)])
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
}
