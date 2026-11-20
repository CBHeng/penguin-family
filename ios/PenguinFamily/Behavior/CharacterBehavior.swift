/// 一隻角色的行為狀態機：決定牠現在要做什麼，只輸出意圖，不碰畫面。
///
/// 每隻的狀態機由模擬（`Simulation`）持有：模擬依 `intent` 播放動作、站著或移動，播完、站滿交給 `.motionFinished`，
/// 走到交給 `.arrived`；動作要播多久、怎麼走過去由模擬決定，這裡不處理時間，所以可以單獨測試，換畫面技術也能沿用。
///
/// 目前的流程：
/// - 待機 →（主人點一下）→ 哈囉 →（播完）→ 待機。
/// - 待機 →（要牠走去某一格）→ 移動 →（走到）→ 待機。
/// - 待機 →（要牠站著幾秒）→ 站著 →（站滿）→ 待機；站著時被點就哈囉。
/// - 移動中被點：當場停下哈囉，播完接著走原本那段路（作者 2026-11-19 決定）。
/// 要牠走去哪、站多久由閒晃（`WanderRoutine`）決定。哈囉中再點不理（點一下的反應依權重是 A1 第 14 項）。
///
/// 狀態每隻共用、不分物種（作者 2026-11-19 決定；ADR 0009）：每個狀態看起來怎麼動是每隻自己的動作資料
/// （`CharacterMotions`），什麼時候做什麼是每隻自己的閒晃資料（`WanderConfig`），都放在各自的角色包，這裡不分是哪一隻。
nonisolated struct CharacterBehavior: Equatable, Sendable {
    /// 移動的快慢：平常慢、偶爾快（遊戲設計的「走路的樣子」）。不分物種（ADR 0009）：
    /// 慢、快各用哪個步態由每隻的動作資料決定，例如企鵝是慢走、小跑。
    enum Pace: String, CaseIterable, Equatable, Sendable {
        case slow
        case fast
    }

    /// 角色現在要做的事，模擬照著做。
    enum Intent: Equatable, Sendable {
        case idle
        case hello
        /// 走到某一格（沿格線、繞過家具，路由模擬找）。
        case move(to: Tile, pace: Pace)
        /// 站在原地幾秒：發呆、東張西望的一眼、在窗邊看外面、走幾步停一下。
        /// `facing` 是要轉向哪裡，nil 維持原本的方向。
        case stand(facing: Facing?, seconds: Double)

        /// 這個意圖要播的動作（角色動作資料裡的名稱）；待機、移動、站著不播。
        /// 角色沒有這個動作時，模擬當作馬上播完。
        var motionName: String? {
            switch self {
            case .hello: "hello"
            case .idle, .move, .stand: nil
            }
        }
    }

    /// 會改變行為的事。
    enum Input: Equatable, Sendable {
        /// 主人點了角色一下。
        case ownerTapped
        /// 模擬回報播完目前的動作，或站滿了。
        case motionFinished
        /// 要牠走去某一格（由閒晃決定）。
        case moveRequested(to: Tile, pace: Pace)
        /// 要牠站在原地幾秒（由閒晃決定）。
        case standRequested(facing: Facing?, seconds: Double)
        /// 模擬回報走到了（到不了時停在原地，也算走完）。
        case arrived
    }

    private(set) var intent: Intent = .idle
    /// 被點打斷的那段路，哈囉播完後接著走；沒有被打斷時是 nil。
    private(set) var interruptedMove: Intent?

    /// 處理一個輸入；意圖有改變時回傳 true，被忽略時回傳 false。
    /// 同樣的意圖連續要兩次（例如往同一個方向站兩次一樣久，中間經過待機）也是兩次改變，模擬兩次都重新開始。
    @discardableResult
    mutating func handle(_ input: Input) -> Bool {
        guard let next = transition(input) else { return false }
        // 移動被點打斷：記下這段路；哈囉播完、接回去之後就清掉
        if case .move = intent, next == .hello {
            interruptedMove = intent
        } else if intent == .hello {
            interruptedMove = nil
        }
        intent = next
        return true
    }

    /// 這個輸入會讓意圖變成什麼；不理時是 nil。
    private func transition(_ input: Input) -> Intent? {
        switch (intent, input) {
        case (.idle, .ownerTapped), (.stand, .ownerTapped), (.move, .ownerTapped):
            // 站著（發呆、東張西望）也算閒著，被點就打招呼；移動中被點當場停下打招呼
            return .hello
        case (.hello, .motionFinished):
            // 移動被打斷的話，揮完接著走
            return interruptedMove ?? .idle
        case (.stand, .motionFinished):
            return .idle
        case (.idle, .moveRequested(let tile, let pace)):
            return .move(to: tile, pace: pace)
        case (.idle, .standRequested(let facing, let seconds)):
            return .stand(facing: facing, seconds: seconds)
        case (.move, .arrived):
            return .idle
        case (.hello, .ownerTapped):
            // 哈囉播放中再點不重來，揮完才能再打招呼
            return nil
        case (.hello, .moveRequested), (.move, .moveRequested), (.stand, .moveRequested),
             (.hello, .standRequested), (.move, .standRequested), (.stand, .standRequested):
            // 正在做別的事，做完才接下一件
            return nil
        case (_, .motionFinished), (_, .arrived):
            return nil
        }
    }
}
