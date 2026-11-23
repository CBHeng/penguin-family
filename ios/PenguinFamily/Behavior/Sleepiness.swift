/// 一隻角色的睏意（作者 2026-11-20 決定；遊戲設計的「睏意：打瞌睡與睡覺」）：0～100 的一個數值。
///
/// 醒著時隨時間增加，走路、小跑時增加得快；打瞌睡時慢慢下降（之後的睡覺降得多又快，晚上增加得快，見 TASKS）。
/// 超過門檻時，閒晃挑下一件事時有機率去打瞌睡（`WanderRoutine`）。數字每隻各一份，在牠的 `wander.json`。
///
/// 這裡只記「某個時間點是多少、現在每秒變多少」，要用時再算出現在的值，所以模擬停下來不跑節拍時也不用一直更新。
/// 不碰畫面、不讀時鐘：時間（模擬的秒）由外面給。打開 App 時從 `start` 的範圍裡隨機開始，不跨次保存
/// （離開期間怎麼補算是 A1 第 22 項）。
nonisolated struct Sleepiness: Equatable, Sendable {
    static let range = 0.0...100.0

    /// `since` 那一刻的值。
    private(set) var value: Double
    private(set) var since: Double
    /// 每秒變多少（正的是越來越睏）。
    private(set) var perSecond: Double

    init(value: Double, at time: Double, perSecond: Double = 0) {
        self.value = min(max(value, Self.range.lowerBound), Self.range.upperBound)
        since = time
        self.perSecond = perSecond
    }

    /// `time` 那一刻的值（不超出 0～100）。
    func level(at time: Double) -> Double {
        min(max(value + perSecond * (time - since), Self.range.lowerBound), Self.range.upperBound)
    }

    /// 從 `time` 起改成每秒變 `perSecond`（之前的照舊的速度算到 `time`）。
    mutating func change(perSecond rate: Double, at time: Double) {
        value = level(at: time)
        since = time
        perSecond = rate
    }

    /// 在 `time` 一下子加 `amount`（可以是負的；除錯用的「加睏意」按鈕）。
    mutating func add(_ amount: Double, at time: Double) {
        value = min(max(level(at: time) + amount, Self.range.lowerBound), Self.range.upperBound)
        since = time
    }

    /// 照現在的速度，從 `time` 起再過幾秒會降到 `target`；不會降到（沒在降、或已經比它低）時是 0。
    func secondsUntil(fallingTo target: Double, from time: Double) -> Double {
        let now = level(at: time)
        guard perSecond < 0, now > target else { return 0 }
        return (now - target) / -perSecond
    }
}
