import Foundation
import os

/// 不分物種的共用特效的形狀（ADR 0010）：例如 Z、鼻涕泡泡、泡泡破掉的線。
///
/// 放在公開 repo 的 `Resources/effects.json`（進 git）：這些不是玩偶的造型，不受 ADR 0004 限制，所有物種共用。
/// 每個特效的格式和造型的部件相同（`VectorRig.Part`：轉軸、顏色層），不描共用的外框；render 載入時畫成貼圖。
/// 特效怎麼動、從哪裡冒出來是每隻角色動作片段裡的特效軌道（`MotionClip.effects`），由私有素材 repo 算好匯出，
/// 這裡沒有算式。
///
/// ```
/// { "version": 1, "effects": { "z": { "pivot": { "x": 0, "y": 0 }, "silhouette": [], "layers": [...] }, ... } }
/// ```
nonisolated struct EffectLibrary: Decodable, Sendable {
    static let supportedVersion = 1

    let version: Int
    /// 特效名稱 → 形狀。名稱和片段的特效軌道對應。
    let effects: [String: VectorRig.Part]

    /// 沒有任何特效（測試，或 `effects.json` 讀不到時）。
    static let empty = EffectLibrary(version: supportedVersion, effects: [:])

    init(version: Int = supportedVersion, effects: [String: VectorRig.Part]) {
        self.version = version
        self.effects = effects
    }

    static func decode(_ data: Data) throws -> EffectLibrary {
        let library = try JSONDecoder().decode(EffectLibrary.self, from: data)
        guard library.version == supportedVersion else { throw VectorRigError.unsupportedFormat(library.version) }
        for (name, effect) in library.effects.sorted(by: { $0.key < $1.key }) { try effect.validate("effects.\(name)") }
        return library
    }

    private static let log = Logger(subsystem: "PenguinFamily", category: "Effects")

    /// App 裡的 `effects.json`。讀不到或內容不合理時是空的（看不到特效，角色照樣動）；`EffectLibraryTests` 守著這個檔案。
    static func bundled(_ bundle: Bundle = .main) -> EffectLibrary {
        do {
            guard let url = bundle.url(forResource: "effects", withExtension: "json") else {
                log.error("找不到 effects.json")
                return .empty
            }
            return try decode(Data(contentsOf: url))
        } catch {
            log.error("effects.json 讀取失敗：\(String(describing: error))")
            return .empty
        }
    }
}
