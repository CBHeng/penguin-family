import SwiftData
import SwiftUI

/// App 的第一個畫面：先顯示載入畫面，初始化放到背景，完成後淡入主遊戲。
///
/// 作者 2026-11-16 決定：用首次載入換遊戲中的順暢，但初始化不能卡住啟動。
/// iOS 會強制關掉啟動太久的 App，所以第一個畫面要馬上出來，費時的工作在背景做（見架構的「技術取捨」）。
/// 背景做的事：載入一家的角色包、打開事件紀錄的資料庫並讀每隻最後一次被點的時間；另外讀閒晃、點一下的反應的預設資料
/// 與共用特效的形狀（都很小）。
/// 之後新增的初始化也放在 `load()`。
struct ContentView: View {
    /// 載入好、交給主遊戲的東西。
    private struct Loaded {
        /// 一家的每一隻（照名單，沒有角色包的那隻 `character` 是 nil）。
        let family: [FamilyMember]
        /// App 裡預設的閒晃與點一下的反應（讀不到是 nil）；角色包帶了自己的那隻用自己的。
        let wander: WanderConfig?
        let interactions: InteractionConfig?
        /// 共用特效的形狀（讀不到是空的）。
        let effects: EffectLibrary
        let events: EventLog
        /// 每隻最後一次被點的時間（A1 第 14 項，判斷離開一陣子後的第一次點）。
        let lastTaps: [CharacterID: Date]
    }

    private enum Phase {
        case loading
        case ready(Loaded)
    }

    @Environment(\.modelContext) private var modelContext
    @State private var phase = Phase.loading

    var body: some View {
        ZStack {
            switch phase {
            case .loading:
                LoadingView()
                    .transition(.opacity)
            case .ready(let loaded):
                GameView(family: loaded.family, wander: loaded.wander, interactions: loaded.interactions, effects: loaded.effects,
                         events: loaded.events, lastTaps: loaded.lastTaps)
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
        let wander = WanderConfig.bundled()
        let interactions = InteractionConfig.bundled()
        let effects = EffectLibrary.bundled()
        let members = await family
        // 每隻最後一次被點的時間：事件紀錄存的是 id 字串
        let taps = await events.lastTaps(of: members.map(\.id.rawValue))
        let lastTaps = Dictionary(uniqueKeysWithValues: taps.map { (CharacterID($0.key), $0.value) })
        let loaded = Loaded(family: members, wander: wander, interactions: interactions, effects: effects, events: events,
                            lastTaps: lastTaps)
        withAnimation(.easeOut(duration: 0.25)) {
            phase = .ready(loaded)
        }
    }
}

#Preview {
    ContentView()
        .modelContainer(try! EventLog.makeContainer(inMemory: true))
}
