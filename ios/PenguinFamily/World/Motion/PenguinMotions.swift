import Foundation

/// 一隻企鵝各狀態的動作細節（作者 2026-11-19 決定）：狀態（待機、站著、哈囉、走路）是兩隻共用的
/// （`PenguinBehavior.Intent`），每個狀態怎麼動每隻各一份，改一隻不影響另一隻。
///
/// 放在角色包的 `motion.json`，由私有素材 repo 的 `character.js` 匯出（角色名稱只在私有 repo）。
/// 算式（`HelloMotion.pose`、`Gait.vectorPose`）兩隻共用，和 `vector.js` 逐格比對。
/// 角色包沒帶 `motion.json` 或內容不合理時用 `standard`；沒有角色包的替身與灰色剪影也用它。
///
/// 格式：`{ "version": 1, "hello": {...}, "walk": {...}, "trot": {...} }`，欄位見 `HelloMotion` 與 `Gait`。
nonisolated struct PenguinMotions: Decodable, Equatable, Sendable {
    static let supportedVersion = 1

    var version = supportedVersion
    /// 主人點一下時的哈囉。
    var hello: HelloMotion
    /// 慢走。
    var walk: Gait
    /// 小跑。
    var trot: Gait

    /// 作者定案的那一份（哈囉 2026-11-07、步態 2026-11-17）。
    static let standard = PenguinMotions(hello: .standard, walk: .standardWalk, trot: .standardTrot)

    static func decode(_ data: Data) throws -> PenguinMotions {
        let motions = try JSONDecoder().decode(PenguinMotions.self, from: data)
        try motions.validate()
        return motions
    }

    /// 檢查數字合不合理；不合理時丟出 `PenguinMotionsError`，說明是哪個欄位。
    func validate() throws {
        guard version == Self.supportedVersion else { throw PenguinMotionsError.unsupportedVersion(version) }
        if let problem = hello.problem() ?? walk.problem("walk") ?? trot.problem("trot") {
            throw PenguinMotionsError.invalid(problem)
        }
    }

    /// 走路的快慢用哪個步態。
    func gait(for pace: PenguinBehavior.Pace) -> Gait {
        switch pace {
        case .walk: walk
        case .trot: trot
        }
    }

    /// 意圖要播哪個正面動作；待機、站著與走路不播（走路用斜向的步態）。
    func motion(for intent: PenguinBehavior.Intent) -> Motion? {
        switch intent {
        case .idle, .stand, .walk: nil
        case .hello: hello.motion
        }
    }
}

nonisolated enum PenguinMotionsError: Error, Equatable {
    case unsupportedVersion(Int)
    case invalid(String)
}
