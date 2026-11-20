/// 模擬每個節拍交出的快照（ADR 0008）：不能修改的值，可以跨執行緒傳；畫面準備拿最近兩份內插。
///
/// 只記「在哪、面向哪、在做什麼、從什麼時候開始」。腳底在畫面上的位置、這一格的姿勢、鏡頭、前後順序都由畫面準備算，
/// 所以這裡沒有任何畫面的東西。時間都是模擬的時間（秒，由節拍數換算）。
nonisolated struct SimulationSnapshot: Equatable, Sendable {
    /// 一隻企鵝在做什麼，畫面準備照這個算姿勢。
    enum Activity: Equatable, Sendable {
        /// 站著：待機、站著幾秒、走到後、等別隻讓路。斜向時是站姿，正面時是站好。
        case still
        /// 播正面的動作（例如哈囉），從模擬時間 `since` 開始；動作的時間軸看那一隻的 `PenguinMotions`。
        case motion(PenguinBehavior.Intent, since: Double)
        /// 走路，已經走了 `elapsed` 秒：步態照這個算姿勢（等別隻讓路的時間不算）。
        case walking(PenguinBehavior.Pace, elapsed: Double)
    }

    /// 台上的一隻。
    struct Penguin: Equatable, Sendable {
        let id: PenguinID
        /// 站在地板的哪一點（格，可以有小數）。
        let position: TilePosition
        let facing: Facing
        let activity: Activity
    }

    /// 第幾個節拍結束時的樣子。
    let tick: Int
    /// 台上的企鵝，依上台先後。
    let penguins: [Penguin]
    /// 還有東西在動或有事件在等：模擬要繼續跑節拍。
    let isActive: Bool
    /// 沒有東西在動時，下次要醒來的模擬時間（例如某隻站滿）；沒有排定的事是 nil。
    let wakeAt: Double?

    /// 模擬的時間（秒）。
    var time: Double { Double(tick) / Double(Simulation.ticksPerSecond) }

    /// 台上的某一隻；不在台上是 nil。
    func penguin(_ id: PenguinID) -> Penguin? {
        penguins.first { $0.id == id }
    }
}
