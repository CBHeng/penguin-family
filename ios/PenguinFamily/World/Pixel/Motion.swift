/// 一個動作：每秒幾格、共幾格、第幾格是什麼姿勢。
///
/// 動作參數不分角色，兩隻企鵝共用同一份時間軸；每隻角色載入時，依這裡的清單把每一格預先算好（見 `CharacterFrames`）。
/// 之後的走路、打瞌睡、嚇一跳都照這個格式新增，再加進 `all`。
nonisolated struct Motion: Sendable {
    /// 識別用，例如 `hello`。不是角色名稱。
    let name: String
    let framesPerSecond: Double
    let frameCount: Int
    /// 第幾格的姿勢；超過最後一格時由呼叫的一方處理（顯示站好）。
    let pose: @Sendable (Int) -> RigPose

    /// 播完要幾秒。
    var duration: Double { Double(frameCount) / framesPerSecond }

    /// 主人點一下時的哈囉，時間軸見 `HelloMotion`。
    static let hello = Motion(name: "hello", framesPerSecond: HelloMotion.framesPerSecond,
                              frameCount: HelloMotion.frameCount, pose: { HelloMotion.pose(frame: $0) })

    /// App 會用到的所有動作；載入角色時全部預先算好（作者 2026-11-16 決定）。
    static let all: [Motion] = [.hello]
}
