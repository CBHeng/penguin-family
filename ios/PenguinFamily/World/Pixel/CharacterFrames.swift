import CoreGraphics

/// 一隻角色預先算好的每一格圖：站好的一張，加上 `Motion.all` 每個動作的每一格。
///
/// 載入角色時全部算好（作者 2026-11-16 決定），播放時只取出來貼，不再每格合成。
/// 2026-11-16 在 Mac（M4 Pro）上量：哈囉 56 格約 5 毫秒算完；一格 44×45 像素約 7.9KB，56 格約 0.44MB。
/// 跟著互動即時變化的姿勢（例如抱抱時依觸覺壓扁）不放這裡，直接用 `RigCompositor` 合成。
nonisolated struct CharacterFrames: @unchecked Sendable {
    // CGImage 建好後不會再改，可以安全地跨執行緒共用；SDK 沒標成 Sendable，所以手動標示。

    /// 每格的寬高（像素）。
    let width: Int
    let height: Int
    /// 腳底在圖上的位置（像素），用來把企鵝放到箱庭的某一點。
    let anchor: PixelPoint
    /// 站好的樣子。
    let rest: CGImage?
    /// 動作名稱 → 每一格。
    private let motions: [String: [CGImage?]]

    init(compositor: RigCompositor, motions: [Motion] = Motion.all) {
        let colors = compositor.colors
        let restGrid = compositor.compose(.rest)
        width = restGrid.width
        height = restGrid.height
        rest = PixelImage.cgImage(restGrid, colors: colors)
        let pivot = compositor.rig.parts["body"]?.pivot
        anchor = PixelPoint(x: Int((pivot?.x ?? Double(width) / 2).rounded(.down)),
                            y: Int((pivot?.y ?? Double(height)).rounded(.up)))
        var frames: [String: [CGImage?]] = [:]
        for motion in motions {
            frames[motion.name] = (0..<motion.frameCount).map { i in
                PixelImage.cgImage(compositor.compose(motion.pose(i)), colors: colors)
            }
        }
        self.motions = frames
    }

    /// 某個動作的第幾格；沒算過的動作或超過最後一格時是站好的樣子。
    func image(_ motion: Motion, frame: Int) -> CGImage? {
        guard let frames = motions[motion.name], frames.indices.contains(frame) else { return rest }
        return frames[frame]
    }

    /// 存了幾張圖（含站好的一張）。
    var imageCount: Int { 1 + motions.values.reduce(0) { $0 + $1.count } }

    /// 大約佔多少記憶體（位元組）：每張圖每個像素 4 個位元組。
    var byteCount: Int { imageCount * width * height * 4 }
}
