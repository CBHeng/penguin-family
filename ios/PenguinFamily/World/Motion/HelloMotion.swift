import Foundation

/// 「哈囉」動作的時間軸（作者 2026-11-07 定案），算式和私有素材 repo `vector.js` 的 `helloPose` 相同（逐格比對）。
///
/// 右手舉起小幅快速揮動，頭往畫面左側歪，身體微微壓扁；最後手放下、彈回站好。
/// 數字每隻各一份（角色包的 `motion.json`，見 `PenguinMotions`），算式兩隻共用。
nonisolated struct HelloMotion: Decodable, Equatable, Sendable {
    /// 舉手要幾秒。
    var raise: Double
    /// 舉好後揮幾秒。
    var wave: Double
    /// 放下要幾秒。
    var lower: Double
    /// 放下後站好再停幾秒，才算播完。
    var settle: Double
    /// 手舉起的角度（度，負值往上）。
    var armUp: Double
    /// 頭歪的角度（度，負值往畫面左）。
    var headTilt: Double
    /// 揮手上下各幾度。
    var waveDegrees: Double
    /// 每秒揮幾下。
    var waveHz: Double
    /// 舉手時身體高度縮到多少（1 是不縮）。
    var squash: Double

    /// 作者 2026-11-07 定案的哈囉：舉手 0.35 秒、揮 1.4 秒（上下各 8 度，每秒 4 下）、放下 0.35 秒、站好停 0.7 秒；
    /// 頭往左歪 9 度，身體高度縮到 94%。沒有角色包的替身與灰色剪影用這一份。
    static let standard = HelloMotion(raise: 0.35, wave: 1.4, lower: 0.35, settle: 0.7,
                                      armUp: -140, headTilt: -9, waveDegrees: 8, waveHz: 4, squash: 0.94)

    /// 秒，含最後站好的停頓。
    var duration: Double { raise + wave + lower + settle }

    /// 播放用的動作。
    var motion: Motion {
        let hello = self
        return Motion(name: "hello", duration: duration, poseAt: { hello.pose(at: $0) })
    }

    /// 第 t 秒的姿勢；播完之後是站好。算式的順序和 JS 相同，讓浮點結果相同。
    func pose(at t: Double) -> RigPose {
        let waveEnd = raise + wave
        let lowerEnd = waveEnd + lower
        if t < raise {
            let k = Self.smooth(t / raise)
            return RigPose(headDegrees: headTilt * k, armDegrees: armUp * k, squash: 1 - (1 - squash) * k)
        }
        if t < waveEnd {
            let arm = armUp + sin((t - raise) * 2 * Double.pi * waveHz) * waveDegrees
            return RigPose(headDegrees: headTilt, armDegrees: arm, squash: squash)
        }
        if t < lowerEnd {
            let k = Self.smooth((t - waveEnd) / lower)
            return RigPose(headDegrees: headTilt * (1 - k), armDegrees: armUp * (1 - k), squash: squash + (1 - squash) * k)
        }
        return .rest
    }

    /// 數字合不合理；不合理時回傳哪個欄位。
    func problem() -> String? {
        if !(raise > 0) { return "hello.raise" }
        if !(lower > 0) { return "hello.lower" }
        if !(wave >= 0) { return "hello.wave" }
        if !(settle >= 0) { return "hello.settle" }
        if !(waveHz >= 0) { return "hello.waveHz" }
        if !(squash > 0) { return "hello.squash" }
        if ![armUp, headTilt, waveDegrees].allSatisfy(\.isFinite) { return "hello" }
        return nil
    }

    private static func smooth(_ t: Double) -> Double {
        let t = max(0, min(1, t))
        return t * t * (3 - 2 * t)
    }
}
