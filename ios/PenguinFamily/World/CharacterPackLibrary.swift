import Foundation
import os

/// 找出 App 裡的角色包。
///
/// 角色包放在 `CharacterPacks.bundle/<角色>/rig.json`，不進 git；乾淨 clone 下來沒有角色包，這時回傳空的結果，
/// 畫面改顯示占位圖形。角色 id 只從資料夾讀，不寫在程式裡（角色名稱只能出現在私有 repo）。
nonisolated enum CharacterPackLibrary {
    private static let log = Logger(subsystem: "PenguinFamily", category: "CharacterPack")

    /// App 內角色包的根目錄；沒有就是 nil。
    static var bundledRoot: URL? {
        Bundle.main.url(forResource: "CharacterPacks", withExtension: "bundle")
    }

    /// 根目錄底下有 `rig.json` 的角色資料夾，依名稱排序。
    static func packs(in root: URL?) -> [URL] {
        guard let root,
              let dirs = try? FileManager.default.contentsOfDirectory(
                at: root, includingPropertiesForKeys: nil, options: .skipsHiddenFiles)
        else { return [] }
        return dirs
            .filter { FileManager.default.fileExists(atPath: $0.appending(path: "rig.json").path) }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    static func load(_ pack: URL) throws -> RigCompositor {
        let data = try Data(contentsOf: pack.appending(path: "rig.json"))
        return try RigCompositor(rig: JSONDecoder().decode(CharacterRig.self, from: data))
    }

    /// 載入第一隻能用的角色；全部壞掉或沒有角色包時回傳 nil。
    static func loadFirst(in root: URL? = bundledRoot) -> RigCompositor? {
        for pack in packs(in: root) {
            do {
                return try load(pack)
            } catch {
                log.error("角色包載入失敗：\(String(describing: error), privacy: .public)")
            }
        }
        return nil
    }
}
