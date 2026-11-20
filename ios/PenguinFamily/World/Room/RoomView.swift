import QuartzCore
import SwiftUI

/// 一個區域的等角箱庭：Metal 畫面加上手勢（ADR 0006、0008）。
///
/// 這裡只把手勢交給箱庭（`RoomScene`）：模擬、畫面準備與遊戲迴圈都在那裡。
/// - 點一下企鵝：告訴模擬主人點了牠（兩隻重疊時前面那隻優先）；點空地沒有反應。
/// - 拖曳空地捲動；從企鵝身上開始拖不捲動，留給之後的「拎起來」。
/// - 雙指捏合縮放；一段時間沒碰，鏡頭慢慢移回第一隻身邊（遊戲設計 2026-11-16）。
/// 畫面本身不會移動，所以手勢的座標就是畫面上的位置。
///
/// 箱庭只建一次：第一次出現時才建，之後一直沿用（作者 2026-11-18 決定）。不在 `init` 裡建：
/// 上一層的 `body` 每次重算都會重新呼叫 `init`，`State(initialValue:)` 的參數會真的算出來再被丟掉；
/// 建一次要畫整個房間，放在 `init` 會在主執行緒白做。
struct RoomView: View {
    let room: RoomLayout
    /// 可能上台的每一隻（後台名單），圖在載入時一次送進 GPU。只在建箱庭時讀一次。
    let cast: [RoomScene.Member]
    /// 一開始在台上的企鵝與站的位置，依上台先後。只在建箱庭時讀一次。
    let start: [(id: PenguinID, position: TilePosition)]
    /// 模擬跑出來的事（例如主人點了哪一隻），交給外面記錄。
    var onOutputs: ([Simulation.Output]) -> Void = { _ in }

    /// 第一次出現前是 nil。
    @State private var scene: RoomScene?
    @Environment(\.displayScale) private var displayScale

    /// 只記下參數，不建箱庭（見上面的說明）。
    init(room: RoomLayout, cast: [RoomScene.Member], start: [(id: PenguinID, position: TilePosition)],
         onOutputs: @escaping ([Simulation.Output]) -> Void = { _ in }) {
        self.room = room
        self.cast = cast
        self.start = start
        self.onOutputs = onOutputs
    }

    var body: some View {
        GeometryReader { proxy in
            if let scene {
                MetalRoomView(scene: scene, onOutputs: onOutputs)
                    .gesture(tapGesture(scene))
                    .simultaneousGesture(panGesture(scene))
                    .simultaneousGesture(pinchGesture(scene))
                    .onAppear { scene.builder.resize(viewport: proxy.size, displayScale: displayScale) }
                    .onChange(of: proxy.size) { _, size in scene.builder.resize(viewport: size, displayScale: displayScale) }
            }
        }
        .onAppear {
            if scene == nil {
                scene = RoomScene(room: room, cast: cast, start: start, seed: .random(in: .min ... .max),
                                  now: CACurrentMediaTime())
            }
        }
        .accessibilityElement()
        .accessibilityLabel("箱庭")
        .accessibilityAction(named: "點企鵝") {
            guard let scene, let first = scene.runner.current.penguins.first else { return }
            scene.builder.ownerTouched(now: CACurrentMediaTime())
            scene.runner.send(.ownerTapped(first.id, at: .now))
        }
    }

    private func tapGesture(_ scene: RoomScene) -> some Gesture {
        SpatialTapGesture()
            .onEnded { value in
                PerfSignposts.measure("tap") { _ = scene.tap(at: value.location, now: CACurrentMediaTime()) }
            }
    }

    private func panGesture(_ scene: RoomScene) -> some Gesture {
        DragGesture()
            .onChanged { value in
                scene.builder.panChanged(translation: value.translation, startLocation: value.startLocation,
                                         now: CACurrentMediaTime())
            }
            .onEnded { _ in scene.builder.panEnded(now: CACurrentMediaTime()) }
    }

    private func pinchGesture(_ scene: RoomScene) -> some Gesture {
        MagnifyGesture()
            .onChanged { value in
                scene.builder.pinchChanged(magnification: value.magnification, anchor: value.startLocation,
                                           now: CACurrentMediaTime())
            }
            .onEnded { value in
                scene.builder.pinchEnded(magnification: value.magnification, anchor: value.startLocation,
                                         now: CACurrentMediaTime())
            }
    }
}

#Preview("沒有角色包") {
    let ids = [PenguinID("placeholder-1"), PenguinID("placeholder-2")]
    RoomView(room: .indoor, cast: ids.map { .init(id: $0) },
             start: [(ids[0], TilePosition(i: 4.5, j: 4.5)), (ids[1], TilePosition(i: 5.5, j: 3.5))])
        .ignoresSafeArea()
}
