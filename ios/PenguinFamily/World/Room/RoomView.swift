import QuartzCore
import SwiftUI

/// 一個區域的等角箱庭：Metal 畫面加上手勢（ADR 0006）。
///
/// 這裡只把手勢與意圖交給 `RoomStage`，畫面由 `MetalRoomView` 的遊戲迴圈負責。
/// - 點一下企鵝：回報點到哪一隻（兩隻重疊時前面那隻優先）；點空地沒有反應。
/// - 拖曳空地捲動；從企鵝身上開始拖不捲動，留給之後的「拎起來」。
/// - 雙指捏合縮放；一段時間沒碰，鏡頭慢慢移回企鵝身邊（遊戲設計 2026-11-16）。
/// 畫面本身不會移動，所以手勢的座標就是畫面上的位置。
struct RoomView: View {
    /// 一隻企鵝要給畫面的資料：造型（nil 用灰色剪影）、站的位置、現在的意圖。
    struct Penguin {
        let frames: CharacterFrames?
        let position: TilePosition
        let intent: PenguinBehavior.Intent
    }

    let penguins: [Penguin]
    /// 主人點了哪一隻（企鵝編號）。
    var onTap: (Int) -> Void = { _ in }
    /// 哪一隻的動作播完了（企鵝編號）。
    var onMotionFinished: (Int) -> Void = { _ in }

    @State private var stage: RoomStage
    @Environment(\.displayScale) private var displayScale

    init(room: RoomLayout, penguins: [Penguin],
         onTap: @escaping (Int) -> Void = { _ in }, onMotionFinished: @escaping (Int) -> Void = { _ in }) {
        self.penguins = penguins
        self.onTap = onTap
        self.onMotionFinished = onMotionFinished
        _stage = State(initialValue: RoomStage(
            room: room, penguins: penguins.map { RoomStage.PenguinSetup(frames: $0.frames, position: $0.position) }))
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
        .onChange(of: penguins.map(\.intent), initial: true) { _, intents in
            let now = CACurrentMediaTime()
            for (index, intent) in intents.enumerated() { stage.setIntent(intent, for: index, now: now) }
        }
        .onChange(of: penguins.map(\.position)) { _, positions in
            for (index, position) in positions.enumerated() { stage.setPosition(position, for: index) }
        }
        .accessibilityElement()
        .accessibilityLabel("箱庭")
        .accessibilityAction(named: "點企鵝") { tapPenguin(0) }
    }

    private func tapPenguin(_ index: Int) {
        stage.ownerTouched(now: CACurrentMediaTime())
        onTap(index)
    }

    private var tapGesture: some Gesture {
        SpatialTapGesture()
            .onEnded { value in
                PerfSignposts.measure("tap") {
                    if let index = stage.penguin(at: value.location) { tapPenguin(index) }
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
    RoomView(room: .indoor, penguins: [
        .init(frames: nil, position: TilePosition(i: 4.5, j: 4.5), intent: .idle),
        .init(frames: nil, position: TilePosition(i: 5.5, j: 3.5), intent: .idle),
    ])
    .ignoresSafeArea()
}
