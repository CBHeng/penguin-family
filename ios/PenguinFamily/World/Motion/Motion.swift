/// 正面的姿勢：頭、手各轉幾度，身體壓扁多少。`VectorRig.Facing.frontTransforms` 把它換成每個部件的矩陣。
nonisolated struct RigPose: Equatable, Sendable {
    /// 頭的角度，正值順時針。
    var headDegrees: Double = 0
    /// 手的角度，正值順時針。
    var armDegrees: Double = 0
    /// 身體高度比例；寬度用倒數撐開，讓體積看起來差不多。
    var squash: Double = 1

    static let rest = RigPose()
}

/// 正面的一個動作：播多久、第幾秒是什麼姿勢。
///
/// 每隻的數字不同（`PenguinMotions`），播的時候由那隻的數字組出來，例如 `HelloMotion.motion`。
/// 不用預先算，每一格照第幾秒的姿勢轉動部件（ADR 0007）。之後的打瞌睡、嚇一跳都照這個格式新增。
/// 走路不在這裡，見 `Gait`。
nonisolated struct Motion: Sendable {
    /// 識別用，例如 `hello`。不是角色名稱。
    let name: String
    /// 播完要幾秒。
    let duration: Double
    /// 第幾秒的姿勢；播完之後是站好。
    let poseAt: @Sendable (Double) -> RigPose
}
