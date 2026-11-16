import SwiftUI

/// 依 `Behavior` 的意圖顯示一隻企鵝並播放動作。
///
/// 這裡不決定要做什麼：點擊與「動作播完」都交回給 `Behavior`，再照新的意圖播放。
/// 沒有角色包時顯示占位圖形。
struct PenguinView: View {
    let character: RigCompositor?
    let intent: PenguinBehavior.Intent
    var onTap: () -> Void = {}
    var onMotionFinished: () -> Void = {}
    @State private var helloStart: Date?

    var body: some View {
        if let character {
            TimelineView(.animation(minimumInterval: 1 / HelloMotion.framesPerSecond, paused: helloStart == nil)) { context in
                PixelSprite(grid: character.compose(pose(at: context.date)), colors: character.colors)
            }
            .contentShape(Rectangle())
            .onTapGesture { onTap() }
            .onChange(of: intent, initial: true) { _, intent in
                helloStart = intent == .hello ? .now : nil
            }
            .task(id: helloStart) {
                guard helloStart != nil else { return }
                do {
                    try await Task.sleep(for: .seconds(HelloMotion.duration))
                } catch {
                    return  // 被取消（例如意圖改變）時不回報播完
                }
                onMotionFinished()
            }
            .accessibilityElement()
            .accessibilityAddTraits(.isButton)
            .accessibilityLabel("企鵝")
        } else {
            PlaceholderPenguin()
        }
    }

    /// 對齊到每秒 20 格，和私有素材 repo 的預覽一致。
    private func pose(at date: Date) -> RigPose {
        guard let helloStart else { return .rest }
        let frame = Int((date.timeIntervalSince(helloStart) * HelloMotion.framesPerSecond).rounded(.down))
        return HelloMotion.pose(frame: max(0, frame))
    }
}

/// 原始尺寸的像素圖，以整數倍放大、不做平滑處理，底部置中。
struct PixelSprite: View {
    let grid: PixelGrid
    let colors: [Character: PixelColor]
    /// 企鵝最多佔可用寬度或高度的比例。
    var fill: CGFloat = 0.7

    var body: some View {
        GeometryReader { proxy in
            let scale = max(1, floor(min(proxy.size.width / CGFloat(grid.width),
                                         proxy.size.height / CGFloat(grid.height)) * fill))
            if let image = PixelImage.cgImage(grid, colors: colors) {
                Image(decorative: image, scale: 1)
                    .interpolation(.none)
                    .resizable()
                    .frame(width: CGFloat(grid.width) * scale, height: CGFloat(grid.height) * scale)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }
}

/// 沒有角色包（例如公開 repo 乾淨 clone）時的占位圖形：不像任何玩偶的簡單灰色剪影。
struct PlaceholderPenguin: View {
    var body: some View {
        VStack(spacing: 4) {
            Circle()
                .frame(width: 70, height: 70)
            Ellipse()
                .frame(width: 110, height: 120)
            Text("沒有角色包")
                .font(.caption)
                .padding(.top, 12)
        }
        .foregroundStyle(.gray)
        .accessibilityElement(children: .combine)
    }
}

#Preview("占位") {
    PenguinView(character: nil, intent: .idle)
}
