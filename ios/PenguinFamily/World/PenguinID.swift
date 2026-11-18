/// 一隻企鵝的身分：舞台、點擊、動作播完、事件紀錄都用它認是哪一隻。
///
/// 作者 2026-11-17 決定：舞台用固定身分加入、移除企鵝，不用「陣列的第幾個」；
/// 台上有誰會變（寫移動時第二隻先藏起來、之後屋內與庭院之間進出），用編號會對錯隻。
/// 不用 enum 列出角色：角色 id 來自私有素材 repo 的資料夾名稱，不能寫進公開的程式。
nonisolated struct PenguinID: Hashable, Sendable {
    /// 有角色包時是角色包 id（可能帶有角色名稱：只在執行時使用、存在手機上，不寫進程式或日誌）；
    /// 灰色剪影是 `placeholder-<第幾隻>`。
    let rawValue: String

    init(_ rawValue: String) {
        self.rawValue = rawValue
    }

    /// 一家第 `index` 隻（0 起算）的身分：有角色包用角色包 id，沒有就是 `placeholder-<index + 1>`，兩隻仍分得出來。
    init(character: LoadedCharacter?, index: Int) {
        self.init(character?.id ?? "placeholder-\(index + 1)")
    }
}
