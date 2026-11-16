import SwiftUI

/// 顯示一隻企鵝；點一下播放「哈囉」。沒有角色包時顯示占位圖形。
struct PenguinView: View {
    let character: RigCompositor?
    @State private var helloStart: Date?

    var body: some View {
        if let character {
            TimelineView(.animation(minimumInterval: 1 / HelloMotion.framesPerSecond, paused: helloStart == nil)) { context in
                PixelSprite(grid: character.compose(pose(at: context.date)), colors: character.colors)
            }
            .contentShape(Rectangle())
            .onTapGesture {
                // 播放中再點不重來，揮完才能再打招呼
                if helloStart == nil { helloStart = .now }
            }
            .task(id: helloStart) {
                guard helloStart != nil else { return }
                try? await Task.sleep(for: .seconds(HelloMotion.duration))
                helloStart = nil
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
    PenguinView(character: nil)
}
