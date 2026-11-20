import SwiftUI

/// 主遊戲：箱庭與一家企鵝。載入完成後才進來，角色包與閒晃的資料都已經讀好。
///
/// 只是外殼（ADR 0008）：把一家每一隻的身分、造型、動作細節與閒晃交給箱庭，決定誰一開始在台上。
/// 狀態機、閒晃、走路都在模擬裡，這裡不持有。模擬交出「主人點了哪一隻」時，丟給事件紀錄在背景寫入（不等它存完）。
struct GameView: View {
    /// 箱庭外面的顏色；載入畫面也用同一個，切換時不閃。
    static let outsideColor = Color(red: 0.23, green: 0.21, blue: 0.19)

    /// 現在的箱庭。A1 只有屋內。
    static let room = RoomLayout.indoor

    /// 每隻企鵝一開始站的位置（格）：兩隻並排，第二隻在第一隻的畫面右邊。
    static let startPositions = [TilePosition(i: 4.5, j: 4.5), TilePosition(i: 5.5, j: 3.5)]

    /// 事件紀錄；預覽時可以是 nil。
    let events: EventLog?
    /// 一家的每一隻，依一家的順序。
    private let cast: [RoomScene.Member]
    private let hasCharacters: Bool

    /// `wander` 是 App 裡的預設閒晃；角色包帶了自己的 `wander.json` 的那隻用自己的（作者 2026-11-19 決定兩隻各自獨立）。
    init(family: [LoadedCharacter?], wander: WanderConfig?, events: EventLog?) {
        self.events = events
        cast = family.enumerated().map { index, character in
            RoomScene.Member(id: PenguinID(character: character, index: index), vector: character?.vector,
                             motions: character?.motions ?? .standard, wander: character?.wander ?? wander)
        }
        hasCharacters = family.contains { $0 != nil }
    }

    /// 一開始誰在台上：一家每一隻（A1 第 12 項）。沒有角色包的那隻，台上是借另一隻形狀塗灰的替身。
    static func initialStage(_ family: [PenguinID]) -> [PenguinID] {
        family
    }

    var body: some View {
        ZStack(alignment: .top) {
            Self.outsideColor
                .ignoresSafeArea()
            RoomView(room: Self.room, cast: cast,
                     start: Self.initialStage(cast.map(\.id)).enumerated().map { index, id in
                         (id, Self.startPositions[index % Self.startPositions.count])
                     },
                     onOutputs: record)
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

    /// 主人點了哪一隻就記下，不論企鵝當下有沒有回應；時間是點的當下，背景寫入的先後不影響順序。
    private func record(_ outputs: [Simulation.Output]) {
        guard let events else { return }
        for case .ownerTapped(let id, let date) in outputs {
            Task { await events.record(.ownerTapped, penguinID: id.rawValue, at: date) }
        }
    }
}

#Preview("沒有角色包") {
    GameView(family: [nil, nil], wander: WanderConfig.bundled(), events: nil)
}
