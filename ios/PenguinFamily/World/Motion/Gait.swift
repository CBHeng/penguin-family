import Foundation

/// 企鵝面向哪裡：正面（面向鏡頭，站著、哈囉），或沿格線走的斜向四個方向（遊戲設計的「企鵝的方向」）。
/// 名稱和角色包 `vector.json` 的方向名稱相同，閒晃的資料（`wander.json`）也用這些名稱。
nonisolated enum Facing: String, CaseIterable, Sendable, Decodable {
    case front
    /// 往左下走（沿 j 軸往前）。
    case frontLeft
    /// 往左上走（沿 i 軸往後）。
    case backLeft
    /// 往右下走（沿 i 軸往前）。
    case frontRight
    /// 往右上走（沿 j 軸往後）。
    case backRight

    /// 斜向四個方向。
    static let oblique: [Facing] = [.frontLeft, .backLeft, .frontRight, .backRight]
}

/// 斜向某一格的姿勢：不取整數，每一格照經過的時間算。單位都是角色畫布的單位。
nonisolated struct VectorWalkPose: Equatable, Sendable {
    struct Offset: Equatable, Sendable {
        var dx: Double
        var dy: Double
    }

    /// 上半身（腳以外）以身體的轉軸（腳底）傾斜幾度，正值順時針。
    var swayDegrees = 0.0
    /// 上半身往下沉。
    var dip = 0.0
    /// 近的手以肩膀往外張開幾度。
    var armOpenDegrees = 0.0
    /// 近的手另外往下（負值往上）。
    var armDy = 0.0
    /// 腳的名稱（`farFoot`、`nearFoot`）→ 位移。
    var feet: [String: Offset] = [:]

    static let rest = VectorWalkPose()
}

/// 走路的步態：慢走與小跑。數字不分角色，兩隻企鵝共用（同哈囉的時間軸）。
///
/// 數字是作者 2026-11-17 定的（當時在像素版上調）；算式和私有素材 repo `vector.js` 的 `GAITS`、`walkPose` 相同，逐格比對。
nonisolated struct Gait: Equatable, Sendable {
    /// 地板一格沿格線走是幾個步幅單位（一個單位是畫面上左右 2、上下 1 個單位；一格的邊是 16×8 單位）。
    static let unitsPerTile = 8.0

    /// 識別用：`walk`、`trot`。
    let name: String
    /// 一個循環幾秒（走兩步）。
    let cycle: Double
    /// 身體左右搖擺的幅度（度）。
    let sway: Double
    /// 身體朝走的方向前傾（度）。
    let lean: Double
    /// 換腳落地時上半身往下沉多少（單位）。
    let dip: Double
    /// 近的手往外張開（度）。
    let armOpen: Double
    /// 手往上時多張開、往下時收回的幅度（度）。
    let flap: Double
    /// 近的手上下晃的幅度（單位）。
    let armBob: Double
    /// 一個循環晃幾次：1 跟著左右搖擺，2 每一步一次。
    let armBobSteps: Int
    /// 一步的步幅（步幅單位）。
    let stride: Double
    /// 抬腳的高度（單位）。
    let lift: Double

    /// 慢走：一個循環 1 秒走兩步，約 2 秒走一格地板。
    static let walk = Gait(name: "walk", cycle: 1.0, sway: 3.0, lean: 0.0, dip: 1, armOpen: 12, flap: 0,
                           armBob: 1, armBobSteps: 1, stride: 2, lift: 1)
    /// 小跑：碎步快一倍、往前傾，手張更開、每一步拍一次。
    static let trot = Gait(name: "trot", cycle: 0.5, sway: 2.0, lean: 5.0, dip: 1, armOpen: 20, flap: 8,
                           armBob: 1, armBobSteps: 2, stride: 2, lift: 1)
    static let all: [Gait] = [.walk, .trot]

    /// 每秒走幾格地板：每半個循環前進一個步幅，踩著的腳才不會在地上滑。
    var tilesPerSecond: Double { stride / (cycle / 2) / Self.unitsPerTile }

    /// 斜向第 `t` 秒的姿勢（`walk` 是畫好的那一邊的走法；翻轉的方向用來源的）。
    /// 下沉是落地時最低的平滑起伏，抬腳在搖擺到一側時平滑抬起；腳往前後、手上下都不取整數。
    func vectorPose(at t: Double, walk: VectorRig.Walk) -> VectorWalkPose {
        let ph = (t / cycle).truncatingRemainder(dividingBy: 1)
        let s = sin(2 * Double.pi * ph)
        let ahead = walk.forward.x < 0 ? -1.0 : 1.0   // 朝走的方向（畫面左或右）前傾
        let c = (1 + cos(4 * Double.pi * ph)) / 2
        let rightFoot = walk.leftFoot == "farFoot" ? "nearFoot" : "farFoot"
        // 腳的前後（步幅單位）：抬起的腳往前、踩著的腳往後
        let kLeft = (-stride / 2) * cos(2 * Double.pi * ph)
        var pose = VectorWalkPose()
        for (name, k, side) in [(walk.leftFoot, kLeft, s), (rightFoot, -kLeft, -s)] {
            let lift = self.lift * Self.smoothstep(0.1, 0.6, side)
            let peek = (walk.peek[name] ?? 0) * max(0, -k)   // 越往後越往下露
            pose.feet[name] = .init(dx: walk.forward.x * k, dy: walk.forward.y * k - lift + peek)
        }
        // 手：up 是手往上的程度（-1～1）。慢走時往手那側傾就往下；拍手時往上會多張開
        let wave = armBobSteps == 1 ? s : sin(4 * Double.pi * ph)
        let up = -wave * Double(walk.armSide)
        pose.swayDegrees = sway * s + ahead * lean
        pose.dip = dip * c * c
        pose.armOpenDegrees = armOpen + flap * up
        pose.armDy = -armBob * up
        return pose
    }

    /// `a` 到 `b` 之間平滑地從 0 變 1。
    static func smoothstep(_ a: Double, _ b: Double, _ x: Double) -> Double {
        let t = min(1, max(0, (x - a) / (b - a)))
        return t * t * (3 - 2 * t)
    }
}
