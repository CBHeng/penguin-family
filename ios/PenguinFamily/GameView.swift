import SwiftData
import SwiftUI
import os

/// 主遊戲：箱庭與企鵝。載入完成後才進來，角色與預先算好的格子都已經準備好。
///
/// 「接線員」：持有狀態機與企鵝位置；主人點擊時先記進事件紀錄，再交給狀態機。
struct GameView: View {
    /// 箱庭外面的顏色；載入畫面也用同一個，切換時不閃。
    static let outsideColor = Color(red: 0.23, green: 0.21, blue: 0.19)

    /// 載入好的角色；nil 表示沒有角色包（顯示灰色剪影）。
    let character: LoadedCharacter?
    @Environment(\.modelContext) private var modelContext
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
        // 主人點了就記下，不論企鵝當下有沒有回應
        do {
            try EventLog(context: modelContext).record(.ownerTapped, penguinID: character?.id)
        } catch {
            Logger(subsystem: "PenguinFamily", category: "Memory")
                .error("事件紀錄寫入失敗：\(String(describing: error), privacy: .private)")
        }
        behavior.handle(.ownerTapped)
    }
}

#Preview("沒有角色包") {
    GameView(character: nil)
        .modelContainer(try! EventLog.makeContainer(inMemory: true))
}
