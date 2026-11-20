/// 一隻角色的身分：模擬、畫面準備、點擊、事件紀錄都用它認是哪一隻。
///
/// 作者 2026-11-17 決定：用固定身分讓角色上台、下台，不用「陣列的第幾個」；
/// 台上有誰會變（例如之後屋內與庭院之間進出），用編號會對錯隻。
/// 不用 enum 列出角色：角色 id 來自私有素材 repo 的資料夾名稱，不能寫進公開的程式。
/// 不分物種（ADR 0009）：企鵝、鯊魚都用它。
nonisolated struct CharacterID: Hashable, Sendable {
    /// 名單（`family.json`）上的 id，也就是角色包的資料夾名稱（可能帶有角色名稱：只在執行時使用、存在手機上，
    /// 不寫進程式或日誌）。沒有名單時，沒填到角色包的位置是 `placeholder-<第幾隻>`。
    let rawValue: String

    init(_ rawValue: String) {
        self.rawValue = rawValue
    }
}

/// 物種：企鵝、鯊魚等（ADR 0009）。名稱寫在名單（`family.json`），不是 enum：加一種動物不用改程式。
/// 同物種的角色可以互借造型當替身。
nonisolated struct Species: Hashable, Sendable, Decodable {
    let rawValue: String

    init(_ rawValue: String) {
        self.rawValue = rawValue
    }

    init(from decoder: Decoder) throws {
        rawValue = try decoder.singleValueContainer().decode(String.self)
    }

    /// 名單第 1 版（只有順序）與沒有名單時，每隻都是企鵝。
    static let penguin = Species("penguin")
}
