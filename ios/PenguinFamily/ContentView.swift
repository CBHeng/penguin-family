import SwiftData
import SwiftUI

/// App 的第一個畫面：先顯示載入畫面，初始化放到背景，完成後淡入主遊戲。
///
/// 作者 2026-11-16 決定：用首次載入換遊戲中的順暢，但初始化不能卡住啟動。
/// iOS 會強制關掉啟動太久的 App，所以第一個畫面要馬上出來，費時的工作在背景做（見架構的「技術取捨」）。
/// 背景做的事：載入一家的角色包、打開事件紀錄的資料庫。之後新增的初始化也放在 `load()`。
struct ContentView: View {
    private enum Phase {
        case loading
        /// 載入完成；一家的每一隻，nil 表示那一隻沒有角色包。
        case ready([LoadedCharacter?], EventLog)
    }

    @Environment(\.modelContext) private var modelContext
    @State private var phase = Phase.loading

    var body: some View {
        ZStack {
            switch phase {
            case .loading:
                LoadingView()
                    .transition(.opacity)
            case .ready(let family, let events):
                GameView(family: family, events: events)
                    .transition(.opacity)
            }
        }
        .task { await load() }
    }

    private func load() async {
        // 兩件事同時在背景做
        async let family = CharacterPackLibrary.loadFamilyInBackground()
        let events = await EventLog.open(modelContext.container)
        await events.warmUp()
        let loaded = await family
        withAnimation(.easeOut(duration: 0.25)) {
            phase = .ready(loaded, events)
        }
    }
}

#Preview {
    ContentView()
        .modelContainer(try! EventLog.makeContainer(inMemory: true))
}
