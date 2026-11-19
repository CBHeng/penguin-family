/// 一隻企鵝的行為狀態機：決定牠現在要做什麼，只輸出意圖，不碰畫面。
///
/// `World` 依 `intent` 播放動作或走路，播完回報 `.motionFinished`、走到回報 `.arrived`；
/// 動作要播多久、怎麼走過去由 `World` 決定，這裡不處理時間，所以可以單獨測試，換畫面技術也能沿用。
///
/// 目前的流程：
/// - 待機 →（主人點一下）→ 哈囉 →（播完）→ 待機。
/// - 待機 →（要牠走去某一格）→ 走路 →（走到）→ 待機。
/// 哈囉中、走路中再點都先不理（點一下的反應依權重是 A1 第 14 項）。
nonisolated struct PenguinBehavior: Equatable, Sendable {
    /// 走路的快慢：平常慢走，偶爾小跑（遊戲設計的「走路的樣子」）。
    enum Pace: Equatable, Sendable {
        case walk
        case trot
    }

    /// 企鵝現在要呈現的事，`World` 照著播放。
    enum Intent: Equatable, Sendable {
        case idle
        case hello
        /// 走到某一格（沿格線、繞過家具，路由 `World` 找）。
        case walk(to: Tile, pace: Pace)
    }

    /// 會改變行為的事。
    enum Input: Equatable, Sendable {
        /// 主人點了企鵝一下。
        case ownerTapped
        /// `World` 播完目前的動作。
        case motionFinished
        /// 要牠走去某一格（目前是試走的固定路線；第 11 項起由閒晃決定）。
        case walkRequested(to: Tile, pace: Pace)
        /// `World` 回報走到了（到不了時停在原地，也算走完）。
        case arrived
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
        case (.idle, .walkRequested(let tile, let pace)):
            intent = .walk(to: tile, pace: pace)
        case (.walk, .arrived):
            intent = .idle
        case (.hello, .ownerTapped):
            // 哈囉播放中再點不重來，揮完才能再打招呼
            return false
        case (.walk, .ownerTapped):
            // 走路中先不理；點一下的反應依權重（第 14 項）再決定
            return false
        case (.hello, .walkRequested), (.walk, .walkRequested):
            // 正在做別的事，不換目的地
            return false
        case (_, .motionFinished), (_, .arrived):
            return false
        }
        return true
    }
}
