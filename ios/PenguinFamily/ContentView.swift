import SwiftData
import SwiftUI

/// App 的第一個畫面：先顯示載入畫面，初始化放到背景，完成後淡入主遊戲。
///
/// 作者 2026-11-16 決定：用首次載入換遊戲中的順暢，但初始化不能卡住啟動。
/// iOS 會強制關掉啟動太久的 App，所以第一個畫面要馬上出來，費時的工作在背景做（見架構的「技術取捨」）。
/// 背景做的事：載入角色包、預先算好每一格。之後新增的初始化也放在 `load()`。
struct ContentView: View {
    private enum Phase {
        case loading
        /// 載入完成；角色是 nil 表示沒有角色包。
        case ready(LoadedCharacter?)
    }

    @State private var phase = Phase.loading

    var body: some View {
        ZStack {
            switch phase {
            case .loading:
                LoadingView()
                    .transition(.opacity)
            case .ready(let character):
                GameView(character: character)
                    .transition(.opacity)
            }
        }
        .task { await load() }
    }

    private func load() async {
        let character = await CharacterPackLibrary.loadFirstInBackground()
        withAnimation(.easeOut(duration: 0.25)) {
            phase = .ready(character)
        }
    }
}

#Preview {
    ContentView()
        .modelContainer(try! EventLog.makeContainer(inMemory: true))
}
