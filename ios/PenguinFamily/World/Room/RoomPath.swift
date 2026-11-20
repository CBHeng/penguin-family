/// 地板上的一格（整數）。角色移動時站在格子中心，沿格線（i 軸、j 軸）一格一格走。
nonisolated struct Tile: Hashable, Sendable {
    var i: Int
    var j: Int

    /// 格子中心。
    var center: TilePosition { TilePosition(i: Double(i) + 0.5, j: Double(j) + 0.5) }

    /// 這一點落在哪一格。
    init(containing position: TilePosition) {
        self.init(i: Int(position.i.rounded(.down)), j: Int(position.j.rounded(.down)))
    }

    init(i: Int, j: Int) {
        self.i = i
        self.j = j
    }
}

/// 沿格線走一步的方向，對到斜向的四張圖（畫面上 i 軸往右下、j 軸往左下）。
nonisolated enum Step: CaseIterable, Sendable {
    case iForward, jForward, iBackward, jBackward

    var di: Int {
        switch self {
        case .iForward: 1
        case .iBackward: -1
        case .jForward, .jBackward: 0
        }
    }

    var dj: Int {
        switch self {
        case .jForward: 1
        case .jBackward: -1
        case .iForward, .iBackward: 0
        }
    }

    /// 往這個方向走時面向哪裡：i 往前是右下（右前）、j 往前是左下（左前）、i 往後是左上（左後）、j 往後是右上（右後）。
    var facing: Facing {
        switch self {
        case .iForward: .frontRight
        case .jForward: .frontLeft
        case .iBackward: .backLeft
        case .jBackward: .backRight
        }
    }

    func from(_ tile: Tile) -> Tile { Tile(i: tile.i + di, j: tile.j + dj) }

    /// 相鄰兩格之間是哪個方向；不相鄰時是 nil。
    init?(from a: Tile, to b: Tile) {
        guard let step = Self.allCases.first(where: { $0.from(a) == b }) else { return nil }
        self = step
    }
}

/// 家具或牆上東西旁邊站得上去的一格，與站在那裡看著它時面向哪裡（閒晃「走向家具、窗邊」用）。
nonisolated struct RoomSpot: Equatable, Sendable {
    let tile: Tile
    let facing: Facing
}

nonisolated extension RoomLayout {
    /// 角色站得上去的格子：在地板上，而且沒有家具。
    func isWalkable(_ tile: Tile) -> Bool {
        let one = TileRect(x: tile.i, y: tile.j, width: 1, height: 1)
        return floor.contains(one) && !furniture.contains { $0.footprint.intersects(one) }
    }

    /// 從 `start` 沿格線走到每一格要幾步（繞過家具）；走不到的格子不在裡面，`start` 站不上去時是空的。
    /// 步數和 `RoomPath.find` 的最短路相同；閒晃一次算好整個房間，不用每一格各找一次路。
    func stepCounts(from start: Tile) -> [Tile: Int] {
        guard isWalkable(start) else { return [:] }
        var counts = [start: 0]
        var queue = [start]
        var head = 0
        while head < queue.count {
            let tile = queue[head]
            head += 1
            for step in Step.allCases {
                let next = step.from(tile)
                guard counts[next] == nil, isWalkable(next) else { continue }
                counts[next] = counts[tile]! + 1
                queue.append(next)
            }
        }
        return counts
    }

    /// 某種家具或牆上東西旁邊站得上去的格子，與面向它的方向；站不上去的（牆外、別的家具上）不算。
    /// - 地上的家具：四周緊鄰的格子，面向家具。
    /// - 牆上的東西（窗戶）：牆腳下那一排，面向牆。左牆在 i = 0，面向左後；右牆在 j = 0，面向右後。
    func spots(beside kind: FurnitureKind) -> [RoomSpot] {
        var spots: [RoomSpot] = []
        for item in furniture where item.kind == kind {
            let r = item.footprint
            for i in r.x..<r.maxX {
                spots.append(RoomSpot(tile: Tile(i: i, j: r.y - 1), facing: Step.jForward.facing))
                spots.append(RoomSpot(tile: Tile(i: i, j: r.maxY), facing: Step.jBackward.facing))
            }
            for j in r.y..<r.maxY {
                spots.append(RoomSpot(tile: Tile(i: r.x - 1, j: j), facing: Step.iForward.facing))
                spots.append(RoomSpot(tile: Tile(i: r.maxX, j: j), facing: Step.iBackward.facing))
            }
        }
        for item in wallItems where item.kind == kind {
            for k in item.start..<(item.start + item.length) {
                switch item.side {
                case .left: spots.append(RoomSpot(tile: Tile(i: 0, j: k), facing: Step.iBackward.facing))
                case .right: spots.append(RoomSpot(tile: Tile(i: k, j: 0), facing: Step.jBackward.facing))
                }
            }
        }
        return spots.filter { isWalkable($0.tile) }
    }

    /// 一開始站的格子，給 `count` 隻（ADR 0009：一家有幾隻由名單決定）：先用箱庭的起點（`starts`），
    /// 不夠時從第一個起點往外找最近、站得上去、還沒人用的格子（一樣近時依 i、j 排）。站得上去的格子不夠時給得比較少。
    func startTiles(count: Int) -> [Tile] {
        var tiles: [Tile] = []
        for tile in starts where isWalkable(tile) && !tiles.contains(tile) && tiles.count < count { tiles.append(tile) }
        guard tiles.count < count else { return tiles }
        let origin = tiles.first ?? Tile(i: widthTiles / 2, j: depthTiles / 2)
        let nearby = stepCounts(from: origin)
            .filter { !tiles.contains($0.key) }
            .sorted { ($0.value, $0.key.i, $0.key.j) < ($1.value, $1.key.i, $1.key.j) }
        return tiles + nearby.prefix(count - tiles.count).map(\.key)
    }

    /// 某一格（例如另一隻角色站的地方）四周緊鄰、站得上去的格子，與面向那一格的方向（閒晃「走去黏著另一隻」用）。
    func spots(around tile: Tile) -> [RoomSpot] {
        Step.allCases.compactMap { step in
            let spot = step.from(tile)
            // 從旁邊那一格往這一格走的方向，就是面向它的方向
            guard isWalkable(spot), let toward = Step(from: spot, to: tile) else { return nil }
            return RoomSpot(tile: spot, facing: toward.facing)
        }
    }
}

