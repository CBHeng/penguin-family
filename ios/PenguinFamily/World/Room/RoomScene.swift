import CoreGraphics
import Foundation

/// 一個箱庭在 App 裡的東西（ADR 0008）：模擬與它的驅動、畫面準備。`RoomView` 第一次出現時建一次，之後一直沿用。
///
/// 手勢與遊戲迴圈都透過它：拖曳、捏合交給畫面準備（只動鏡頭）；點到角色時把「主人點了這一隻」送進模擬，
/// 一起送離上一次點牠幾秒（模擬不讀時鐘，ADR 0008；打開 App 時從事件紀錄讀每隻最後一次被點的時間，之後這裡記著）。
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
        /// 點一下的反應；nil 時被點只會哈囉。
        var interactions: InteractionConfig? = nil

        /// 一家每一隻上台用的東西：缺角色包的換成替身（`StandIn`）；閒晃與點一下的反應用角色包自己的，
        /// 沒帶時用 `defaultWander`、`defaultInteractions`（作者 2026-11-19 決定每隻各自獨立）。
        static func cast(_ family: [FamilyMember], defaultWander: WanderConfig?,
                         defaultInteractions: InteractionConfig? = nil) -> [Member] {
            zip(family, StandIn.resolve(family)).map { member, look in
                Member(id: member.id, vector: look.vector, motions: look.motions,
                       wander: member.character?.wander ?? defaultWander,
                       interactions: member.character?.interactions ?? defaultInteractions)
            }
        }
    }

    /// 到目前為止建過幾個箱庭。測試用：確認 `RoomView` 被重新建立時不會跟著重建。
    private(set) static var createdCount = 0

    let builder: FrameBuilder
    let runner: SimulationRunner
    /// 每隻最後一次被主人點的時間（真實時間）；從來沒被點過的不在裡面。
    private(set) var lastTaps: [CharacterID: Date]

    /// `start` 是一開始在台上的角色與站的位置，依上台先後；第一個節拍上台、開始閒晃。
    /// `seed` 是閒晃的亂數種子，`now` 是現在的真實時間。
    /// `effects` 是共用特效的形狀（ADR 0010）。`lastTaps` 是打開 App 時從事件紀錄讀到的、每隻最後一次被點的時間。
    init(room: RoomLayout, cast: [Member], start: [(id: CharacterID, position: TilePosition)], seed: UInt64, now: Double,
         effects: EffectLibrary = .empty, lastTaps: [CharacterID: Date] = [:]) {
        Self.createdCount += 1
        self.lastTaps = lastTaps
        var simulation = Simulation(room: room, cast: cast.map {
            .init(id: $0.id, motions: $0.motions, wander: $0.wander, interactions: $0.interactions)
        }, seed: seed)
        for character in start { simulation.send(.enter(character.id, at: character.position)) }
        runner = SimulationRunner(simulation: simulation, now: now)
        builder = FrameBuilder(room: room, cast: cast.map { .init(id: $0.id, vector: $0.vector, motions: $0.motions) },
                               effects: effects)
    }

    /// 主人點了畫面上的這一點：點到角色就重新計算閒置，並告訴模擬主人點了牠（`date` 是點的當下，記錄用）。
    /// 回傳點到哪一隻；沒點到是 nil。
    @discardableResult
    func tap(at point: CGPoint, now: Double, date: Date = .now) -> CharacterID? {
        guard let id = builder.character(at: point) else { return nil }
        tap(id, now: now, date: date)
        return id
    }

    /// 主人點了這一隻（點到畫面上的牠，或無障礙的動作）：重新計算閒置，告訴模擬離上一次點牠幾秒，再記下這次。
    func tap(_ id: CharacterID, now: Double, date: Date = .now) {
        builder.ownerTouched(now: now)
        let sinceLastTap = lastTaps[id].map { date.timeIntervalSince($0) } ?? .infinity
        lastTaps[id] = date
        runner.send(.ownerTapped(id, at: date, sinceLastTap: sinceLastTap))
    }
}
