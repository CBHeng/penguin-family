import Foundation

/// 「哈囉」動作的時間軸（作者 2026-11-07 定案），和私有素材 repo `vector.js` 的 `helloPose` 相同（逐格比對）。
///
/// 右手舉起小幅快速揮動，頭往畫面左側歪，身體微微壓扁；最後手放下、彈回站好。
/// 動作參數不分角色，兩隻企鵝共用。
nonisolated enum HelloMotion {
    /// 秒，含最後站好的停頓。
    static let duration = 2.8

    static let armUp = -140.0
    static let headTilt = -9.0
    /// 揮手幅度小、頻率快：上下各 8 度，每秒 4 下。
    static let waveDegrees = 8.0
    static let waveHz = 4.0
    /// 舉手時身體高度縮到 94%。
    static let squash = 0.94

    /// 第 t 秒的姿勢；播完之後是站好。算式的順序和 JS 相同，讓浮點結果相同。
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
