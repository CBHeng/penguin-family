import SwiftUI

/// 主遊戲：箱庭與一家企鵝。載入完成後才進來，角色與預先算好的格子都已經準備好。
///
/// 「接線員」：每隻企鵝各有自己的狀態機與位置；主人點了哪一隻，就交給那一隻的狀態機，
/// 並把這件事丟給事件紀錄在背景寫入（不等它存完）。
struct GameView: View {
    /// 箱庭外面的顏色；載入畫面也用同一個，切換時不閃。
    static let outsideColor = Color(red: 0.23, green: 0.21, blue: 0.19)

    /// 每隻企鵝一開始站的位置（格）：兩隻並排，第二隻在第一隻的畫面右邊。A1 第 4 項加入走動後會變。
    static let startPositions = [TilePosition(i: 4.5, j: 4.5), TilePosition(i: 5.5, j: 3.5)]

    /// 一家的每一隻，依角色包順序；nil 表示沒有角色包（顯示灰色剪影）。
    let family: [LoadedCharacter?]
    /// 事件紀錄；預覽時可以是 nil。
    let events: EventLog?
    @State private var behaviors: [PenguinBehavior]
    @State private var positions: [TilePosition]

    init(family: [LoadedCharacter?], events: EventLog?) {
        self.family = family
        self.events = events
        _behaviors = State(initialValue: family.map { _ in PenguinBehavior() })
        _positions = State(initialValue: family.indices.map { Self.startPositions[$0 % Self.startPositions.count] })
    }

    /// 事件紀錄裡怎麼稱呼這一隻：有角色包用角色包 id；灰色剪影用 `placeholder-<第幾隻>`，兩隻仍分得出來。
    static func penguinID(of character: LoadedCharacter?, at index: Int) -> String {
        character?.id ?? "placeholder-\(index + 1)"
    }

    var body: some View {
        ZStack(alignment: .top) {
            Self.outsideColor
                .ignoresSafeArea()
            RoomView(
                room: .indoor,
                penguins: family.indices.map {
                    .init(frames: family[$0]?.frames, position: positions[$0], intent: behaviors[$0].intent)
                },
                onTap: ownerTapped,
                onMotionFinished: { behaviors[$0].handle(.motionFinished) })
            .ignoresSafeArea()
            if family.allSatisfy({ $0 == nil }) {
                Text("沒有角色包")
                    .font(.caption)
                    .foregroundStyle(.white)
                    .padding(6)
                    .background(.black.opacity(0.4), in: Capsule())
            }
        }
    }

    private func ownerTapped(_ index: Int) {
        // 先讓那一隻反應，再記下這件事；時間在點的當下取，背景寫入的先後不影響順序
        behaviors[index].handle(.ownerTapped)
        // 主人點了就記下，不論企鵝當下有沒有回應
        if let events {
            let penguinID = Self.penguinID(of: family[index], at: index)
            let now = Date.now
            Task { await events.record(.ownerTapped, penguinID: penguinID, at: now) }
        }
    }
}

#Preview("沒有角色包") {
    GameView(family: [nil, nil], events: nil)
}
