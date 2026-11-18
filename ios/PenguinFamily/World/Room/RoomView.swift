import QuartzCore
import SwiftUI

/// 一個區域的等角箱庭：Metal 畫面加上手勢（ADR 0006）。
///
/// 這裡只把手勢、意圖與「誰在台上」交給 `RoomStage`，畫面由 `MetalRoomView` 的遊戲迴圈負責。
/// - 點一下企鵝：回報點到哪一隻（兩隻重疊時前面那隻優先）；點空地沒有反應。
/// - 拖曳空地捲動；從企鵝身上開始拖不捲動，留給之後的「拎起來」。
/// - 雙指捏合縮放；一段時間沒碰，鏡頭慢慢移回企鵝身邊（遊戲設計 2026-11-16）。
/// 畫面本身不會移動，所以手勢的座標就是畫面上的位置。
///
/// 舞台只建一次：第一次出現時才建，之後一直沿用（作者 2026-11-18 決定）。不在 `init` 裡建：
/// 上一層的 `body` 每次重算都會重新呼叫 `init`，`State(initialValue:)` 的參數會真的算出來再被丟掉；
/// 建一次舞台要畫整個房間（模擬器最佳化約 2.8 毫秒、Debug 約 107 毫秒），以前每點一下就在主執行緒白做兩次。
struct RoomView: View {
    /// 台上一隻企鵝要給畫面的資料：身分、站的位置、現在的意圖。
    struct Penguin: Equatable {
        let id: PenguinID
        let position: TilePosition
        let intent: PenguinBehavior.Intent
    }

    let room: RoomLayout
    /// 可能上台的每一隻與造型（後台名單），圖在載入時一次送進 GPU。只在建舞台時讀一次。
    let cast: [RoomStage.CastMember]
    /// 台上的企鵝；清單變了，就讓多出來的上台、不見的下台。
    let penguins: [Penguin]
    /// 主人點了哪一隻。
    var onTap: (PenguinID) -> Void = { _ in }
    /// 哪一隻的動作播完了。
    var onMotionFinished: (PenguinID) -> Void = { _ in }
    /// 哪一隻走到了哪一格。
    var onArrived: (RoomStage.Arrival) -> Void = { _ in }

    /// 第一次出現前是 nil。
    @State private var stage: RoomStage?
    @Environment(\.displayScale) private var displayScale

    /// 只記下參數，不建舞台（見上面的說明）。
    init(room: RoomLayout, cast: [RoomStage.CastMember], penguins: [Penguin],
         onTap: @escaping (PenguinID) -> Void = { _ in },
         onMotionFinished: @escaping (PenguinID) -> Void = { _ in },
         onArrived: @escaping (RoomStage.Arrival) -> Void = { _ in }) {
        self.room = room
        self.cast = cast
        self.penguins = penguins
        self.onTap = onTap
        self.onMotionFinished = onMotionFinished
        self.onArrived = onArrived
    }

    var body: some View {
        GeometryReader { proxy in
            if let stage {
                MetalRoomView(stage: stage, onMotionFinished: onMotionFinished, onArrived: onArrived)
                    .gesture(tapGesture(stage))
                    .simultaneousGesture(panGesture(stage))
                    .simultaneousGesture(pinchGesture(stage))
                    .onAppear { stage.resize(viewport: proxy.size, displayScale: displayScale) }
                    .onChange(of: proxy.size) { _, size in stage.resize(viewport: size, displayScale: displayScale) }
            }
        }
        .onAppear {
            if stage == nil { stage = Self.makeStage(room: room, cast: cast, penguins: penguins) }
        }
        .onChange(of: penguins) { _, penguins in
            if let stage { Self.sync(penguins, on: stage) }
        }
        .accessibilityElement()
        .accessibilityLabel("箱庭")
        .accessibilityAction(named: "點企鵝") {
            if let stage, let first = stage.onStage.first { tapPenguin(first, on: stage) }
        }
    }

    /// 建舞台，讓一開始在台上的上台。在量到畫面大小之前上台，第一次出現時鏡頭才會對準牠們。
    static func makeStage(room: RoomLayout, cast: [RoomStage.CastMember], penguins: [Penguin]) -> RoomStage {
        let stage = RoomStage(room: room, cast: cast)
        sync(penguins, on: stage)
        return stage
    }

    /// 讓舞台和清單一致：不在清單裡的下台、新的上台，再更新每一隻的位置與意圖。
    /// 正在走的企鵝位置由舞台決定，這裡給的位置不會蓋過去；走到後外面會改成終點，兩邊就一致了。
    static func sync(_ penguins: [Penguin], on stage: RoomStage) {
        let now = CACurrentMediaTime()
        let ids = Set(penguins.map(\.id))
        for id in stage.onStage where !ids.contains(id) { stage.remove(id) }
        for penguin in penguins {
            stage.add(penguin.id, at: penguin.position)  // 已經在台上就不做事
            stage.setPosition(penguin.position, for: penguin.id)
            stage.setIntent(penguin.intent, for: penguin.id, now: now)
        }
    }

    private func tapPenguin(_ id: PenguinID, on stage: RoomStage) {
        stage.ownerTouched(now: CACurrentMediaTime())
        onTap(id)
    }

    private func tapGesture(_ stage: RoomStage) -> some Gesture {
        SpatialTapGesture()
            .onEnded { value in
                PerfSignposts.measure("tap") {
                    if let id = stage.penguin(at: value.location) { tapPenguin(id, on: stage) }
                }
            }
    }

    private func panGesture(_ stage: RoomStage) -> some Gesture {
        DragGesture()
            .onChanged { value in
                stage.panChanged(translation: value.translation, startLocation: value.startLocation,
                                 now: CACurrentMediaTime())
            }
            .onEnded { _ in stage.panEnded(now: CACurrentMediaTime()) }
    }

    private func pinchGesture(_ stage: RoomStage) -> some Gesture {
        MagnifyGesture()
            .onChanged { value in
                stage.pinchChanged(magnification: value.magnification, anchor: value.startLocation,
                                   now: CACurrentMediaTime())
            }
            .onEnded { value in
                stage.pinchEnded(magnification: value.magnification, anchor: value.startLocation,
                                 now: CACurrentMediaTime())
            }
    }
}

#Preview("沒有角色包") {
    let ids = [PenguinID("placeholder-1"), PenguinID("placeholder-2")]
    RoomView(room: .indoor, cast: ids.map { .init(id: $0, frames: nil) }, penguins: [
        .init(id: ids[0], position: TilePosition(i: 4.5, j: 4.5), intent: .idle),
        .init(id: ids[1], position: TilePosition(i: 5.5, j: 3.5), intent: .idle),
    ])
    .ignoresSafeArea()
}
