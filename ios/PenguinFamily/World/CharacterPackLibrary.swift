import Foundation
import os

/// 載入好的一隻角色：造型、動作、閒晃與點一下的反應，都是牠自己的一份（作者 2026-11-19 決定每隻各自獨立）。
nonisolated struct LoadedCharacter: Sendable {
    /// 角色包的資料夾名稱，可能帶有角色名稱：只在執行時使用、存在手機上，不寫進程式或日誌。
    let id: String
    /// 向量造型（ADR 0007）。
    let vector: VectorRig
    /// 動作資料（`motion.json`，ADR 0009）；沒帶、讀不懂或片段對不上造型時是 nil（照預設的速度移動、不動手腳）。
    var motions: CharacterMotions? = nil
    /// 閒晃的資料（`wander.json`）；角色包沒帶或壞掉時是 nil，改用 App 裡的預設。
    var wander: WanderConfig? = nil
    /// 點一下的反應（`interactions.json`，A1 第 14 項）；角色包沒帶或壞掉時是 nil，改用 App 裡的預設。
    var interactions: InteractionConfig? = nil
}

/// 名單上的一隻（ADR 0009）：身分、物種，與牠的角色包（沒有或壞掉時是 nil，畫面上是替身）。
nonisolated struct FamilyMember: Sendable {
    let id: CharacterID
    let species: Species
    var character: LoadedCharacter?
}

