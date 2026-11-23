import SwiftUI

/// 主遊戲：箱庭與一家。載入完成後才進來，角色包與閒晃的資料都已經讀好。
///
/// 只是外殼（ADR 0008）：把一家每一隻的身分、造型、動作與閒晃交給箱庭（缺角色包的換成替身，見 `StandIn`），
/// 決定誰一開始在台上、站在哪。狀態機、閒晃、移動都在模擬裡，這裡不持有。
/// 模擬交出「主人點了哪一隻」時，丟給事件紀錄在背景寫入（不等它存完）。
struct GameView: View {
    /// 箱庭外面的顏色；載入畫面也用同一個，切換時不閃。
    static let outsideColor = Color(red: 0.23, green: 0.21, blue: 0.19)

    /// 現在的箱庭。A1 只有屋內。
    static let room = RoomLayout.indoor

    /// 事件紀錄；預覽時可以是 nil。
    let events: EventLog?
    /// 一家的每一隻，依名單的順序。
    private let cast: [RoomScene.Member]
    private let hasCharacters: Bool
    /// 共用特效的形狀（ADR 0010）。
    private let effects: EffectLibrary

    /// `wander` 是 App 裡的預設閒晃；角色包帶了自己的 `wander.json` 的那隻用自己的（作者 2026-11-19 決定每隻各自獨立）。
    init(family: [FamilyMember], wander: WanderConfig?, effects: EffectLibrary = .empty, events: EventLog?) {
        self.events = events
        self.effects = effects
        cast = RoomScene.Member.cast(family, defaultWander: wander)
        hasCharacters = family.contains { $0.character != nil }
    }

    /// 一開始誰在台上：一家每一隻（A1 第 12 項）。沒有角色包的那隻，台上是替身。
    static func initialStage(_ family: [CharacterID]) -> [CharacterID] {
        family
    }

    /// 一開始在台上的每一隻站在哪：照上台先後，用箱庭的起點（幾隻都不會疊在一起，見 `RoomLayout.startTiles`）。
    static func startPositions(_ stage: [CharacterID], in room: RoomLayout) -> [(id: CharacterID, position: TilePosition)] {
        let tiles = room.startTiles(count: stage.count)
        return stage.enumerated().compactMap { index, id in
            tiles.isEmpty ? nil : (id, tiles[min(index, tiles.count - 1)].center)
        }
    }

    var body: some View {
        ZStack(alignment: .top) {
            Self.outsideColor
                .ignoresSafeArea()
            RoomView(room: Self.room, cast: cast,
                     start: Self.startPositions(Self.initialStage(cast.map(\.id)), in: Self.room),
                     effects: effects, onOutputs: record)
            .ignoresSafeArea()
            if !hasCharacters {
                Text("沒有角色包")
                    .font(.caption)
                    .foregroundStyle(.white)
                    .padding(6)
                    .background(.black.opacity(0.4), in: Capsule())
            }
        }
        // 打開 App 時不特別迎接：牠們一上台就做自己的事（遊戲設計的「一天的節奏」）
    }

    /// 主人點了哪一隻就記下，不論角色當下有沒有回應；時間是點的當下，背景寫入的先後不影響順序。
    private func record(_ outputs: [Simulation.Output]) {
        guard let events else { return }
        for case .ownerTapped(let id, let date) in outputs {
            Task { await events.record(.ownerTapped, characterID: id.rawValue, at: date) }
        }
    }
}

#Preview("沒有角色包") {
    GameView(family: CharacterPackLibrary.loadFamily(in: nil), wander: WanderConfig.bundled(), effects: .bundled(), events: nil)
}
