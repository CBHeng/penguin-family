/// 一隻企鵝的行為狀態機：決定牠現在要做什麼，只輸出意圖，不碰畫面。
///
/// 每隻的狀態機由模擬（`Simulation`）持有：模擬依 `intent` 播放動作、站著或走路，播完、站滿交給 `.motionFinished`，
/// 走到交給 `.arrived`；動作要播多久、怎麼走過去由模擬決定，這裡不處理時間，所以可以單獨測試，換畫面技術也能沿用。
///
/// 目前的流程：
/// - 待機 →（主人點一下）→ 哈囉 →（播完）→ 待機。
/// - 待機 →（要牠走去某一格）→ 走路 →（走到）→ 待機。
/// - 待機 →（要牠站著幾秒）→ 站著 →（站滿）→ 待機；站著時被點就哈囉。
/// - 走路中被點：當場停下哈囉，播完接著走原本那段路（作者 2026-11-19 決定）。
/// 要牠走去哪、站多久由閒晃（`WanderRoutine`）決定。哈囉中再點不理（點一下的反應依權重是 A1 第 14 項）。
///
/// 狀態兩隻共用（作者 2026-11-19 決定）：每個狀態怎麼動是每隻自己的數字（`PenguinMotions`），
/// 什麼時候做什麼是每隻自己的閒晃資料（`WanderConfig`），都放在各自的角色包，這裡不分是哪一隻。
nonisolated struct PenguinBehavior: Equatable, Sendable {
    /// 走路的快慢：平常慢走，偶爾小跑（遊戲設計的「走路的樣子」）。
    enum Pace: String, CaseIterable, Equatable, Sendable {
        case walk
        case trot
    }

    /// 企鵝現在要做的事，模擬照著做。
    enum Intent: Equatable, Sendable {
        case idle
        case hello
        /// 走到某一格（沿格線、繞過家具，路由模擬找）。
        case walk(to: Tile, pace: Pace)
        /// 站在原地幾秒：發呆、東張西望的一眼、在窗邊看外面、走幾步停一下。
        /// `facing` 是要轉向哪裡，nil 維持原本的方向。
        case stand(facing: Facing?, seconds: Double)
    }

    /// 會改變行為的事。
    enum Input: Equatable, Sendable {
        /// 主人點了企鵝一下。
        case ownerTapped
        /// 模擬回報播完目前的動作，或站滿了。
        case motionFinished
        /// 要牠走去某一格（由閒晃決定）。
        case walkRequested(to: Tile, pace: Pace)
        /// 要牠站在原地幾秒（由閒晃決定）。
        case standRequested(facing: Facing?, seconds: Double)
        /// 模擬回報走到了（到不了時停在原地，也算走完）。
        case arrived
    }

    private(set) var intent: Intent = .idle
    /// 被點打斷的那段路，哈囉播完後接著走；沒有被打斷時是 nil。
    private(set) var interruptedWalk: Intent?

    /// 處理一個輸入；意圖有改變時回傳 true，被忽略時回傳 false。
    /// 同樣的意圖連續要兩次（例如往同一個方向站兩次一樣久，中間經過待機）也是兩次改變，模擬兩次都重新開始。
    @discardableResult
    mutating func handle(_ input: Input) -> Bool {
        guard let next = transition(input) else { return false }
        // 走路被點打斷：記下這段路；哈囉播完、接回去之後就清掉
        if case .walk = intent, next == .hello {
            interruptedWalk = intent
        } else if intent == .hello {
            interruptedWalk = nil
        }
        intent = next
        return true
    }

    /// 這個輸入會讓意圖變成什麼；不理時是 nil。
    private func transition(_ input: Input) -> Intent? {
        switch (intent, input) {
        case (.idle, .ownerTapped), (.stand, .ownerTapped), (.walk, .ownerTapped):
            // 站著（發呆、東張西望）也算閒著，被點就打招呼；走路中被點當場停下打招呼
            return .hello
        case (.hello, .motionFinished):
            // 走路被打斷的話，揮完接著走
            return interruptedWalk ?? .idle
        case (.stand, .motionFinished):
            return .idle
        case (.idle, .walkRequested(let tile, let pace)):
            return .walk(to: tile, pace: pace)
        case (.idle, .standRequested(let facing, let seconds)):
            return .stand(facing: facing, seconds: seconds)
        case (.walk, .arrived):
            return .idle
        case (.hello, .ownerTapped):
            // 哈囉播放中再點不重來，揮完才能再打招呼
            return nil
        case (.hello, .walkRequested), (.walk, .walkRequested), (.stand, .walkRequested),
             (.hello, .standRequested), (.walk, .standRequested), (.stand, .standRequested):
            // 正在做別的事，做完才接下一件
            return nil
        case (_, .motionFinished), (_, .arrived):
            return nil
        }
    }
}
