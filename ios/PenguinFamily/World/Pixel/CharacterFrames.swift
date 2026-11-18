/// 一隻角色預先算好的每一格圖：正面站好的一張、`Motion.all` 每個動作的每一格，
/// 加上斜向四個方向的站姿與每個步態（慢走、小跑）的每一格。
///
/// 載入角色時全部算好（作者 2026-11-16 決定），播放時只取出來貼，不再每格合成。
/// 2026-11-16 在 Mac（M4 Pro）上量：哈囉 56 格約 6 毫秒算完；一格 44×45 像素約 7.9KB，57 張約 0.44MB。
/// 斜向一格 46×42 像素約 7.7KB，站姿 4 張加慢走 48 格、小跑 24 格共 76 張，約 0.59MB。
/// 跟著互動即時變化的姿勢（例如抱抱時依觸覺壓扁）不放這裡，直接用 `RigCompositor` 合成。
nonisolated struct CharacterFrames: Sendable {
    /// 正面每格的寬高（像素）。
    let width: Int
    let height: Int
    /// 正面腳底在圖上的位置（像素），用來把企鵝放到箱庭的某一點。
    let anchor: PixelPoint
    /// 正面站好的樣子。
    let rest: PixelBitmap
    /// 斜向的圖；角色包沒有斜向時是 nil（只能面向鏡頭）。
    let oblique: ObliqueFrames?
    /// 動作名稱 → 每一格。
    private let motions: [String: [PixelBitmap]]

    init(compositor: RigCompositor, oblique: ObliqueCompositor? = nil,
         motions: [Motion] = Motion.all, gaits: [Gait] = Gait.all) {
        let colors = compositor.colors
        rest = PixelBitmap(compositor.compose(.rest), colors: colors)
        width = rest.width
        height = rest.height
        let pivot = compositor.rig.parts["body"]?.pivot
        anchor = PixelPoint(x: Int((pivot?.x ?? Double(width) / 2).rounded(.down)),
                            y: Int((pivot?.y ?? Double(height)).rounded(.up)))
        var frames: [String: [PixelBitmap]] = [:]
        for motion in motions {
            frames[motion.name] = (0..<motion.frameCount).map { i in
                PixelBitmap(compositor.compose(motion.pose(i)), colors: colors)
            }
        }
        self.motions = frames
        self.oblique = oblique.map { ObliqueFrames(compositor: $0, colors: colors, gaits: gaits) }
    }

    /// 某個動作的第幾格；沒算過的動作或超過最後一格時是站好的樣子。
    func image(_ motion: Motion, frame: Int) -> PixelBitmap {
        guard let frames = motions[motion.name], frames.indices.contains(frame) else { return rest }
        return frames[frame]
    }

    /// 某個動作算好了幾格；沒算過是 0。
    func frameCount(of motion: Motion) -> Int { motions[motion.name]?.count ?? 0 }

    /// 存了幾張圖（含站好的一張與斜向的圖）。
    var imageCount: Int { 1 + motions.values.reduce(0) { $0 + $1.count } + (oblique?.imageCount ?? 0) }

    /// 大約佔多少記憶體（位元組）。
    var byteCount: Int {
        rest.byteCount + motions.values.joined().reduce(0) { $0 + $1.byteCount } + (oblique?.byteCount ?? 0)
    }
}

/// 斜向四個方向預先算好的圖：站姿，加上每個步態在每個方向一個循環的每一格。
nonisolated struct ObliqueFrames: Sendable {
    /// 每格的寬高（像素），和正面不同。
    let width: Int
    let height: Int
    /// 腳底在圖上的位置（像素）；和正面的腳底對到同一點，換方向時不會跳。
    let anchor: PixelPoint
    /// 方向 → 站著的樣子（部件都不動，等於定稿圖）。
    let standing: [Facing: PixelBitmap]
    /// 步態名稱 → 方向 → 一個循環的每一格。
    private let gaits: [String: [Facing: [PixelBitmap]]]

    init(compositor: ObliqueCompositor, colors: [Character: PixelColor], gaits: [Gait]) {
        width = compositor.width
        height = compositor.height
        anchor = compositor.anchor
        var standing: [Facing: PixelBitmap] = [:]
        var all: [String: [Facing: [PixelBitmap]]] = [:]
        for facing in Facing.oblique {
            guard let side = compositor.walkSide(facing), let still = compositor.compose(facing, .rest) else { continue }
            standing[facing] = PixelBitmap(still, colors: colors)
            for gait in gaits {
                all[gait.name, default: [:]][facing] = (0..<gait.frameCount).compactMap { i in
                    compositor.compose(facing, gait.pose(frame: i, side: side)).map { PixelBitmap($0, colors: colors) }
                }
            }
        }
        self.standing = standing
        self.gaits = all
    }

    /// 某個步態、某個方向的第幾格（超過一個循環就從頭繞）；沒有時是 nil。
    func image(_ gait: Gait, _ facing: Facing, frame: Int) -> PixelBitmap? {
        guard let frames = gaits[gait.name]?[facing], !frames.isEmpty else { return nil }
        return frames[((frame % frames.count) + frames.count) % frames.count]
    }

    /// 某個步態一個循環幾格；沒有時是 0。
    func frameCount(_ gait: Gait, _ facing: Facing) -> Int { gaits[gait.name]?[facing]?.count ?? 0 }

    var imageCount: Int { standing.count + gaits.values.flatMap(\.values).reduce(0) { $0 + $1.count } }

    var byteCount: Int {
        standing.values.reduce(0) { $0 + $1.byteCount }
            + gaits.values.flatMap(\.values).joined().reduce(0) { $0 + $1.byteCount }
    }
}
