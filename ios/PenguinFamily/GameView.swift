import SwiftUI

/// 主遊戲：箱庭與企鵝。載入完成後才進來，角色與預先算好的格子都已經準備好。
///
/// 「接線員」：持有狀態機與企鵝位置；主人點擊時交給狀態機，並把這件事丟給事件紀錄在背景寫入（不等它存完）。
struct GameView: View {
    /// 箱庭外面的顏色；載入畫面也用同一個，切換時不閃。
    static let outsideColor = Color(red: 0.23, green: 0.21, blue: 0.19)

    /// 載入好的角色；nil 表示沒有角色包（顯示灰色剪影）。
    let character: LoadedCharacter?
    /// 事件紀錄；預覽時可以是 nil。
    let events: EventLog?
    @State private var behavior = PenguinBehavior()
    /// 企鵝站在地板的哪一點（格）；A1 第 3、4 項加入走動後會變。
    @State private var penguinPosition = TilePosition(i: 4.5, j: 4.5)

    var body: some View {
        ZStack(alignment: .top) {
            Self.outsideColor
                .ignoresSafeArea()
            RoomView(
                room: .indoor,
                character: character?.frames,
                penguinPosition: penguinPosition,
                intent: behavior.intent,
                onTap: ownerTapped,
                onMotionFinished: { behavior.handle(.motionFinished) })
            .ignoresSafeArea()
            if character == nil {
                Text("沒有角色包")
                    .font(.caption)
                    .foregroundStyle(.white)
                    .padding(6)
                    .background(.black.opacity(0.4), in: Capsule())
            }
        }
    }

    private func ownerTapped() {
        // 先讓企鵝反應，再記下這件事；時間在點的當下取，背景寫入的先後不影響順序
        behavior.handle(.ownerTapped)
        // 主人點了就記下，不論企鵝當下有沒有回應
        if let events {
            let penguinID = character?.id
            let now = Date.now
            Task { await events.record(.ownerTapped, penguinID: penguinID, at: now) }
        }
    }
}

#Preview("沒有角色包") {
    GameView(character: nil, events: nil)
}
