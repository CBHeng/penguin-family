/// 一隻企鵝的行為狀態機：決定牠現在要做什麼，只輸出意圖，不碰畫面。
///
/// `World` 依 `intent` 播放動作，動作播完再回報 `.motionFinished`；
/// 動作要播多久由 `World` 決定，這裡不處理時間，所以可以單獨測試，換畫面技術也能沿用。
///
/// 目前只有最小流程：待機 →（主人點一下）→ 哈囉 →（播完）→ 待機。
nonisolated struct PenguinBehavior: Equatable, Sendable {
    /// 企鵝現在要呈現的事，`World` 照著播放。
    enum Intent: Equatable, Sendable {
        case idle
        case hello
    }

    /// 會改變行為的事。
    enum Input: Equatable, Sendable {
        /// 主人點了企鵝一下。
        case ownerTapped
        /// `World` 播完目前的動作。
        case motionFinished
    }

    private(set) var intent: Intent = .idle

    /// 處理一個輸入；意圖有改變時回傳 true，被忽略時回傳 false。
    @discardableResult
    mutating func handle(_ input: Input) -> Bool {
        switch (intent, input) {
        case (.idle, .ownerTapped):
            intent = .hello
        case (.hello, .motionFinished):
            intent = .idle
        case (.hello, .ownerTapped):
            // 哈囉播放中再點不重來，揮完才能再打招呼
            return false
        case (.idle, .motionFinished):
            return false
        }
        return true
    }
}
