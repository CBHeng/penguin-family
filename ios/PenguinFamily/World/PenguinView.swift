import CoreGraphics
import SwiftUI

/// 依 `Behavior` 的意圖顯示一隻企鵝並播放動作，每個像素固定放大成 `pointsPerPixel`。
///
/// 這裡不決定要做什麼：點擊與「動作播完」都交回給 `Behavior`，再照新的意圖播放。
/// 沒有角色包時顯示灰色占位剪影，點了也不回應（沒有動作可播）。
struct PenguinView: View {
    let character: RigCompositor?
    let intent: PenguinBehavior.Intent
    var pointsPerPixel: CGFloat = 3
    var onTap: () -> Void = {}
    var onMotionFinished: () -> Void = {}
    @State private var helloStart: Date?

    /// 腳底在圖上的位置（像素），用來把企鵝放到箱庭的某一點。
    static func anchor(for character: RigCompositor?) -> PixelPoint {
        guard let pivot = character?.rig.parts["body"]?.pivot else { return PlaceholderSilhouette.anchor }
        return PixelPoint(x: Int(pivot.x.rounded(.down)), y: Int(pivot.y.rounded(.up)))
    }

    var body: some View {
        if let character {
            TimelineView(.animation(minimumInterval: 1 / HelloMotion.framesPerSecond, paused: helloStart == nil)) { context in
                PixelImageView(grid: character.compose(pose(at: context.date)), colors: character.colors,
                               pointsPerPixel: pointsPerPixel)
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
            PixelImageView(grid: PlaceholderSilhouette.grid, colors: PlaceholderSilhouette.colors,
                           pointsPerPixel: pointsPerPixel)
                .accessibilityLabel("企鵝（占位）")
        }
    }

    /// 對齊到每秒 20 格，和私有素材 repo 的預覽一致。
    private func pose(at date: Date) -> RigPose {
        guard let helloStart else { return .rest }
        let frame = Int((date.timeIntervalSince(helloStart) * HelloMotion.framesPerSecond).rounded(.down))
        return HelloMotion.pose(frame: max(0, frame))
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
