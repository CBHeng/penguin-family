import Foundation

/// 角色面向哪裡：正面（面向鏡頭），或沿格線走的斜向四個方向（遊戲設計的「企鵝的方向」）。不分物種。
/// 名稱和角色包 `vector.json`、`motion.json` 的方向名稱相同，閒晃的資料（`wander.json`）也用這些名稱。
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

    /// 背對主人（看不到臉）：左後、右後。點一下時背對的一律嚇一跳（作者 2026-11-27 決定）。
    var facesAway: Bool { self == .backLeft || self == .backRight }
}