/// 在箱庭裡找路：沿格線走、繞過家具（A1 第 6 項），需要時也繞過另一隻角色（A1 第 12 項）。
///
/// 先找最短的路；一樣短的路有好幾條時，挑轉彎最少的，看起來像有目標地走，不會一直左右拐。
/// 還是一樣時，照 `Step.allCases` 的順序固定挑一條，同樣的起點與終點每次都走同一條路。
nonisolated struct RoomPath: Equatable, Sendable {
    /// 一段直線：往哪個方向、走過哪些格子（不含這段的起點）。
    struct Leg: Equatable, Sendable {
        let step: Step
        let tiles: [Tile]
    }

    /// 從起點到終點的每一格（含兩端）。
    let tiles: [Tile]

    var start: Tile { tiles[0] }
    var goal: Tile { tiles[tiles.count - 1] }
    /// 走幾步（格數減一）。
    var steps: Int { tiles.count - 1 }

    /// 拆成一段段直線；起點等於終點時是空的。
    var legs: [Leg] {
        var legs: [Leg] = []
        for (a, b) in zip(tiles, tiles.dropFirst()) {
            guard let step = Step(from: a, to: b) else { continue }
            if let last = legs.last, last.step == step {
                legs[legs.count - 1] = Leg(step: step, tiles: last.tiles + [b])
            } else {
                legs.append(Leg(step: step, tiles: [b]))
            }
        }
        return legs
    }

    /// 轉幾次彎。
    var turns: Int { max(0, legs.count - 1) }

    /// 找一條路；起點或終點站不上去、或到不了時是 nil。起點等於終點時是只有一格的路。
    /// `avoiding` 的格子當成站不上去（例如另一隻角色站的地方），起點除外；終點在裡面時是 nil。
    static func find(in room: RoomLayout, from start: Tile, to goal: Tile, avoiding: Set<Tile> = []) -> RoomPath? {
        guard room.isWalkable(start), room.isWalkable(goal), start == goal || !avoiding.contains(goal) else { return nil }
        if start == goal { return RoomPath(tiles: [start]) }

        // 狀態是「站在哪一格、上一步往哪走」，成本先比步數、再比轉彎數（Dijkstra；格子很少，不用堆積）
        struct State: Hashable { let tile: Tile; let heading: Step? }
        typealias Cost = (steps: Int, turns: Int)
        func better(_ a: Cost, _ b: Cost) -> Bool { (a.steps, a.turns) < (b.steps, b.turns) }

        let origin = State(tile: start, heading: nil)
        var best: [State: Cost] = [origin: (0, 0)]
        var previous: [State: State] = [:]
        var open: [State] = [origin]
        var done: Set<State> = []
        while !open.isEmpty {
            // 取成本最小的；一樣時取先加入的，結果才固定
            let index = open.indices.min { better(best[open[$0]]!, best[open[$1]]!) }!
            let current = open.remove(at: index)
            guard done.insert(current).inserted else { continue }
            if current.tile == goal {
                var tiles = [current.tile]
                var cursor = current
                while let prior = previous[cursor] {
                    tiles.append(prior.tile)
                    cursor = prior
                }
                return RoomPath(tiles: tiles.reversed())
            }
            let cost = best[current]!
            for step in Step.allCases {
                let next = step.from(current.tile)
                guard room.isWalkable(next), !avoiding.contains(next) else { continue }
                let state = State(tile: next, heading: step)
                guard !done.contains(state) else { continue }
                let turned = current.heading.map { $0 != step } ?? false
                let candidate: Cost = (cost.steps + 1, cost.turns + (turned ? 1 : 0))
                if let known = best[state], !better(candidate, known) { continue }
                best[state] = candidate
                previous[state] = current
                open.append(state)
            }
        }
        return nil
    }
}
