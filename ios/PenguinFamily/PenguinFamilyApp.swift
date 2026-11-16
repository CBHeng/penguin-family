import SwiftData
import SwiftUI
import os

@main
struct PenguinFamilyApp: App {
    let container: ModelContainer

    init() {
        do {
            container = try EventLog.makeContainer()
        } catch {
            // 資料庫打不開時仍讓企鵝能用，只是這次的事件不會留下來
            Logger(subsystem: "PenguinFamily", category: "Memory")
                .error("事件紀錄無法開啟，改用暫存：\(String(describing: error), privacy: .private)")
            container = try! EventLog.makeContainer(inMemory: true)
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(container)
    }
}
