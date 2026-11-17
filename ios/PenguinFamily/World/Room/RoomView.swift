import QuartzCore
import SwiftUI

/// 一個區域的等角箱庭：Metal 畫面加上手勢（ADR 0006）。
///
/// 這裡只把手勢、意圖與「誰在台上」交給 `RoomStage`，畫面由 `MetalRoomView` 的遊戲迴圈負責。
/// - 點一下企鵝：回報點到哪一隻（兩隻重疊時前面那隻優先）；點空地沒有反應。
/// - 拖曳空地捲動；從企鵝身上開始拖不捲動，留給之後的「拎起來」。
/// - 雙指捏合縮放；一段時間沒碰，鏡頭慢慢移回企鵝身邊（遊戲設計 2026-11-16）。
/// 畫面本身不會移動，所以手勢的座標就是畫面上的位置。
struct RoomView: View {
    /// 台上一隻企鵝要給畫面的資料：身分、站的位置、現在的意圖。
    struct Penguin: Equatable {
        let id: PenguinID
        let position: TilePosition
        let intent: PenguinBehavior.Intent
    }

    /// 台上的企鵝；清單變了，就讓多出來的上台、不見的下台。
    let penguins: [Penguin]
    /// 主人點了哪一隻。
    var onTap: (PenguinID) -> Void = { _ in }
    /// 哪一隻的動作播完了。
    var onMotionFinished: (PenguinID) -> Void = { _ in }

    @State private var stage: RoomStage
    @Environment(\.displayScale) private var displayScale

    /// `cast` 是可能上台的每一隻與造型（後台名單），圖在載入時一次送進 GPU；`penguins` 是一開始在台上的。
    init(room: RoomLayout, cast: [RoomStage.CastMember], penguins: [Penguin],
         onTap: @escaping (PenguinID) -> Void = { _ in },
         onMotionFinished: @escaping (PenguinID) -> Void = { _ in }) {
        self.penguins = penguins
        self.onTap = onTap
        self.onMotionFinished = onMotionFinished
        let stage = RoomStage(room: room, cast: cast)
        // 量到畫面大小之前就先上台，第一次出現時鏡頭才會對準牠們
        for penguin in penguins { stage.add(penguin.id, at: penguin.position) }
        _stage = State(initialValue: stage)
    }

    var body: some View {
        GeometryReader { proxy in
            MetalRoomView(stage: stage, onMotionFinished: onMotionFinished)
                .gesture(tapGesture)
                .simultaneousGesture(panGesture)
                .simultaneousGesture(pinchGesture)
                .onAppear { stage.resize(viewport: proxy.size, displayScale: displayScale) }
                .onChange(of: proxy.size) { _, size in stage.resize(viewport: size, displayScale: displayScale) }
        }
        .onChange(of: penguins, initial: true) { _, penguins in sync(penguins) }
        .accessibilityElement()
        .accessibilityLabel("箱庭")
        .accessibilityAction(named: "點企鵝") {
            if let first = stage.onStage.first { tapPenguin(first) }
        }
    }

    /// 讓舞台和清單一致：不在清單裡的下台、新的上台，再更新每一隻的位置與意圖。
    private func sync(_ penguins: [Penguin]) {
        let now = CACurrentMediaTime()
        let ids = Set(penguins.map(\.id))
        for id in stage.onStage where !ids.contains(id) { stage.remove(id) }
        for penguin in penguins {
            stage.add(penguin.id, at: penguin.position)  // 已經在台上就不做事
            stage.setPosition(penguin.position, for: penguin.id)
            stage.setIntent(penguin.intent, for: penguin.id, now: now)
        }
    }

    private func tapPenguin(_ id: PenguinID) {
        stage.ownerTouched(now: CACurrentMediaTime())
        onTap(id)
    }

    private var tapGesture: some Gesture {
        SpatialTapGesture()
            .onEnded { value in
                PerfSignposts.measure("tap") {
                    if let id = stage.penguin(at: value.location) { tapPenguin(id) }
                }
            }
    }

    private var panGesture: some Gesture {
        DragGesture()
            .onChanged { value in
                stage.panChanged(translation: value.translation, startLocation: value.startLocation,
                                 now: CACurrentMediaTime())
            }
            .onEnded { _ in stage.panEnded(now: CACurrentMediaTime()) }
    }

    private var pinchGesture: some Gesture {
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
