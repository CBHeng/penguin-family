import SwiftUI

/// 主遊戲：箱庭與一家企鵝。載入完成後才進來，角色與預先算好的格子都已經準備好。
///
/// 「接線員」：一家的每一隻各有自己的身分、狀態機與位置；誰在台上由 `onStage` 決定（舞台用加入、移除，不用數量）。
/// 主人點了哪一隻，就交給那一隻的狀態機，並把這件事丟給事件紀錄在背景寫入（不等它存完）。
struct GameView: View {
    /// 箱庭外面的顏色；載入畫面也用同一個，切換時不閃。
    static let outsideColor = Color(red: 0.23, green: 0.21, blue: 0.19)

    /// 每隻企鵝一開始站的位置（格）：兩隻並排，第二隻在第一隻的畫面右邊。加入走動（A1 第 6、7 項）後會變。
    static let startPositions = [TilePosition(i: 4.5, j: 4.5), TilePosition(i: 5.5, j: 3.5)]

    /// 一家的一隻：身分、造型（nil 用灰色剪影）、狀態機、位置。不在台上時狀態機與位置照樣保留。
    private struct Member {
        let id: PenguinID
        let character: LoadedCharacter?
        var behavior = PenguinBehavior()
        var position: TilePosition
    }

    /// 事件紀錄；預覽時可以是 nil。
    let events: EventLog?
    @State private var members: [Member]
    /// 台上有誰，依上台先後。
    @State private var onStage: [PenguinID]

    init(family: [LoadedCharacter?], events: EventLog?) {
        self.events = events
        let members = family.enumerated().map { index, character in
            Member(id: PenguinID(character: character, index: index), character: character,
                   position: Self.startPositions[index % Self.startPositions.count])
        }
        _members = State(initialValue: members)
        _onStage = State(initialValue: Self.initialStage(members.map(\.id)))
    }

    /// 一開始誰在台上。作者 2026-11-17 決定：寫移動（A1 第 5～7 項）的期間只有第一隻，
    /// 第二隻先留在後台；第一隻走穩後（第 8 項）第二隻再上台。
    static func initialStage(_ family: [PenguinID]) -> [PenguinID] {
        Array(family.prefix(1))
    }

    /// 試走的固定路線（作者 2026-11-18 決定：閒晃做好之前，開場自動走一段）。第 7 項閒晃做好後拿掉。
    /// 從 (4, 4) 出發，四個方向都會走到，也會繞過沙發（i = 7、j = 6～8）：
    /// 1. 慢走到沙發右側：往右前、再往左前。
    /// 2. 小跑從沙發前面繞到另一側：往左前、左後、右後（往前或往後繞一樣短，照固定順序挑前面）。
    /// 3. 慢走回起點：往左後、再往右後。
    static let demoRoute: [(tile: Tile, pace: PenguinBehavior.Pace)] = [
        (Tile(i: 8, j: 7), .walk),
        (Tile(i: 5, j: 7), .trot),
        (Tile(i: 4, j: 4), .walk),
    ]
    /// 開場、每段之間停多久（秒）。「走幾步就停一下」（遊戲設計），實機上調。
    static let demoPause: Duration = .seconds(1.5)

    /// 試走走到第幾段了。
    @State private var demoLeg = 0

    var body: some View {
        ZStack(alignment: .top) {
            Self.outsideColor
                .ignoresSafeArea()
            RoomView(
                room: .indoor,
                cast: members.map { .init(id: $0.id, frames: $0.character?.frames) },
                penguins: onStage.compactMap { id in
                    members.first { $0.id == id }.map { .init(id: id, position: $0.position, intent: $0.behavior.intent) }
                },
                onTap: ownerTapped,
                onMotionFinished: { id in update(id) { $0.behavior.handle(.motionFinished) } },
                onArrived: arrived)
            .ignoresSafeArea()
            if members.allSatisfy({ $0.character == nil }) {
                Text("沒有角色包")
                    .font(.caption)
                    .foregroundStyle(.white)
                    .padding(6)
                    .background(.black.opacity(0.4), in: Capsule())
            }
        }
        .task { await walkNextDemoLeg() }
    }

    /// 走到了：記下新位置，讓狀態機回到待機；試走還有下一段就停一下再走。
    private func arrived(_ arrival: RoomStage.Arrival) {
        update(arrival.id) {
            $0.position = arrival.tile.center
            $0.behavior.handle(.arrived)
        }
        Task { await walkNextDemoLeg() }
    }

    /// 停一下，再讓台上第一隻走試走路線的下一段。正在做別的事（例如哈囉）就等一下再試。
    private func walkNextDemoLeg() async {
        while demoLeg < Self.demoRoute.count {
            try? await Task.sleep(for: Self.demoPause)
            guard !Task.isCancelled, demoLeg < Self.demoRoute.count, let id = onStage.first,
                  let index = members.firstIndex(where: { $0.id == id }) else { return }
            if case .walk = members[index].behavior.intent { return }   // 已經在走（另一個等待先開始了）
            let leg = Self.demoRoute[demoLeg]
            if members[index].behavior.handle(.walkRequested(to: leg.tile, pace: leg.pace)) {
                demoLeg += 1
                return
            }
        }
    }

    private func update(_ id: PenguinID, _ change: (inout Member) -> Void) {
        guard let index = members.firstIndex(where: { $0.id == id }) else { return }
        change(&members[index])
    }

    private func ownerTapped(_ id: PenguinID) {
        // 先讓那一隻反應，再記下這件事；時間在點的當下取，背景寫入的先後不影響順序
        update(id) { $0.behavior.handle(.ownerTapped) }
        // 主人點了就記下，不論企鵝當下有沒有回應
        if let events {
            let now = Date.now
            Task { await events.record(.ownerTapped, penguinID: id.rawValue, at: now) }
        }
    }
}

#Preview("沒有角色包") {
    GameView(family: [nil, nil], events: nil)
}
