/// 名單上每一隻實際用的造型與動作，缺角色包的換成替身（作者 2026-11-19 決定；ADR 0009 依物種）。
///
/// - 有角色包：用牠自己的造型；動作沒帶或對不上造型時照預設的速度移動、不動手腳（`CharacterMotions.still`）。
/// - 沒有角色包、名單上有同物種的有：借排在最前面那隻的形狀塗灰（`VectorRig.graySilhouette()`），動作也用牠的
///   （形狀相同，片段直接用）。不借別種動物的形狀。
/// - 同物種都沒有角色包：灰色剪影（`VectorRig.placeholder`）與它的動作（`CharacterMotions.placeholder`）。
nonisolated enum StandIn {
    struct Look: Sendable {
        let vector: VectorRig
        let motions: CharacterMotions
    }

    /// 依名單的順序，每一隻一個。
    static func resolve(_ family: [FamilyMember]) -> [Look] {
        family.map { member in
            if let own = member.character {
                return Look(vector: own.vector, motions: own.motions ?? .still)
            }
            let source = family.lazy.filter { $0.species == member.species }.compactMap(\.character).first
            guard let source else { return Look(vector: .placeholder, motions: .placeholder) }
            return Look(vector: source.vector.graySilhouette(), motions: source.motions ?? .still)
        }
    }
}
