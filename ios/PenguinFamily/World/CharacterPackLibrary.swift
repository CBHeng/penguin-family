import Foundation
import os

/// 載入好的一隻角色：造型、動作細節與閒晃，都是牠自己的一份（作者 2026-11-19 決定兩隻各自獨立）。
nonisolated struct LoadedCharacter: Sendable {
    /// 角色包的資料夾名稱，可能帶有角色名稱：只在執行時使用、存在手機上，不寫進程式或日誌。
    let id: String
    /// 向量造型（ADR 0007）。
    let vector: VectorRig
    /// 各狀態怎麼動（`motion.json`）；角色包沒帶或壞掉時是作者定案的那一份。
    var motions: PenguinMotions = .standard
    /// 閒晃的資料（`wander.json`）；角色包沒帶或壞掉時是 nil，改用 App 裡的預設。
    var wander: WanderConfig? = nil
}

/// 找出 App 裡的角色包。
///
/// 一隻的角色包是 `CharacterPacks.bundle/<角色>/` 底下的 `vector.json`（造型，一定要有）、`motion.json`（動作細節）、
/// `wander.json`（閒晃），都由私有素材 repo 匯出、不進 git。乾淨 clone 下來沒有角色包，這時回傳空的結果，
/// 畫面改顯示灰色剪影（`VectorRig.placeholder`）。角色 id 只從資料夾讀，不寫在程式裡（角色名稱只能出現在私有 repo）。
nonisolated enum CharacterPackLibrary {
    private static let log = Logger(subsystem: "PenguinFamily", category: "CharacterPack")

    /// App 內角色包的根目錄；沒有就是 nil。
    static var bundledRoot: URL? {
        Bundle.main.url(forResource: "CharacterPacks", withExtension: "bundle")
    }

    /// 一家的順序寫在根目錄的這個檔（`{ "version": 1, "order": [角色資料夾名稱, ...] }`），由私有素材 repo 匯出。
    /// 排第一的是第一隻（鏡頭優先看牠）。角色 id 寫在這個不進 git 的檔裡，程式不用知道。
    static let familyFile = "family.json"

    private struct FamilyOrder: Decodable {
        let version: Int
        let order: [String]
    }

    /// 根目錄底下有 `vector.json` 的角色資料夾：`family.json` 列到的排前面、照清單的順序，
    /// 沒列到的接在後面依名稱排。沒有清單或清單壞掉時全部依名稱排。
    static func packs(in root: URL?) -> [URL] {
        guard let root,
              let dirs = try? FileManager.default.contentsOfDirectory(
                at: root, includingPropertiesForKeys: nil, options: .skipsHiddenFiles)
        else { return [] }
        let order = familyOrder(in: root)
        let rank = { (dir: URL) in (order.firstIndex(of: dir.lastPathComponent) ?? order.count, dir.lastPathComponent) }
        return dirs
            .filter { FileManager.default.fileExists(atPath: $0.appending(path: "vector.json").path) }
            .sorted { rank($0) < rank($1) }
    }

    /// `family.json` 的順序；沒有這個檔是空的。格式不對（壞掉、版本不認得、有重複）時記下來，當作沒有清單。
    static func familyOrder(in root: URL) -> [String] {
        guard let data = try? Data(contentsOf: root.appending(path: familyFile)) else { return [] }
        guard let file = try? JSONDecoder().decode(FamilyOrder.self, from: data),
              file.version == 1, Set(file.order).count == file.order.count
        else {
            log.error("一家的順序讀不懂，改依名稱排")
            return []
        }
        return file.order
    }

    /// 讀一隻的角色包。造型壞掉就丟錯（整個角色包不用）；動作細節、閒晃沒帶或壞掉時記下來，改用預設，牠照樣上台。
    static func load(_ pack: URL) throws -> LoadedCharacter {
        let vector = try VectorRig.decode(Data(contentsOf: pack.appending(path: "vector.json")))
        return LoadedCharacter(id: pack.lastPathComponent, vector: vector,
                               motions: optional(pack, "motion.json", PenguinMotions.decode) ?? .standard,
                               wander: optional(pack, "wander.json", WanderConfig.decode))
    }

    /// 角色包裡可以不帶的檔：沒有是 nil；讀不懂也是 nil，並記下來（錯誤內容可能含角色 id，系統日誌預設遮蔽）。
    private static func optional<T>(_ pack: URL, _ file: String, _ decode: (Data) throws -> T) -> T? {
        guard let data = try? Data(contentsOf: pack.appending(path: file)) else { return nil }
        do {
            return try decode(data)
        } catch {
            log.error("角色包的 \(file, privacy: .public) 讀不懂，改用預設：\(String(describing: error), privacy: .private)")
            return nil
        }
    }

    /// 一家有幾隻企鵝。
    static let familySize = 2

    /// 一家的每一隻，照 `packs(in:)` 的順序（第一個是第一隻）：角色包不夠時，缺的位置是 nil（舞台換成替身或灰色剪影）；
    /// 多的角色包不用。
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

    /// 在背景載入一家，不卡住畫面。
    static func loadFamilyInBackground(in root: URL? = bundledRoot) async -> [LoadedCharacter?] {
        await Task.detached(priority: .userInitiated) { loadFamily(in: root) }.value
    }
}
