import CoreGraphics
import Foundation

/// 一個箱庭在 App 裡的東西（ADR 0008）：模擬與它的驅動、畫面準備。`RoomView` 第一次出現時建一次，之後一直沿用。
///
/// 手勢與遊戲迴圈都透過它：拖曳、捏合交給畫面準備（只動鏡頭）；點到角色時把「主人點了這一隻」送進模擬。
/// 模擬交出的事（輸出事件）由 `runner.onOutputs` 交給外面（例如事件紀錄）。
final class RoomScene {
    /// 後台名單的一隻：身分、造型、動作與閒晃。名單的順序就是一家的順序，最前面的是第一隻。
    struct Member {
        let id: CharacterID
        /// 向量造型；缺角色包的已經換成替身或灰色剪影（`StandIn`）。
        var vector: VectorRig = .placeholder
        /// 動作資料：一次性動作的長度與片段、慢與快的步態。
        var motions: CharacterMotions = .placeholder
        /// 閒晃的資料；nil 時牠只站著。
        var wander: WanderConfig? = nil

        /// 一家每一隻上台用的東西：缺角色包的換成替身（`StandIn`）；閒晃用角色包自己的，沒帶時用 `defaultWander`
        /// （作者 2026-11-19 決定每隻各自獨立）。
        static func cast(_ family: [FamilyMember], defaultWander: WanderConfig?) -> [Member] {
            zip(family, StandIn.resolve(family)).map { member, look in
                Member(id: member.id, vector: look.vector, motions: look.motions,
                       wander: member.character?.wander ?? defaultWander)
            }
        }
    }

    /// 到目前為止建過幾個箱庭。測試用：確認 `RoomView` 被重新建立時不會跟著重建。
    private(set) static var createdCount = 0

    let builder: FrameBuilder
    let runner: SimulationRunner

    /// `start` 是一開始在台上的角色與站的位置，依上台先後；第一個節拍上台、開始閒晃。
    /// `seed` 是閒晃的亂數種子，`now` 是現在的真實時間。
    init(room: RoomLayout, cast: [Member], start: [(id: CharacterID, position: TilePosition)], seed: UInt64, now: Double) {
        Self.createdCount += 1
        var simulation = Simulation(room: room, cast: cast.map { .init(id: $0.id, motions: $0.motions, wander: $0.wander) },
                                    seed: seed)
        for character in start { simulation.send(.enter(character.id, at: character.position)) }
        runner = SimulationRunner(simulation: simulation, now: now)
        builder = FrameBuilder(room: room, cast: cast.map { .init(id: $0.id, vector: $0.vector, motions: $0.motions) })
    }

    /// 主人點了畫面上的這一點：點到角色就重新計算閒置，並告訴模擬主人點了牠（`date` 是點的當下，記錄用）。
    /// 回傳點到哪一隻；沒點到是 nil。
    @discardableResult
    func tap(at point: CGPoint, now: Double, date: Date = .now) -> CharacterID? {
        guard let id = builder.character(at: point) else { return nil }
        builder.ownerTouched(now: now)
        runner.send(.ownerTapped(id, at: date))
        return id
    }
}
