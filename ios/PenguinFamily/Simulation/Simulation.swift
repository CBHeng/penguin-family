import Foundation

/// 模擬：唯一的世界狀態（ADR 0008）。台上每一隻角色的位置、面向、狀態機、閒晃、移動與讓路都在這裡。不分物種（ADR 0009）。
///
/// - **固定節拍**：每秒 `ticksPerSecond` 個節拍。模擬的時間就是節拍數（`time`），不讀系統時鐘、不知道螢幕更新率。
/// - **事件**：會改變世界的都是事件（`Event`），先用 `send` 排進佇列。每個節拍（`step`）：
///   開頭依序處理事件 → 推進到節拍結束（動作、站著、走路）→ 回報播完、走到，交給各自的狀態機，回到待機就問閒晃。
/// - **結果固定**：亂數放在這裡（建立時給種子）。同樣的起始狀態加上同樣的事件，一定得到同樣的結果。
/// - **交出去的都是值**：快照（`snapshot`）與輸出事件（`step` 的回傳值），可以跨執行緒傳。
/// - **不碰畫面**：腳底在畫面上的位置、姿勢、鏡頭、前後順序由畫面準備算；這裡只記「在哪、面向哪、在做什麼、從什麼時候開始」。
///
/// 每隻照自己的動作資料動（`CharacterMotions`，作者 2026-11-19 決定；ADR 0009）：一次性的動作多長、播的時候轉向哪裡、
/// 慢與快一秒走幾格都看那一隻的。角色沒有某個動作時，那個意圖馬上算播完。
///
/// 兩隻互相讓路（作者 2026-11-19 決定）：走路時要走進的下一格被別隻佔住，就停在格子中心等；
/// 等了一陣子還擋著就找一條繞開牠的路（第一隻等久一點，迎面撞上時第二隻先讓），繞不過去、等太久就停在原地算走到。
///
/// 移動中被點（作者 2026-11-19 決定）：停在當下的位置（可能在兩格之間）哈囉，揮完從停的地方沿格線接著走，不跳回格子中心。
nonisolated struct Simulation: Sendable {
    /// 每秒幾個節拍（作者 2026-11-20 決定，ADR 0008）。
    static let ticksPerSecond = 30
    /// 前面那一格被別隻擋住時，等幾秒後試著繞路：第一隻、其他隻。實機上調。
    static let detourAfter = (lead: 1.5, others: 1.0)
    /// 繞不過去（例如別隻站在目的地）時，等幾秒就放棄，停在原地算走到。實機上調。
    static let giveUpAfter: Double = 4

    /// 後台名單的一隻。名單的順序就是一家的順序，最前面的是第一隻。
    struct CastMember: Sendable {
        let id: CharacterID
        /// 這隻的動作資料（已經換好替身的，見 `StandIn`）。
        var motions: CharacterMotions = .placeholder
        /// 閒晃的資料；nil 時牠不會自己找事做，只照事件動（資料讀不到時，或測試）。
        var wander: WanderConfig? = nil
    }

    /// 會改變世界的事。
    enum Event: Equatable, Sendable {
        /// 讓後台名單裡的一隻站到某一點上台，之後問牠的閒晃要做什麼。不在名單裡或已經在台上時不做事。
        case enter(CharacterID, at: TilePosition)
        /// 下台：正在做的事直接停掉，不回報。
        case leave(CharacterID)
        /// 把台上的一隻放到某一點（之後的「拎起來」也用它）。正在走或停在半路時不做事。
        case place(CharacterID, at: TilePosition)
        /// 主人點了這一隻。`at` 是點的當下，由外面取，只用來記錄。
        case ownerTapped(CharacterID, at: Date)
        /// 直接交給這一隻的狀態機，例如要牠走去某一格。
        case input(CharacterID, CharacterBehavior.Input)
    }

    /// 這個節拍發生的事，交給外面（事件紀錄、之後的觸覺與台詞）。
    enum Output: Equatable, Sendable {
        /// 主人點了這一隻（不論牠有沒有回應都記）。
        case ownerTapped(CharacterID, at: Date)
        /// 動作播完或站滿。
        case finished(CharacterID)
        /// 走到了哪一格（到不了、等太久放棄時是停下來的那一格）。
        case arrived(CharacterID, Tile)
    }

    /// 停在兩格之間：從 `from` 往 `to` 走了 `fraction`（0～1，不含兩端）。
    struct Midway: Equatable, Sendable {
        let from: Tile
        let to: Tile
        let fraction: Double
    }

    /// 台上一隻角色。
    private struct Character: Sendable {
        let id: CharacterID
        let motions: CharacterMotions
        var behavior = CharacterBehavior()
        var wander: WanderRoutine?
        /// 站在地板的哪一點；移動時一直變。
        var position: TilePosition
        /// 面向哪裡：一開始面向鏡頭；移動時是這一段的方向，走到後維持；播動作時照動作資料轉（例如哈囉轉回正面）；站著時照意圖轉。
        var facing: Facing = .front
        /// 正在播的動作：哪個意圖、播多久、開始的模擬時間。
        var playing: (intent: CharacterBehavior.Intent, duration: Double, start: Double)?
        /// 站著要站到幾秒。
        var standUntil: Double?
        var walking: Walk?
        /// 移動被打斷時停在兩格之間；在格子中心時是 nil。
        var midway: Midway?
    }

    /// 正在走的一段路。
    private struct Walk: Sendable {
        let path: RoomPath
        let pace: CharacterBehavior.Pace
        /// 一秒走幾格（這隻這種快慢的步態）。
        let speed: Double
        /// 照速度從這個時間開始走；等別隻讓路時往後推，等的時間不算。
        var start: Double
        /// 在路上走了幾格；走過格子中心時剛好是整數。
        var distance = 0.0
        /// 前面那一格被別隻佔住、停在格子中心等的開始時間；沒在等是 nil。
        var waitingSince: Double?
        /// 等的時候，下次試著繞路的時間。
        var nextDetour: Double?

        /// 走了幾秒：步態的片段照這個播。
        var elapsed: Double { distance / speed }
    }

    let room: RoomLayout
    /// 後台名單，依一家的順序。
    private let cast: [CastMember]
    /// 已經跑完幾個節拍。
    private(set) var tick = 0
    /// 台上的角色，依上台先後。
    private var characters: [Character] = []
    /// 還沒處理的事件，依送來的順序。
    private var pending: [Event] = []
    private var rng: SeededRandom

    /// 建立時台上沒有角色；用 `.enter` 事件讓牠們上台。`seed` 是閒晃用的亂數種子。
    init(room: RoomLayout, cast: [CastMember], seed: UInt64) {
        self.room = room
        self.cast = cast
        rng = SeededRandom(seed: seed)
    }

    /// 模擬的時間（秒）。
    var time: Double { Double(tick) / Double(Self.ticksPerSecond) }

    /// 台上有誰，依上台先後。
    var onStage: [CharacterID] { characters.map(\.id) }

    /// 還有東西在動、或有事件在等：要繼續跑節拍。否則可以停下來，等事件或 `wakeAt`。
    var isActive: Bool { !pending.isEmpty || isMoving }

    /// 有角色正在播動作或移動。站著不算：畫面不動，只要到時間（`wakeAt`）再跑。
    var isMoving: Bool { characters.contains { $0.playing != nil || $0.walking != nil } }

    /// 沒有東西在動時，下次要醒來的模擬時間（最早站滿的那隻）；沒有排定的事是 nil。
    var wakeAt: Double? { characters.compactMap(\.standUntil).min() }

    /// 台上某一隻的狀態機；不在台上是 nil。
    func behavior(of id: CharacterID) -> CharacterBehavior? {
        characters.first { $0.id == id }?.behavior
    }

    /// 這個節拍結束時的樣子。
    var snapshot: SimulationSnapshot {
        SimulationSnapshot(tick: tick, characters: characters.map { character in
            SimulationSnapshot.Character(id: character.id, position: character.position, facing: character.facing,
                                         activity: Self.activity(of: character))
        }, isActive: isActive, wakeAt: wakeAt)
    }

    // MARK: - 事件與節拍

    /// 排進佇列，下一個節拍開頭處理。
    mutating func send(_ event: Event) {
        pending.append(event)
    }

    /// 跑一個節拍，回傳這個節拍發生的事。
    mutating func step() -> [Output] {
        var outputs: [Output] = []
        // 1. 節拍開頭：依序處理事件；新上台的等事件處理完再一起問閒晃，才看得到同一批上台的別隻
        let start = time
        let events = pending
        pending.removeAll()
        var entered: [CharacterID] = []
        for event in events {
            if let id = handle(event, now: start, outputs: &outputs) { entered.append(id) }
        }
        for id in entered { wander(id, now: start) }

        // 2. 推進到節拍結束
        tick += 1
        let now = time
        var finished: [CharacterID] = []
        var arrived: [(id: CharacterID, tile: Tile)] = []
        for index in characters.indices {
            if let playing = characters[index].playing, now - playing.start >= playing.duration {
                characters[index].playing = nil
                finished.append(characters[index].id)
            }
            if let until = characters[index].standUntil, now >= until {
                characters[index].standUntil = nil
                finished.append(characters[index].id)
            }
            if let tile = advanceWalk(index, now: now) { arrived.append((characters[index].id, tile)) }
        }

        // 3. 回報給各自的狀態機，回到待機就問閒晃
        for id in finished {
            outputs.append(.finished(id))
            input(id, .motionFinished, now: now)
            wander(id, now: now)
        }
        for arrival in arrived {
            outputs.append(.arrived(arrival.id, arrival.tile))
            input(arrival.id, .arrived, now: now)
            wander(arrival.id, now: now)
        }
        return outputs
    }

    /// 沒有東西在動時，直接跳到第 `newTick` 個節拍：停下來的期間不補跑節拍（ADR 0008）。有東西在動時不做事。
    /// 在等的事件留著，在跳過之後的下一個節拍生效（例如閒置很久後主人點一下，用的是現在的時間）；
    /// 站著的那隻如果在這段期間站滿了，下一個節拍就回報。
    mutating func skip(to newTick: Int) {
        guard !isMoving, newTick > tick else { return }
        tick = newTick
    }

    /// 處理一個事件；有角色上台時回傳牠。
    private mutating func handle(_ event: Event, now: Double, outputs: inout [Output]) -> CharacterID? {
        switch event {
        case .enter(let id, let position):
            guard index(of: id) == nil, let member = cast.first(where: { $0.id == id }) else { return nil }
            characters.append(Character(id: id, motions: member.motions,
                                        wander: member.wander.map { WanderRoutine(config: $0, room: room) },
                                        position: position))
            return id
        case .leave(let id):
            characters.removeAll { $0.id == id }
        case .place(let id, let position):
            guard let index = index(of: id), characters[index].walking == nil, characters[index].midway == nil else { return nil }
            characters[index].position = position
        case .ownerTapped(let id, let date):
            // 主人點了就記下，不論角色當下有沒有回應
            outputs.append(.ownerTapped(id, at: date))
            input(id, .ownerTapped, now: now)
        case .input(let id, let request):
            input(id, request, now: now)
        }
        return nil
    }

    /// 交給這一隻的狀態機；意圖變了就照新的意圖做。
    private mutating func input(_ id: CharacterID, _ request: CharacterBehavior.Input, now: Double) {
        guard let index = index(of: id), characters[index].behavior.handle(request) else { return }
        apply(index, now: now)
    }

    /// 這一隻在待機的話，問牠的閒晃下一步做什麼，交給狀態機。台上別隻的格子（正在走的話是牠要去的那一格）一起給閒晃。
    private mutating func wander(_ id: CharacterID, now: Double) {
        guard let index = index(of: id), characters[index].behavior.intent == .idle,
              var routine = characters[index].wander else { return }
        let others = Set(characters.indices.filter { $0 != index }.map { Self.whereabouts(of: characters[$0]) })
        let next = routine.next(from: Tile(containing: characters[index].position), others: others, now: now, using: &rng)
        characters[index].wander = routine
        if let next, characters[index].behavior.handle(next.request) { apply(index, now: now) }
    }

    /// 照狀態機現在的意圖做：換播對應的動作、站著，或開始移動。
    /// - 播動作（例如哈囉）：照這隻的動作資料播多久、轉向哪裡（企鵝的哈囉只有正面的圖，所以轉回正面，作者 2026-11-18 決定）。
    ///   這隻沒有這個動作時播 0 秒，下一個節拍就回報播完。
    /// - 移動：從現在的位置找路；到不了時停在原地，下一個節拍就回報走到。停在兩格之間時見 `route`。
    /// - 移動被別的意圖打斷（例如被點就哈囉）：停在當下的位置，記下停在哪兩格之間。
    /// - 站著：轉向意圖給的方向（nil 不轉），站滿後回報播完。
    /// - 待機：不換方向，走到後維持走的方向。
    private mutating func apply(_ index: Int, now: Double) {
        let intent = characters[index].behavior.intent
        if let name = intent.motionName {
            let motion = characters[index].motions.motion(named: name)
            characters[index].playing = (intent, motion?.duration ?? 0, now)
            if let turn = motion?.facing { characters[index].facing = turn }
        } else {
            characters[index].playing = nil
        }
        if let walk = characters[index].walking { characters[index].midway = Self.midway(of: walk) }
        characters[index].walking = nil
        characters[index].standUntil = nil
        switch intent {
        case .idle, .hello:
            break
        case .stand(let facing, let seconds):
            if let facing { characters[index].facing = facing }
            characters[index].standUntil = now + seconds
        case .move(let goal, let pace):
            let speed = characters[index].motions.gait(for: pace).tilesPerSecond
            let (path, walked) = Self.route(from: characters[index].position, midway: characters[index].midway, to: goal,
                                            avoiding: takenByOthers(except: index), in: room)
            // 已經走了一段（從半路出發）時，把開始的時間往前推，位置與步態都從那裡接著算
            characters[index].midway = nil
            characters[index].walking = Walk(path: path, pace: pace, speed: speed,
                                             start: now - walked / speed, distance: walked)
            moveAlong(index, distance: walked)
        }
    }

    // MARK: - 走路

    /// 推進一隻正在走的角色：位置照經過的時間前進；走到時回傳走到的那一格。
    /// 站在格子中心、要走進下一格之前，先看那一格有沒有被別隻佔住，佔住就停下來等（見 `wait`）。
    private mutating func advanceWalk(_ index: Int, now: Double) -> Tile? {
        guard var walk = characters[index].walking else { return nil }
        let tiles = walk.path.tiles
        let target = min(walk.speed * max(0, now - walk.start), Double(walk.path.steps))
        while walk.distance < target {
            let k = Int(walk.distance.rounded(.down))
            if Double(k) == walk.distance, isTaken(tiles[k + 1], except: index) {
                return wait(index, walk, now: now)
            }
            walk.distance = min(target, Double(k + 1))
        }
        walk.waitingSince = nil
        walk.nextDetour = nil
        characters[index].walking = walk
        moveAlong(index, distance: walk.distance)
        guard walk.distance >= Double(walk.path.steps) else { return nil }
        characters[index].walking = nil
        return walk.path.goal
    }

    /// 前面那一格被別隻佔住：停在格子中心等，站姿、面向那一格（作者 2026-11-19 決定：先等、等不到再繞路）。
    /// 等的時間不算進走路，對方走開後從這裡接著走。等了 `detourAfter` 秒還擋著，就找一條繞開別隻的路；
    /// 繞不過去就過一陣子再試，等滿 `giveUpAfter` 秒就放棄，停在這一格算走到。
    private mutating func wait(_ index: Int, _ walk: Walk, now: Double) -> Tile? {
        var walk = walk
        let here = walk.path.tiles[Int(walk.distance)]
        walk.start = now - walk.elapsed
        if walk.waitingSince == nil {
            walk.waitingSince = now
            walk.nextDetour = now + detourDelay(for: index)
        }
        characters[index].walking = walk
        moveAlong(index, distance: walk.distance)   // 這個節拍可能先走到了格子中心才停
        if now - (walk.waitingSince ?? now) >= Self.giveUpAfter {
            characters[index].walking = nil
            return here
        }
        if let next = walk.nextDetour, now >= next {
            if let detour = RoomPath.find(in: room, from: here, to: walk.path.goal, avoiding: takenByOthers(except: index)) {
                characters[index].walking = Walk(path: detour, pace: walk.pace, speed: walk.speed, start: now)
                moveAlong(index, distance: 0)
            } else {
                let retry = now + detourDelay(for: index)   // 先算好：改 characters 的同時不能再讀它
                characters[index].walking?.nextDetour = retry
            }
        }
        return nil
    }

    /// 等幾秒後試著繞路：第一隻等久一點，迎面撞上時第二隻先讓。
    private func detourDelay(for index: Int) -> Double {
        index == leadIndex ? Self.detourAfter.lead : Self.detourAfter.others
    }

    /// 一隻角色佔住的格子（每隻佔一格；ADR 0009：鯊魚比企鵝瘦，也放得進一格）：站的那一格，在兩格之間時是兩格；正在走、沒在等的話，再加上要走進去的下一格，
    /// 兩隻同時要走進同一格時才不會撞在一起。
    private static func taken(by character: Character) -> Set<Tile> {
        let p = character.position
        var tiles: Set<Tile> = [Tile(i: Int((p.i - 0.5).rounded(.down)), j: Int((p.j - 0.5).rounded(.down))),
                                Tile(i: Int((p.i - 0.5).rounded(.up)), j: Int((p.j - 0.5).rounded(.up)))]
        if let walk = character.walking, walk.waitingSince == nil {
            let next = Int(walk.distance.rounded(.down)) + 1
            if next < walk.path.tiles.count { tiles.insert(walk.path.tiles[next]) }
        }
        return tiles
    }

    /// 台上別隻佔住的格子。
    private func takenByOthers(except index: Int) -> Set<Tile> {
        characters.indices.reduce(into: Set<Tile>()) { tiles, i in
            if i != index { tiles.formUnion(Self.taken(by: characters[i])) }
        }
    }

    private func isTaken(_ tile: Tile, except index: Int) -> Bool {
        takenByOthers(except: index).contains(tile)
    }

    /// 從現在的位置走到 `goal` 的路，與這條路上已經走了幾格。
    /// - 站在格子上：從那一格找路，已經走了 0 格。
    /// - 停在兩格之間：往前走到 `to` 或回頭走到 `from`，挑總步數少的（一樣時往前），再從那一格找路；
    ///   路的第一步就是停的那一步，所以位置接得上、不會跳。
    /// - 到不了：停在原地；停在兩格之間時走到比較近的那一格。
    /// - 先找繞開 `others` 的路；找不到（例如別隻站在目的地）就走一般的路，走到牠前面再等。
    static func route(from position: TilePosition, midway: Midway?, to goal: Tile, avoiding others: Set<Tile>,
                      in room: RoomLayout) -> (path: RoomPath, walked: Double) {
        func find(from start: Tile) -> RoomPath? {
            RoomPath.find(in: room, from: start, to: goal, avoiding: others) ?? RoomPath.find(in: room, from: start, to: goal)
        }
        guard let m = midway else {
            let here = Tile(containing: position)
            return (find(from: here) ?? RoomPath(tiles: [here]), 0)
        }
        // 兩種走法：這一步從 back 走向 end，已經走了 walked
        let ways = [(back: m.from, end: m.to, walked: m.fraction), (back: m.to, end: m.from, walked: 1 - m.fraction)]
        let found = ways.compactMap { way in find(from: way.end).map { (way: way, rest: $0) } }
        func cost(_ option: (way: (back: Tile, end: Tile, walked: Double), rest: RoomPath)) -> Double {
            1 - option.way.walked + Double(option.rest.steps)
        }
        if let best = found.min(by: { cost($0) < cost($1) }) {
            return (RoomPath(tiles: [best.way.back] + best.rest.tiles), best.way.walked)
        }
        let nearer = ways[m.fraction >= 0.5 ? 0 : 1]
        return (RoomPath(tiles: [nearer.back, nearer.end]), nearer.walked)
    }

    /// 走到一半時停在哪兩格之間；剛好在格子中心時是 nil。
    private static func midway(of walk: Walk) -> Midway? {
        let tiles = walk.path.tiles
        guard tiles.count > 1 else { return nil }
        let distance = walk.distance
        let segment = min(Int(distance.rounded(.down)), tiles.count - 2)
        let fraction = distance - Double(segment)
        guard fraction > 0, fraction < 1 else { return nil }
        return Midway(from: tiles[segment], to: tiles[segment + 1], fraction: fraction)
    }

    /// 把正在走的角色放到路上走了 `distance` 格的地方，面向這一段的方向（剛好在轉角時面向下一段）。
    private mutating func moveAlong(_ index: Int, distance: Double) {
        guard let path = characters[index].walking?.path else { return }
        let tiles = path.tiles
        guard tiles.count > 1 else {
            characters[index].position = tiles[0].center
            return
        }
        let segment = min(Int(distance.rounded(.down)), tiles.count - 2)
        let fraction = distance - Double(segment)
        let a = tiles[segment].center, b = tiles[segment + 1].center
        characters[index].position = TilePosition(i: a.i + (b.i - a.i) * fraction, j: a.j + (b.j - a.j) * fraction)
        if let step = Step(from: tiles[segment], to: tiles[segment + 1]) { characters[index].facing = step.facing }
    }

    // MARK: - 小工具

    private func index(of id: CharacterID) -> Int? {
        characters.firstIndex { $0.id == id }
    }

    /// 第一隻在 `characters` 的位置：後台名單裡最前面、而且在台上的（第一隻不在台上時是下一隻）。
    private var leadIndex: Int? {
        cast.lazy.compactMap { member in self.characters.firstIndex { $0.id == member.id } }.first
    }

    /// 這一隻在哪一格：正在移動（或移動被點打斷）的話是要去的那一格，否則是站的那一格。
    private static func whereabouts(of character: Character) -> Tile {
        for intent in [character.behavior.intent, character.behavior.interruptedMove] {
            if case .move(let goal, _)? = intent { return goal }
        }
        return Tile(containing: character.position)
    }

    /// 快照裡的「在做什麼」：正在播的動作優先；移動中等別隻讓路時算站著（站姿）。
    private static func activity(of character: Character) -> SimulationSnapshot.Activity {
        if let playing = character.playing { return .motion(playing.intent, since: playing.start) }
        if let walk = character.walking, walk.waitingSince == nil { return .moving(walk.pace, elapsed: walk.elapsed) }
        return .still
    }
}
