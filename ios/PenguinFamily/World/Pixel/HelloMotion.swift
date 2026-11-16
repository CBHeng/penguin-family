import Foundation

/// 「哈囉」動作的時間軸（作者 2026-11-07 定案），照私有素材 repo 的 `hello_pose()`。
///
/// 右手舉起小幅快速揮動，頭往畫面左側歪，身體微微壓扁；最後手放下、彈回站好。
/// 動作參數不分角色，兩隻企鵝共用。
nonisolated enum HelloMotion {
    /// 揮得快，要每秒 20 格才看得清楚。
    static let framesPerSecond = 20.0
    /// 秒，含最後站好的停頓。
    static let duration = 2.8
    static var frameCount: Int { Int(duration * framesPerSecond) }

    static let armUp = -140.0
    static let headTilt = -9.0
    /// 揮手幅度小、頻率快：上下各 8 度，每秒 4 下。
    static let waveDegrees = 8.0
    static let waveHz = 4.0
    /// 舉手時身體高度縮到 94%。
    static let squash = 0.94

    /// 第 index 格的姿勢；超過最後一格就是站好的姿勢。
    static func pose(frame index: Int) -> RigPose {
        pose(at: Double(index) / framesPerSecond)
    }

    /// 第 t 秒的姿勢。算式的順序照 Python，讓浮點結果相同。
    static func pose(at t: Double) -> RigPose {
        if t < 0.35 {
            let k = smooth(t / 0.35)
            return RigPose(headDegrees: headTilt * k, armDegrees: armUp * k, squash: 1 - (1 - squash) * k)
        }
        if t < 1.75 {
            let arm = armUp + sin((t - 0.35) * 2 * Double.pi * waveHz) * waveDegrees
            return RigPose(headDegrees: headTilt, armDegrees: arm, squash: squash)
        }
        if t < 2.1 {
            let k = smooth((t - 1.75) / 0.35)
            return RigPose(headDegrees: headTilt * (1 - k), armDegrees: armUp * (1 - k), squash: squash + (1 - squash) * k)
        }
        return .rest
    }

    private static func smooth(_ t: Double) -> Double {
        let t = max(0, min(1, t))
        return t * t * (3 - 2 * t)
    }
}
