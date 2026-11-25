/// 閒晃：沒人碰時接下來做什麼（遊戲設計的「閒晃走動」與「發呆」）。每隻角色一個。
///
/// 依 `WanderConfig` 的權重挑一種活動，冷卻中的先不挑，再拆成一步步交給狀態機：走去某一格、站著幾秒。不分物種。
/// 一種活動的步驟用完才挑下一種；被主人打斷（哈囉）後接著做剩下的步驟。
/// 別隻角色在哪由外面給：不挑牠們的格子當目的地或半路停的地方，「走去黏著另一隻」走到牠們旁邊（A1 第 12 項）。
/// 打瞌睡（作者 2026-11-20 決定）：挑新的活動前，睏意（外面給）超過 `sleepiness.doze.above` 時有一定的機率改成打瞌睡
/// （越睏機率越高，見 `WanderConfig.SleepinessConfig.Doze.chance(at:)`）；
/// 醒來後 `cooldown` 秒內不再打瞌睡。
/// 去床上睡（ADR 0011）：先看要不要睡覺（`sleepiness.sleep`），要的話挑離牠近的空床位（外面給），走到床邊再上床；
/// 走到了床位卻被別隻先佔走，改去另一個空的（`retryBed`）。沒有空的床位就不去，照樣看要不要打瞌睡。
/// 不碰畫面；時間（秒）與亂數由外面給，所以可以用固定的亂數測。
nonisolated struct WanderRoutine: Sendable {
    /// 交給狀態機的一步。
    enum Step: Equatable, Sendable {
        case move(to: Tile, pace: CharacterBehavior.Pace)
        case stand(facing: Facing?, seconds: Double)
        /// 原地坐下打瞌睡，什麼時候醒由模擬照睏意決定。
        case doze
        /// 上床睡：站在床邊了，用哪個床位由模擬決定，什麼時候醒由模擬照睏意決定。
        case sleep

        /// 這一步要給狀態機的輸入。
        var request: CharacterBehavior.Input {
            switch self {
            case .move(let tile, let pace): .moveRequested(to: tile, pace: pace)
            case .stand(let facing, let seconds): .standRequested(facing: facing, seconds: seconds)
            case .doze: .dozeRequested
            case .sleep: .sleepRequested
            }
        }
    }

    /// 停下來之後至少還要走幾步，才值得在半路停：停完只走一步就到，看起來像卡住。
    static let minimumStepsAfterBreak = 2

    let config: WanderConfig
    let room: RoomLayout
    /// 這次活動還沒做的步驟。
    private(set) var plan: [Step] = []
    /// 每種活動上次開始的時間（秒），算冷卻用。
    private var lastStarted: [String: Double] = [:]
    /// 正在做（或剛做完）的活動 id；還沒開始是 nil。打瞌睡是 `doze`、去床上睡是 `sleep`。
    private(set) var activity: String?
    /// 上次打瞌睡、睡覺醒來的時間（秒），算冷卻用。
    private var lastDozeEnded = -Double.infinity
    private var lastSleepEnded = -Double.infinity

    init(config: WanderConfig, room: RoomLayout) {
        self.config = config
        self.room = room
    }

    /// 下一步。這次活動的步驟用完時挑新的活動；`here` 是角色現在站的格子，`now` 是現在的時間（秒）。
    /// `others` 是台上別隻的格子（正在走的話是牠要去的那一格）。`sleepiness` 是現在的睏意；
    /// nil 時不會打瞌睡（例如這隻沒有打瞌睡的動作）。`freeSlots` 是空的床位；空的時不會去床上睡（例如這隻沒有睡覺的動作）。
    /// 什麼都做不了時是 nil（例如資料裡的活動在這個房間都走不到）。
    mutating func next(from here: Tile, others: Set<Tile> = [], now: Double, sleepiness: Double? = nil,
                       freeSlots: [FurnitureSlotID] = [], using rng: inout some RandomNumberGenerator) -> Step? {
        if plan.isEmpty, !freeSlots.isEmpty,
           wants(config.sleepiness?.sleep, sleepiness, lastEnded: lastSleepEnded, now: now, using: &rng) {
            plan = stepsToBed(from: here, others: others, freeSlots: freeSlots, using: &rng)
            if !plan.isEmpty { activity = "sleep" }
        }
        if plan.isEmpty, wants(config.sleepiness?.doze, sleepiness, lastEnded: lastDozeEnded, now: now, using: &rng) {
            activity = "doze"
            return .doze
        }
        if plan.isEmpty { plan = start(from: here, others: others, now: now, using: &rng) }
        return plan.isEmpty ? nil : plan.removeFirst()
    }

    /// 要上床的那一步做不了（不在床邊，或床位被別隻先佔走）：改去另一個空的床位。沒有空的、走不到時放棄，是 nil。
    mutating func retryBed(from here: Tile, others: Set<Tile>, freeSlots: [FurnitureSlotID],
                           using rng: inout some RandomNumberGenerator) -> Step? {
        plan = stepsToBed(from: here, others: others, freeSlots: freeSlots, using: &rng)
        return plan.isEmpty ? nil : plan.removeFirst()
    }

    /// 打瞌睡醒來了（自己醒或被點醒）：從現在起算冷卻。
    mutating func dozeEnded(at now: Double) {
        lastDozeEnded = now
    }

    /// 睡覺醒來了（睡飽或被點醒）：從現在起算冷卻。
    mutating func sleepEnded(at now: Double) {
        lastSleepEnded = now
    }

    /// 睏意夠高、冷卻好了，再擲一次機率。
    private func wants(_ rest: WanderConfig.SleepinessConfig.Rest?, _ sleepiness: Double?, lastEnded: Double, now: Double,
                       using rng: inout some RandomNumberGenerator) -> Bool {
        guard let rest, let sleepiness, sleepiness >= rest.above, now - lastEnded >= rest.cooldown else { return false }
        return Double.random(in: 0..<1, using: &rng) < rest.chance(at: sleepiness)
    }

    /// 走到最近的空床位的床邊，再上床。每個床位用第一個走得到、沒被別隻佔住的格子；一樣近時隨機挑。
    private func stepsToBed(from here: Tile, others: Set<Tile>, freeSlots: [FurnitureSlotID],
                            using rng: inout some RandomNumberGenerator) -> [Step] {
        let counts = room.stepCounts(from: here)
        let entries = freeSlots.compactMap { id in
            room.slot(id).entries.first { counts[$0] != nil && !others.contains($0) }
        }
        guard let nearest = entries.compactMap({ counts[$0] }).min(),
              let entry = entries.filter({ counts[$0] == nearest }).randomElement(using: &rng) else { return [] }
        return walk(from: here, to: entry, others: others, using: &rng) + [.sleep]
    }

    // MARK: - 挑活動

    /// 挑一種活動、排好步驟。先從冷卻好的挑；全部在冷卻時，才從冷卻中的挑（不讓牠呆站著沒事做）。
    /// 挑到的在這裡做不了（例如走不到、台上沒有別隻可以黏）就換一個。
    private mutating func start(from here: Tile, others: Set<Tile>, now: Double,
                                using rng: inout some RandomNumberGenerator) -> [Step] {
        let counts = room.stepCounts(from: here)
        let candidates = config.activities.filter { $0.weight > 0 }
        let ready = candidates.filter { now - (lastStarted[$0.id] ?? -.infinity) >= $0.cooldown }
        let cooling = candidates.filter { !ready.contains($0) }
        for var pool in [ready, cooling] {
            while let chosen = Self.pick(pool, weight: \.weight, using: &rng) {
                let steps = steps(for: chosen, from: here, others: others, counts: counts, using: &rng)
                if !steps.isEmpty {
                    lastStarted[chosen.id] = now
                    activity = chosen.id
                    return steps
                }
                pool.removeAll { $0.id == chosen.id }
            }
        }
        return []
    }

    /// 依權重挑一個；全部是 0 或沒有東西時是 nil。
    static func pick<T>(_ items: [T], weight: (T) -> Double, using rng: inout some RandomNumberGenerator) -> T? {
        let total = items.reduce(0) { $0 + max(0, weight($1)) }
        guard total > 0 else { return nil }
        var roll = Double.random(in: 0..<total, using: &rng)
        for item in items {
            let w = max(0, weight(item))
            if roll < w { return item }
            roll -= w
        }
        return items.last { weight($0) > 0 }
    }

    // MARK: - 排步驟

    /// 一種活動在這裡的步驟；做不了時是空的。`counts` 是從這裡走到每一格要幾步。
    private func steps(for activity: WanderConfig.Activity, from here: Tile, others: Set<Tile>, counts: [Tile: Int],
                       using rng: inout some RandomNumberGenerator) -> [Step] {
        switch activity.kind {
        case .visit:
            guard let target = activity.target else { return [] }
            let spots = room.spots(beside: target).filter { counts[$0.tile] != nil && !others.contains($0.tile) }
            guard let spot = spots.randomElement(using: &rng) else { return [] }
            let walking = walk(from: here, to: spot.tile, others: others, using: &rng)
            return walking + [.stand(facing: spot.facing, seconds: Double.random(in: activity.seconds, using: &rng))]
        case .stroll:
            guard let range = activity.tiles else { return [] }
            // 字典的順序每次執行都不同，排好再挑，固定的亂數才會挑到同一格
            let tiles = counts.filter { range.contains($0.value) && !others.contains($0.key) }.keys
                .sorted { ($0.i, $0.j) < ($1.i, $1.j) }
            guard let goal = tiles.randomElement(using: &rng) else { return [] }
            let walking = walk(from: here, to: goal, others: others, using: &rng)
            return walking + [.stand(facing: nil, seconds: Double.random(in: activity.seconds, using: &rng))]
        case .stayClose:
            // 別隻旁邊緊鄰、走得到、沒被佔住的格子，挑最近的（一樣近時隨機），走過去面向牠
            let spots = others.sorted { ($0.i, $0.j) < ($1.i, $1.j) }
                .flatMap { room.spots(around: $0) }
                .filter { counts[$0.tile] != nil && !others.contains($0.tile) }
            guard let nearest = spots.compactMap({ counts[$0.tile] }).min(),
                  let spot = spots.filter({ counts[$0.tile] == nearest }).randomElement(using: &rng) else { return [] }
            let walking = walk(from: here, to: spot.tile, others: others, using: &rng)
            return walking + [.stand(facing: spot.facing, seconds: Double.random(in: activity.seconds, using: &rng))]
        case .zoneOut:
            return [.stand(facing: activity.facing, seconds: Double.random(in: activity.seconds, using: &rng))]
        case .lookAround:
            guard let range = activity.glances else { return [] }
            var steps: [Step] = []
            var last: Facing?
            for _ in 0..<Int.random(in: range, using: &rng) {
                // 連續兩眼看不同方向
                guard let facing = config.glanceFacings.filter({ $0 != last }).randomElement(using: &rng) else { break }
                steps.append(.stand(facing: facing, seconds: Double.random(in: activity.seconds, using: &rng)))
                last = facing
            }
            return steps
        }
    }

    /// 走到 `goal` 的步驟：整段用同一種快慢；路長時每走幾步停一下（`breaks`），停的點剛好是別隻的格子時不停。
    /// 已經在那裡時是空的。停的點取在找路找到的路上，模擬從那裡再找路，走的步數不變。
    private func walk(from here: Tile, to goal: Tile, others: Set<Tile>,
                      using rng: inout some RandomNumberGenerator) -> [Step] {
        guard goal != here, let path = RoomPath.find(in: room, from: here, to: goal) else { return [] }
        let pace: CharacterBehavior.Pace = Self.pick([CharacterBehavior.Pace.slow, .fast], weight: {
            $0 == .slow ? config.pace.slow : config.pace.fast
        }, using: &rng) ?? .slow
        var steps: [Step] = []
        if let breaks = config.breaks {
            var at = 0
            while true {
                let next = at + Int.random(in: breaks.everyTiles, using: &rng)
                guard path.steps - next >= Self.minimumStepsAfterBreak else { break }
                let seconds = Double.random(in: breaks.seconds, using: &rng)
                if !others.contains(path.tiles[next]) {
                    steps.append(.move(to: path.tiles[next], pace: pace))
                    steps.append(.stand(facing: nil, seconds: seconds))
                }
                at = next
            }
        }
        return steps + [.move(to: goal, pace: pace)]
    }
}
