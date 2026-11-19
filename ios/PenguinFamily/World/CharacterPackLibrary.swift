import Foundation
import os

/// 找出 App 裡的角色包。
///
/// 角色包放在 `CharacterPacks.bundle/<角色>/rig.json`，不進 git；乾淨 clone 下來沒有角色包，這時回傳空的結果，
/// 畫面改顯示占位圖形。角色 id 只從資料夾讀，不寫在程式裡（角色名稱只能出現在私有 repo）。
/// 載入好的一隻角色。
nonisolated struct LoadedCharacter: Sendable {
    /// 角色包的資料夾名稱，可能帶有角色名稱：只在執行時使用、存在手機上，不寫進程式或日誌。
    let id: String
    /// 跟著互動即時變化的姿勢用這個當場合成。
    let compositor: RigCompositor
    /// 預先算好的站好與每個動作的每一格（像素）。
    let frames: CharacterFrames
    /// 向量造型（ADR 0007）：角色包有 `vector.json` 時才有，正面用它畫。
    let vector: VectorRig?
}

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

    static func load(_ pack: URL) throws -> LoadedCharacter {
        let data = try Data(contentsOf: pack.appending(path: "rig.json"))
        let compositor = try RigCompositor(rig: JSONDecoder().decode(CharacterRig.self, from: data))
        let oblique = try ObliqueCompositor(rig: compositor.rig)
        // 有向量造型就一起載入；檔案壞掉時和 rig.json 壞掉一樣，整個角色包不用
        let vectorFile = pack.appending(path: "vector.json")
        let vector = FileManager.default.fileExists(atPath: vectorFile.path)
            ? try VectorRig.decode(Data(contentsOf: vectorFile)) : nil
        return LoadedCharacter(id: pack.lastPathComponent, compositor: compositor,
                               frames: CharacterFrames(compositor: compositor, oblique: oblique), vector: vector)
    }

    /// 一家有幾隻企鵝。
    static let familySize = 2

    /// 一家的每一隻，依角色包資料夾名稱排序：角色包不夠時，缺的位置是 nil（顯示灰色剪影）；多的角色包不用。
    static func loadFamily(in root: URL? = bundledRoot) -> [LoadedCharacter?] {
        var family: [LoadedCharacter?] = []
        for pack in packs(in: root) where family.count < familySize {
            do {
                family.append(try load(pack))
            } catch {
                // 錯誤內容可能含檔案路徑（帶角色 id），系統日誌預設遮蔽
                log.error("角色包載入失敗：\(String(describing: error), privacy: .private)")
            }
        }
        return family + Array(repeating: nil, count: familySize - family.count)
    }

    /// 在背景載入一家（含預先算好每一格），不卡住畫面。
    static func loadFamilyInBackground(in root: URL? = bundledRoot) async -> [LoadedCharacter?] {
        await Task.detached(priority: .userInitiated) { loadFamily(in: root) }.value
    }

    /// 載入第一隻能用的角色；全部壞掉或沒有角色包時回傳 nil。
    static func loadFirst(in root: URL? = bundledRoot) -> LoadedCharacter? {
        for pack in packs(in: root) {
            do {
                return try load(pack)
            } catch {
                // 錯誤內容可能含檔案路徑（帶角色 id），系統日誌預設遮蔽
                log.error("角色包載入失敗：\(String(describing: error), privacy: .private)")
            }
        }
        return nil
    }
}
