/// 模擬每個節拍交出的快照（ADR 0008）：不能修改的值，可以跨執行緒傳；畫面準備拿最近兩份內插。
///
/// 只記「在哪、面向哪、在做什麼、從什麼時候開始」。腳底在畫面上的位置、這一格的姿勢、鏡頭、前後順序都由畫面準備算，
/// 所以這裡沒有任何畫面的東西。時間都是模擬的時間（秒，由節拍數換算）。
nonisolated struct SimulationSnapshot: Equatable, Sendable {
    /// 一隻角色在做什麼，畫面準備照這個找片段。
    enum Activity: Equatable, Sendable {
        /// 站著：待機、站著幾秒、走到後、等別隻讓路。每個部件在原位。
        case still
        /// 播意圖的動作（例如哈囉），從模擬時間 `since` 開始；片段看那一隻的 `CharacterMotions`。
        case motion(CharacterBehavior.Intent, since: Double)
        /// 播到一半停住：分段的動作（ADR 0011）停在第 `at` 秒，例如在床邊等落地的格子空出來。
        case paused(CharacterBehavior.Intent, at: Double)
        /// 移動，已經走了 `elapsed` 秒：步態的片段照這個播（等別隻讓路的時間不算）。
        case moving(CharacterBehavior.Pace, elapsed: Double)
    }

    /// 一隻角色的一個屬性（例如睏意、耐心），給介面的屬性條（作者 2026-11-27 要求）。不分物種、不寫死有哪些：
    /// 模擬照每隻的資料列出牠有的，介面照清單畫，之後加新的屬性不用改介面。
    ///
    /// 記「`since` 那一刻是 `value`、每秒變 `perSecond`」，要用時再算（和睏意、耐心本身的記法相同），
    /// 所以模擬停下來不跑節拍時，介面照樣看得到它在變。
    struct Meter: Equatable, Sendable {
        /// 門檻線：到這個值會發生什麼（例如睏意 60 打瞌睡）。
        struct Mark: Equatable, Sendable {
            let value: Double
            let label: String
        }

        /// 識別用的名稱（例如 `sleepiness`）。
        let id: String
        /// 給人看的名稱（例如「睏意」）。
        let label: String
        let range: ClosedRange<Double>
        /// `since`（模擬的秒）那一刻的值。
        let value: Double
        let since: Double
        /// 每秒變多少；超出範圍的停在兩端。
        let perSecond: Double
        let marks: [Mark]

        /// 模擬時間 `time` 那一刻的值（不超出範圍）。
        func level(at time: Double) -> Double {
            min(max(value + perSecond * (time - since), range.lowerBound), range.upperBound)
        }
    }

    /// 台上的一隻。
    struct Character: Equatable, Sendable {
        let id: CharacterID
        /// 站在地板的哪一點（格，可以有小數）。
        let position: TilePosition
        let facing: Facing
        let activity: Activity
        /// 離地多高（單位）；在地板上是 0。
        var height = 0.0
        /// 在第幾件家具上（ADR 0011，例如躺在床上、正在上下床）；在地板上是 nil。
        var support: Int? = nil
        /// 這隻有的屬性（例如睏意、耐心），依固定的順序；沒有資料的屬性不列。
        var meters: [Meter] = []
    }

    /// 第幾個節拍結束時的樣子。
    let tick: Int
    /// 台上的角色，依上台先後。
    let characters: [Character]
    /// 還有東西在動或有事件在等：模擬要繼續跑節拍。
    let isActive: Bool
    /// 沒有東西在動時，下次要醒來的模擬時間（例如某隻站滿）；沒有排定的事是 nil。
    let wakeAt: Double?

    /// 模擬的時間（秒）。
    var time: Double { Double(tick) / Double(Simulation.ticksPerSecond) }

    /// 台上的某一隻；不在台上是 nil。
    func character(_ id: CharacterID) -> Character? {
        characters.first { $0.id == id }
    }
}
