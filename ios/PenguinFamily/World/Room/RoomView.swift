import QuartzCore
import SwiftUI

/// 一個區域的等角箱庭：Metal 畫面加上手勢（ADR 0006）。
///
/// 這裡只把手勢與意圖交給 `RoomStage`，畫面由 `MetalRoomView` 的遊戲迴圈負責。
/// - 點一下企鵝：回報給 `Behavior`；點空地沒有反應。
/// - 拖曳空地捲動；從企鵝身上開始拖不捲動，留給之後的「拎起來」。
/// - 雙指捏合縮放；一段時間沒碰，鏡頭慢慢移回企鵝身邊（遊戲設計 2026-11-16）。
/// 畫面本身不會移動，所以手勢的座標就是畫面上的位置。
struct RoomView: View {
    let penguinPosition: TilePosition
    let intent: PenguinBehavior.Intent
    var onTap: () -> Void = {}
    var onMotionFinished: () -> Void = {}

    @State private var stage: RoomStage
    @Environment(\.displayScale) private var displayScale

    init(room: RoomLayout, character: CharacterFrames?, penguinPosition: TilePosition, intent: PenguinBehavior.Intent,
         onTap: @escaping () -> Void = {}, onMotionFinished: @escaping () -> Void = {}) {
        self.penguinPosition = penguinPosition
        self.intent = intent
        self.onTap = onTap
        self.onMotionFinished = onMotionFinished
        _stage = State(initialValue: RoomStage(room: room, character: character, penguinPosition: penguinPosition))
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
        .onChange(of: intent, initial: true) { _, intent in stage.setIntent(intent, now: CACurrentMediaTime()) }
        .onChange(of: penguinPosition) { _, position in stage.setPenguinPosition(position) }
        .accessibilityElement()
        .accessibilityLabel("箱庭")
        .accessibilityAction(named: "點企鵝") { tapPenguin() }
    }

    private func tapPenguin() {
        stage.ownerTouched(now: CACurrentMediaTime())
        onTap()
    }

    private var tapGesture: some Gesture {
        SpatialTapGesture()
            .onEnded { value in
                if stage.hitsPenguin(at: value.location) { tapPenguin() }
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
    RoomView(room: .indoor, character: nil, penguinPosition: TilePosition(i: 4.5, j: 4.5), intent: .idle)
        .ignoresSafeArea()
}
