import QuartzCore
import SwiftUI

/// 一個區域的等角箱庭：Metal 畫面加上手勢（ADR 0006、0008）。
///
/// 這裡只把手勢交給箱庭（`RoomScene`）：模擬、畫面準備與遊戲迴圈都在那裡。
/// - 點一下角色：告訴模擬主人點了牠（兩隻重疊時前面那隻優先）；點空地沒有反應。
/// - 拖曳空地捲動；從角色身上開始拖不捲動，留給之後的「拎起來」。
/// - 雙指捏合縮放；一段時間沒碰，鏡頭慢慢移回第一隻身邊（遊戲設計 2026-11-16）。
/// 畫面本身不會移動，所以手勢的座標就是畫面上的位置。
///
/// 除錯用（只在 Debug 編譯）：右下角的「加睏意」按鈕，點一次台上每一隻的睏意加 `debugSleepinessStep`（作者 2026-11-20 要求）。
///
/// 箱庭只建一次：第一次出現時才建，之後一直沿用（作者 2026-11-18 決定）。不在 `init` 裡建：
/// 上一層的 `body` 每次重算都會重新呼叫 `init`，`State(initialValue:)` 的參數會真的算出來再被丟掉；
/// 建一次要畫整個房間，放在 `init` 會在主執行緒白做。
struct RoomView: View {
    let room: RoomLayout
    /// 可能上台的每一隻（後台名單），圖在載入時一次送進 GPU。只在建箱庭時讀一次。
    let cast: [RoomScene.Member]
    /// 一開始在台上的角色與站的位置，依上台先後。只在建箱庭時讀一次。
    let start: [(id: CharacterID, position: TilePosition)]
    /// 共用特效的形狀（ADR 0010）。只在建箱庭時讀一次。
    let effects: EffectLibrary
    /// 打開 App 時從事件紀錄讀到的、每隻最後一次被點的時間（A1 第 14 項）。只在建箱庭時讀一次。
    let lastTaps: [CharacterID: Date]
    /// 模擬跑出來的事（例如主人點了哪一隻），交給外面記錄。
    var onOutputs: ([Simulation.Output]) -> Void = { _ in }
    /// 箱庭建好時交給外面（例如角色的屬性條要讀它的快照）。
    var onScene: (RoomScene) -> Void = { _ in }

    /// 除錯按鈕點一次加多少睏意（0～100）。
    static let debugSleepinessStep = 25.0

    /// 第一次出現前是 nil。
    @State private var scene: RoomScene?
    @Environment(\.displayScale) private var displayScale

    /// 只記下參數，不建箱庭（見上面的說明）。
    init(room: RoomLayout, cast: [RoomScene.Member], start: [(id: CharacterID, position: TilePosition)],
         effects: EffectLibrary = .empty, lastTaps: [CharacterID: Date] = [:],
         onOutputs: @escaping ([Simulation.Output]) -> Void = { _ in }, onScene: @escaping (RoomScene) -> Void = { _ in }) {
        self.room = room
        self.cast = cast
        self.start = start
        self.effects = effects
        self.lastTaps = lastTaps
        self.onOutputs = onOutputs
        self.onScene = onScene
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
                let created = RoomScene(room: room, cast: cast, start: start, seed: .random(in: .min ... .max),
                                        now: CACurrentMediaTime(), effects: effects, lastTaps: lastTaps)
                scene = created
                onScene(created)
            }
        }
        #if DEBUG
        .overlay(alignment: .bottomTrailing) {
            if let scene {
                Button {
                    scene.runner.send(.addSleepiness(Self.debugSleepinessStep))
                } label: {
                    Label("睏意 +\(Int(Self.debugSleepinessStep))", systemImage: "moon.zzz")
                        .font(.caption)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(.black.opacity(0.45), in: Capsule())
                        .foregroundStyle(.white)
                }
                .padding(.trailing, 16)
                .padding(.bottom, 40)
                .accessibilityLabel("除錯：加睏意")
            }
        }
        #endif
        .accessibilityElement()
        .accessibilityLabel("箱庭")
        .accessibilityAction(named: "點第一隻") {
            guard let scene, let first = scene.runner.current.characters.first else { return }
            scene.tap(first.id, now: CACurrentMediaTime())
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
    let ids = [CharacterID("placeholder-1"), CharacterID("placeholder-2")]
    RoomView(room: .indoor, cast: ids.map { .init(id: $0) },
             start: zip(ids, RoomLayout.indoor.startTiles(count: ids.count)).map { ($0, $1.center) })
        .ignoresSafeArea()
}
