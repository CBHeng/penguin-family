import Foundation

/// 企鵝面向哪裡：正面（面向鏡頭，站著、哈囉），或沿格線走的斜向四個方向（遊戲設計的「企鵝的方向」）。
nonisolated enum Facing: String, CaseIterable, Sendable {
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

/// 斜向一格的姿勢：全部是整格平移，不旋轉、不縮放。
nonisolated struct WalkPose: Equatable, Sendable {
    /// 腳的位移（像素）。
    struct Offset: Equatable, Sendable {
        var dx: Int
        var dy: Int
    }

    /// 身體傾斜：每往上一列往右移幾格（負值往左）。
    var lean = 0.0
    /// 上半身往下沉幾格。
    var dip = 0
    /// 近的手肩膀以下每列往外移幾格。
    var armOpen = 0.0
    /// 近的手另外往下移幾格（負值往上）。
    var armDy = 0
    /// 腳的名稱（`farFoot`、`nearFoot`）→ 位移。
    var feet: [String: Offset] = [:]

    static let rest = WalkPose()
}

/// 一個方向怎麼走：往哪裡、哪隻腳在左邊、手在哪側、哪隻腳要露出來。右邊方向用左邊的（翻轉前的姿勢）。
nonisolated struct WalkSide: Sendable {
    /// 往前一步在畫面上是 (x, y) 像素。
    let forward: (x: Int, y: Int)
    let leftFoot: String
    let rightFoot: String
    /// 近的手在身體哪一側：1 右、-1 左。
    let armSide: Int
    /// 被身體擋住的腳，往後踩時多往下幾格。
    let peek: [String: Int]
}

/// 走路的步態：慢走與小跑。數字不分角色，兩隻企鵝共用（同哈囉的時間軸）。
///
/// 照私有素材 repo `walk.py` 的 `WALK`、`TROT` 與 `walk_pose()`，要逐格得到相同的姿勢：
/// 算式的先後順序、`round()` 的 .5 取偶數都照 Python。作者 2026-11-17 定案。
nonisolated struct Gait: Equatable, Sendable {
    /// 每秒幾格（兩種步態相同）。
    static let framesPerSecond = 12.0
    /// 地板一格沿格線走是幾個步幅單位（一個單位是畫面上左右 2、上下 1 像素；一格的邊是 16×8 像素）。
    static let unitsPerTile = 8.0

    /// 識別用：`walk`、`trot`。
    let name: String
    /// 一個循環幾秒（走兩步）。
    let cycle: Double
    /// 身體左右搖擺的幅度（度）。
    let sway: Double
    /// 身體朝走的方向前傾（度）。
    let lean: Double
    /// 換腳落地時上半身往下沉幾格。
    let dip: Int
    /// 近的手往外張開（度）。
    let armOpen: Double
    /// 手往上時多張開、往下時收回的幅度（度）。
    let flap: Double
    /// 近的手上下晃的幅度（像素）。
    let armBob: Double
    /// 一個循環晃幾次：1 跟著左右搖擺，2 每一步一次。
    let armBobSteps: Int
    /// 一步的步幅（單位）。
    let stride: Double
    /// 抬腳的高度（像素）。
    let lift: Int

    /// 慢走：一個循環 1 秒走兩步，約 2 秒走一格地板。
    static let walk = Gait(name: "walk", cycle: 1.0, sway: 3.0, lean: 0.0, dip: 1, armOpen: 12, flap: 0,
                           armBob: 1, armBobSteps: 1, stride: 2, lift: 1)
    /// 小跑：碎步快一倍、往前傾，手張更開、每一步拍一次。
    static let trot = Gait(name: "trot", cycle: 0.5, sway: 2.0, lean: 5.0, dip: 1, armOpen: 20, flap: 8,
                           armBob: 1, armBobSteps: 2, stride: 2, lift: 1)
    static let all: [Gait] = [.walk, .trot]

    /// 一個循環幾格。
    var frameCount: Int { Int((cycle * Self.framesPerSecond).rounded(.toNearestOrEven)) }

    /// 每秒走幾格地板：每半個循環前進一個步幅，踩著的腳才不會在地上滑。
    var tilesPerSecond: Double { stride / (cycle / 2) / Self.unitsPerTile }

    /// 第幾格的姿勢（`side` 是左邊方向的走法；右邊方向傳翻轉前的那一邊）。
    func pose(frame: Int, side: WalkSide) -> WalkPose {
        let t = Double(frame) / Self.framesPerSecond
        let ph = (t / cycle).truncatingRemainder(dividingBy: 1)
        let s = sin(2 * Double.pi * ph)
        // 左右搖擺，加上朝走的方向（畫面左或右）前傾
        let ahead = Double(side.forward.x).sign == .minus ? -1.0 : 1.0
        var pose = WalkPose()
        pose.lean = tan(RigCompositor.radians(sway * s + ahead * lean))
        pose.dip = cos(4 * Double.pi * ph) > 0.5 ? dip : 0  // 換腳落地時往下沉
        // 腳的前後（單位）：抬起的腳往前、踩著的腳往後
        let kLeft = -stride / 2 * cos(2 * Double.pi * ph)
        let kRight = -kLeft
        let liftLeft = s > 0.35 ? lift : 0
        let liftRight = s < -0.35 ? lift : 0
        for (name, k, lift) in [(side.leftFoot, kLeft, liftLeft), (side.rightFoot, kRight, liftRight)] {
            let peek = RigCompositor.roundHalfEven(Double(side.peek[name] ?? 0) * max(0.0, -k))  // 越往後越往下露
            let step = RigCompositor.roundHalfEven(k)
            pose.feet[name] = WalkPose.Offset(dx: side.forward.x * step, dy: side.forward.y * step - lift + peek)
        }
        // 手：up 是手往上的程度（-1～1）。慢走時往手那側傾就往下；拍手時往上會多張開
        let wave = armBobSteps == 1 ? s : sin(4 * Double.pi * ph)
        let up = -wave * Double(side.armSide)
        pose.armDy = Self.roundHalfTowardZero(-armBob * up)
        pose.armOpen = tan(RigCompositor.radians(armOpen + flap * up))
        return pose
    }

    /// 四捨五入，但剛好一半時往 0 取，正負兩邊的格數才會一樣（同 `walk.py` 的 `sround`）。
    static func roundHalfTowardZero(_ value: Double) -> Int {
        let magnitude = (abs(value) + 0.5 - 1e-9).rounded(.down)
        return Int(value.sign == .minus ? -magnitude : magnitude)
    }
}
