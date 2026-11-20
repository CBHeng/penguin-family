import CoreGraphics
import Foundation

/// 一個箱庭在 App 裡的東西（ADR 0008）：模擬與它的驅動、畫面準備。`RoomView` 第一次出現時建一次，之後一直沿用。
///
/// 手勢與遊戲迴圈都透過它：拖曳、捏合交給畫面準備（只動鏡頭）；點到企鵝時把「主人點了這一隻」送進模擬。
/// 模擬交出的事（輸出事件）由 `runner.onOutputs` 交給外面（例如事件紀錄）。
final class RoomScene {
    /// 後台名單的一隻：身分、造型、動作細節與閒晃。名單的順序就是一家的順序，最前面的是第一隻。
    struct Member {
        let id: PenguinID
        /// 向量造型；nil 時借別隻的形狀塗灰，都沒有時用灰色剪影。
        var vector: VectorRig? = nil
        var motions: PenguinMotions = .standard
        /// 閒晃的資料；nil 時牠只站著。
        var wander: WanderConfig? = nil
    }

    /// 到目前為止建過幾個箱庭。測試用：確認 `RoomView` 被重新建立時不會跟著重建。
    private(set) static var createdCount = 0

    let builder: FrameBuilder
    let runner: SimulationRunner

    /// `start` 是一開始在台上的企鵝與站的位置，依上台先後；第一個節拍上台、開始閒晃。
    /// `seed` 是閒晃的亂數種子，`now` 是現在的真實時間。
    init(room: RoomLayout, cast: [Member], start: [(id: PenguinID, position: TilePosition)], seed: UInt64, now: Double) {
        Self.createdCount += 1
        var simulation = Simulation(room: room, cast: cast.map { .init(id: $0.id, motions: $0.motions, wander: $0.wander) },
                                    seed: seed)
        for penguin in start { simulation.send(.enter(penguin.id, at: penguin.position)) }
        runner = SimulationRunner(simulation: simulation, now: now)
        builder = FrameBuilder(room: room, cast: cast.map { .init(id: $0.id, vector: $0.vector, motions: $0.motions) })
    }

    /// 主人點了畫面上的這一點：點到企鵝就重新計算閒置，並告訴模擬主人點了牠（`date` 是點的當下，記錄用）。
    /// 回傳點到哪一隻；沒點到是 nil。
    @discardableResult
    func tap(at point: CGPoint, now: Double, date: Date = .now) -> PenguinID? {
        guard let id = builder.penguin(at: point) else { return nil }
        builder.ownerTouched(now: now)
        runner.send(.ownerTapped(id, at: date))
        return id
    }
}
