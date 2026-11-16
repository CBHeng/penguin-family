import CoreGraphics
import SwiftUI

/// 依 `Behavior` 的意圖顯示一隻企鵝並播放動作，每個像素放大成 `pointsPerPixel`。
///
/// 這裡不決定要做什麼：點擊與「動作播完」都交回給 `Behavior`，再照新的意圖播放。
/// 每一格都是載入角色時預先算好的圖（`CharacterFrames`），播放時只取出來貼。
/// 沒有角色包時顯示灰色占位剪影，點了也不回應（沒有動作可播）。
struct PenguinView: View {
    let character: CharacterFrames?
    let intent: PenguinBehavior.Intent
    var pointsPerPixel: CGFloat = 3
    var onTap: () -> Void = {}
    var onMotionFinished: () -> Void = {}
    /// 正在播的動作與開始時間；站著時是 nil。
    @State private var playing: (motion: Motion, start: Date)?

    /// 腳底在圖上的位置（像素），用來把企鵝放到箱庭的某一點。
    static func anchor(for character: CharacterFrames?) -> PixelPoint {
        character?.anchor ?? PlaceholderSilhouette.anchor
    }

    /// 意圖要播哪個動作；待機不播。
    static func motion(for intent: PenguinBehavior.Intent) -> Motion? {
        switch intent {
        case .idle: nil
        case .hello: .hello
        }
    }

    var body: some View {
        if let character {
            TimelineView(.animation(minimumInterval: 1 / (playing?.motion.framesPerSecond ?? 20), paused: playing == nil)) { context in
                PixelImageView(image: image(of: character, at: context.date),
                               pixelWidth: character.width, pixelHeight: character.height,
                               pointsPerPixel: pointsPerPixel)
            }
            .contentShape(Rectangle())
            .onTapGesture { onTap() }
            .onChange(of: intent, initial: true) { _, intent in
                playing = Self.motion(for: intent).map { ($0, .now) }
            }
            .task(id: playing?.start) {
                guard let playing else { return }
                do {
                    try await Task.sleep(for: .seconds(playing.motion.duration))
                } catch {
                    return  // 被取消（例如意圖改變）時不回報播完
                }
                onMotionFinished()
            }
            .accessibilityElement()
            .accessibilityAddTraits(.isButton)
            .accessibilityLabel("企鵝")
        } else {
            PixelImageView(grid: PlaceholderSilhouette.grid, colors: PlaceholderSilhouette.colors,
                           pointsPerPixel: pointsPerPixel)
                .accessibilityLabel("企鵝（占位）")
        }
    }

    /// 現在該顯示哪一格；格數對齊動作的每秒格數，和私有素材 repo 的預覽一致。
    private func image(of character: CharacterFrames, at date: Date) -> CGImage? {
        guard let playing else { return character.rest }
        let frame = Int((date.timeIntervalSince(playing.start) * playing.motion.framesPerSecond).rounded(.down))
        return character.image(playing.motion, frame: max(0, frame))
    }
}

/// 原始尺寸的像素圖，每個像素放大成 `pointsPerPixel`，不做平滑處理。
struct PixelImageView: View {
    let image: CGImage?
    let pixelWidth: Int
    let pixelHeight: Int
    let pointsPerPixel: CGFloat

    init(grid: PixelGrid, colors: [Character: PixelColor], pointsPerPixel: CGFloat) {
        self.init(image: PixelImage.cgImage(grid, colors: colors),
                  pixelWidth: grid.width, pixelHeight: grid.height, pointsPerPixel: pointsPerPixel)
    }

    init(image: CGImage?, pixelWidth: Int, pixelHeight: Int, pointsPerPixel: CGFloat) {
        self.image = image
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
        self.pointsPerPixel = pointsPerPixel
    }

    var body: some View {
        if let image {
            Image(decorative: image, scale: 1)
                .interpolation(.none)
                .resizable()
                .frame(width: CGFloat(pixelWidth) * pointsPerPixel, height: CGFloat(pixelHeight) * pointsPerPixel)
        }
    }
}

/// 沒有角色包（例如公開 repo 乾淨 clone）或第二隻的美術還沒好時的占位：不像任何玩偶的灰色剪影。
nonisolated enum PlaceholderSilhouette {
    static let colors: [Character: PixelColor] = [
        "G": PixelColor(hex: "#A3A3A3")!,
        "O": PixelColor(hex: "#5E5E5E")!,
    ]

    /// 腳底在圖上的位置。
    static let anchor = PixelPoint(x: 15, y: 35)

    static let grid: PixelGrid = {
        var grid = PixelGrid(width: 31, height: 36)
        func inside(_ x: Int, _ y: Int, cx: Double, cy: Double, rx: Double, ry: Double) -> Bool {
            let dx = (Double(x) + 0.5 - cx) / rx, dy = (Double(y) + 0.5 - cy) / ry
            return dx * dx + dy * dy <= 1
        }
        for y in 0..<grid.height {
            for x in 0..<grid.width
            where inside(x, y, cx: 15.5, cy: 10, rx: 8, ry: 8) || inside(x, y, cx: 15.5, cy: 24, rx: 12, ry: 10.5) {
                grid[x, y] = "G"
            }
        }
        var edge: [(Int, Int)] = []
        for y in 0..<grid.height {
            for x in 0..<grid.width where grid[x, y] == nil {
                let near = [(x + 1, y), (x - 1, y), (x, y + 1), (x, y - 1)]
                if near.contains(where: { grid.contains($0.0, $0.1) && grid[$0.0, $0.1] == "G" }) {
                    edge.append((x, y))
                }
            }
        }
        for (x, y) in edge { grid[x, y] = "O" }
        return grid
    }()
}

#Preview("占位") {
    PenguinView(character: nil, intent: .idle)
}