/// 找出 App 裡的角色包，照名單載入一家。
///
/// 一隻的角色包是 `CharacterPacks.bundle/<角色>/` 底下的 `vector.json`（造型，一定要有）、`motion.json`（動作）、
/// `wander.json`（閒晃）、`interactions.json`（點一下的反應），都由私有素材 repo 匯出、不進 git。乾淨 clone 下來沒有角色包，這時一家是預設名單的灰色剪影。
/// 角色 id 只從名單與資料夾讀，不寫在程式裡（角色名稱只能出現在私有 repo）。
nonisolated enum CharacterPackLibrary {
    private static let log = Logger(subsystem: "PenguinFamily", category: "CharacterPack")

    /// App 內角色包的根目錄；沒有就是 nil。
    static var bundledRoot: URL? {
        Bundle.main.url(forResource: "CharacterPacks", withExtension: "bundle")
    }

    /// 名單寫在根目錄的這個檔，由私有素材 repo 匯出（ADR 0009）：
    /// `{ "version": 2, "members": [{ "id": 角色資料夾名稱, "species": "penguin" }, ...] }`。
    /// 一家有幾隻、誰是第一隻（排第一的，鏡頭優先看牠）、每隻是什麼動物都由它決定；角色 id 寫在這個不進 git 的檔裡。
    /// 第 1 版 `{ "version": 1, "order": [角色資料夾名稱, ...] }` 也讀得懂，每隻當作企鵝。
    static let familyFile = "family.json"

    /// 沒有名單或名單壞掉時的一家：兩隻企鵝的位置（A1 的一家）。依名稱把角色包填進去，填不滿的是灰色剪影。
    static let defaultFamily: [Species] = [.penguin, .penguin]

    /// 名單上的一隻：角色資料夾名稱與物種。
    struct RosterEntry: Equatable, Sendable {
        let id: String
        let species: Species
    }

    private struct FamilyFile: Decodable {
        struct Member: Decodable {
            let id: String
            let species: Species
        }

        let version: Int
        let order: [String]?
        let members: [Member]?
    }

    /// 名單；沒有這個檔是 nil。格式不對（壞掉、版本不認得、id 有重複或是空的）時記下來，也當作沒有名單。
    static func roster(in root: URL) -> [RosterEntry]? {
        guard let data = try? Data(contentsOf: root.appending(path: familyFile)) else { return nil }
        guard let file = try? JSONDecoder().decode(FamilyFile.self, from: data) else {
            log.error("名單讀不懂，改用預設的一家")
            return nil
        }
        let entries: [RosterEntry]? = switch (file.version, file.order, file.members) {
        case (1, let order?, _): order.map { RosterEntry(id: $0, species: .penguin) }
        case (2, _, let members?): members.map { RosterEntry(id: $0.id, species: $0.species) }
        default: nil
        }
        // id 是資料夾名稱：不能是空的，也不能帶路徑
        guard let entries, !entries.isEmpty,
              entries.allSatisfy({ !$0.id.isEmpty && !$0.id.contains("/") && $0.id != ".." && !$0.species.rawValue.isEmpty }),
              Set(entries.map(\.id)).count == entries.count
        else {
            log.error("名單的格式不對，改用預設的一家")
            return nil
        }
        return entries
    }

    /// 根目錄底下有 `vector.json` 的角色資料夾：名單列到的排前面、照名單的順序，
    /// 沒列到的接在後面依名稱排。沒有名單或名單壞掉時全部依名稱排。
    static func packs(in root: URL?) -> [URL] {
        guard let root,
              let dirs = try? FileManager.default.contentsOfDirectory(
                at: root, includingPropertiesForKeys: nil, options: .skipsHiddenFiles)
        else { return [] }
        let order = roster(in: root)?.map(\.id) ?? []
        let rank = { (dir: URL) in (order.firstIndex(of: dir.lastPathComponent) ?? order.count, dir.lastPathComponent) }
        return dirs
            .filter { FileManager.default.fileExists(atPath: $0.appending(path: "vector.json").path) }
            .sorted { rank($0) < rank($1) }
    }

    /// 讀一隻的角色包。造型壞掉就丟錯（整個角色包不用）；動作、閒晃、點一下的反應沒帶或壞掉時記下來，那一份是 nil，牠照樣上台。
    /// 動作的片段要對得上造型（用到的方向與部件造型裡都有），對不上也當作沒帶。
    static func load(_ pack: URL) throws -> LoadedCharacter {
        let vector = try VectorRig.decode(Data(contentsOf: pack.appending(path: "vector.json")))
        var motions = optional(pack, "motion.json", CharacterMotions.decode)
        if let problem = motions?.problem(with: vector) {
            log.error("角色包的 motion.json 對不上造型：\(problem, privacy: .private)")
            motions = nil
        }
        return LoadedCharacter(id: pack.lastPathComponent, vector: vector, motions: motions,
                               wander: optional(pack, "wander.json", WanderConfig.decode),
                               interactions: optional(pack, "interactions.json", InteractionConfig.decode))
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

    /// 讀角色包；沒有 `vector.json` 是 nil，壞掉時記下來，也是 nil。
    private static func loadIfPresent(_ pack: URL) -> LoadedCharacter? {
        guard FileManager.default.fileExists(atPath: pack.appending(path: "vector.json").path) else { return nil }
        do {
            return try load(pack)
        } catch {
            // 錯誤內容可能含檔案路徑（帶角色 id），系統日誌預設遮蔽
            log.error("角色包載入失敗：\(String(describing: error), privacy: .private)")
            return nil
        }
    }

    /// 一家的每一隻，照名單的順序（第一個是第一隻）。名單上有、角色包沒有或壞掉：那一隻照樣在，角色包是 nil（畫面上是替身）；
    /// 名單沒列的角色包不用。沒有名單時是預設的一家（`defaultFamily`），依名稱把讀得進來的角色包填進去，
    /// 填不滿的位置身分是 `placeholder-<第幾隻>`。
    static func loadFamily(in root: URL? = bundledRoot) -> [FamilyMember] {
        if let root, let roster = roster(in: root) {
            return roster.map { entry in
                FamilyMember(id: CharacterID(entry.id), species: entry.species,
                             character: loadIfPresent(root.appending(path: entry.id)))
            }
        }
        let loaded = Array(packs(in: root).lazy.compactMap(loadIfPresent).prefix(defaultFamily.count))
        return defaultFamily.enumerated().map { index, species in
            let character = index < loaded.count ? loaded[index] : nil
            return FamilyMember(id: CharacterID(character?.id ?? "placeholder-\(index + 1)"), species: species,
                                character: character)
        }
    }

    /// 在背景載入一家，不卡住畫面。
    static func loadFamilyInBackground(in root: URL? = bundledRoot) async -> [FamilyMember] {
        await Task.detached(priority: .userInitiated) { loadFamily(in: root) }.value
    }
}
