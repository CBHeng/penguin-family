import SwiftData
import SwiftUI
import os

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var character = CharacterPackLibrary.loadFirst()
    @State private var behavior = PenguinBehavior()

    var body: some View {
        ZStack {
            // 草地色，和私有素材 repo 的預覽相同
            Color(red: 196 / 255, green: 224 / 255, blue: 170 / 255)
                .ignoresSafeArea()
            PenguinView(
                character: character?.compositor,
                intent: behavior.intent,
                onTap: ownerTapped,
                onMotionFinished: { behavior.handle(.motionFinished) })
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
