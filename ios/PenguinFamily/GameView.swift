import QuartzCore
import SwiftUI

/// 主遊戲：箱庭與一家企鵝。載入完成後才進來，角色包與閒晃的資料都已經讀好。
///
/// 「接線員」：一家的每一隻各有自己的身分、狀態機、閒晃與位置；誰在台上由 `onStage` 決定（舞台用加入、移除，不用數量）。
/// 主人點了哪一隻，就交給那一隻的狀態機，並把這件事丟給事件紀錄在背景寫入（不等它存完）。
/// 台上的企鵝一回到待機，就問牠的閒晃接下來做什麼（走去某一格、站著幾秒）。
struct GameView: View {
    /// 箱庭外面的顏色；載入畫面也用同一個，切換時不閃。
    static let outsideColor = Color(red: 0.23, green: 0.21, blue: 0.19)

    /// 現在的箱庭。A1 只有屋內。
    static let room = RoomLayout.indoor

    /// 每隻企鵝一開始站的位置（格）：兩隻並排，第二隻在第一隻的畫面右邊。
    static let startPositions = [TilePosition(i: 4.5, j: 4.5), TilePosition(i: 5.5, j: 3.5)]

    /// 一家的一隻：身分、造型（nil 用灰色剪影）、狀態機、閒晃、位置。不在台上時這些照樣保留。
    private struct Member {
        let id: PenguinID
        let character: LoadedCharacter?
        var behavior = PenguinBehavior()
        /// 沒人碰時接下來做什麼；閒晃的資料讀不到時是 nil，牠就只站著。
        var wander: WanderRoutine?
        var position: TilePosition
    }

    /// 事件紀錄；預覽時可以是 nil。
    let events: EventLog?
    @State private var members: [Member]
    /// 台上有誰，依上台先後。
    @State private var onStage: [PenguinID]

    init(family: [LoadedCharacter?], wander: WanderConfig?, events: EventLog?) {
        self.events = events
        let members = family.enumerated().map { index, character in
            Member(id: PenguinID(character: character, index: index), character: character,
                   wander: wander.map { WanderRoutine(config: $0, room: Self.room) },
                   position: Self.startPositions[index % Self.startPositions.count])
        }
        _members = State(initialValue: members)
        _onStage = State(initialValue: Self.initialStage(members.map(\.id)))
    }

    /// 一開始誰在台上。作者 2026-11-17 決定：寫移動（A1 第 5～11 項）的期間只有第一隻，
    /// 第二隻先留在後台；第一隻走穩後（第 12 項）第二隻再上台。
    static func initialStage(_ family: [PenguinID]) -> [PenguinID] {
        Array(family.prefix(1))
    }

    var body: some View {
        ZStack(alignment: .top) {
            Self.outsideColor
                .ignoresSafeArea()
            RoomView(
                room: Self.room,
                cast: members.map { .init(id: $0.id, vector: $0.character?.vector) },
                penguins: onStage.compactMap { id in
                    members.first { $0.id == id }.map {
                        .init(id: id, position: $0.position, intent: $0.behavior.intent, serial: $0.behavior.serial)
                    }
                },
                onTap: ownerTapped,
                onMotionFinished: motionFinished,
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
        // 打開 App 時不特別迎接：牠們直接做自己的事（遊戲設計的「一天的節奏」）
        .task { for id in onStage { wander(id) } }
    }

    /// 動作播完或站滿：狀態機回到待機，接著閒晃。
    private func motionFinished(_ id: PenguinID) {
        update(id) { $0.behavior.handle(.motionFinished) }
        wander(id)
    }

    /// 走到了：記下新位置，狀態機回到待機，接著閒晃。
    private func arrived(_ arrival: RoomStage.Arrival) {
        update(arrival.id) {
            $0.position = arrival.tile.center
            $0.behavior.handle(.arrived)
        }
        wander(arrival.id)
    }

    /// 台上的這一隻在待機的話，問牠的閒晃下一步做什麼，交給狀態機。
    private func wander(_ id: PenguinID) {
        guard onStage.contains(id) else { return }
        update(id) { member in
            guard member.behavior.intent == .idle, var routine = member.wander else { return }
            var rng = SystemRandomNumberGenerator()
            let step = routine.next(from: Tile(containing: member.position), now: CACurrentMediaTime(), using: &rng)
            member.wander = routine
            if let step { member.behavior.handle(step.request) }
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
    GameView(family: [nil, nil], wander: WanderConfig.bundled(), events: nil)
}
