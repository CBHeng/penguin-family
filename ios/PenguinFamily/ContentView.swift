import SwiftData
import SwiftUI
import os

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var character = CharacterPackLibrary.loadFirst()
    @State private var behavior = PenguinBehavior()
    /// 企鵝站在地板的哪一點（格）；A1 第 3、4 項加入走動後會變。
    @State private var penguinPosition = TilePosition(i: 4.5, j: 4.5)

    var body: some View {
        ZStack(alignment: .top) {
            // 箱庭外面的顏色
            Color(red: 0.23, green: 0.21, blue: 0.19)
                .ignoresSafeArea()
            RoomView(
                room: .indoor,
                character: character?.compositor,
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

#Preview {
    ContentView()
        .modelContainer(try! EventLog.makeContainer(inMemory: true))
}
