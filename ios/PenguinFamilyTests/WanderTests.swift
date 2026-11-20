import Foundation
import Testing
@testable import PenguinFamily

/// 閒晃（A1 第 11 項）：資料檔讀得進來、不合理的數字擋下來；依權重挑活動、冷卻中的先不挑，
/// 拆成走路與站著的步驟（走到家具旁邊面向它、隨便走走、發呆、東張西望、走幾步停一下）。
/// 亂數用固定的種子，每次跑結果都一樣。
struct WanderTests {
    static let room = RoomLayout.indoor
    static let here = Tile(i: 4, j: 4)

    /// 固定種子的亂數（SplitMix64）。
    struct SeededGenerator: RandomNumberGenerator {
        var state: UInt64
        init(seed: UInt64) { state = seed }
        mutating func next() -> UInt64 {
            state &+= 0x9E37_79B9_7F4A_7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
            z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
            return z ^ (z >> 31)
        }
    }

    static func activity(_ id: String, _ kind: WanderConfig.Kind, weight: Double = 1, cooldown: Double = 0,
                         seconds: ClosedRange<Double> = 1...1) -> WanderConfig.Activity {
        WanderConfig.Activity(id: id, kind: kind, weight: weight, cooldown: cooldown, seconds: seconds)
    }

    static func visit(_ target: FurnitureKind, weight: Double = 1) -> WanderConfig.Activity {
        var a = activity(target.rawValue, .visit, weight: weight)
        a.target = target
        return a
    }

    /// 預設只慢走、路上不停。
    static func config(_ activities: [WanderConfig.Activity], pace: WanderConfig.PaceWeights = .init(walk: 1, trot: 0),
                       breaks: WanderConfig.Breaks? = nil,
                       glanceFacings: [Facing] = [.frontLeft, .frontRight]) -> WanderConfig {
        WanderConfig(version: 1, pace: pace, breaks: breaks, glanceFacings: glanceFacings, activities: activities)
    }

    /// 做完一整個活動：第一步挑活動，再把剩下的步驟拿完。
    static func wholeActivity(_ routine: inout WanderRoutine, from here: Tile = here, others: Set<Tile> = [],
                              now: Double = 0, rng: inout SeededGenerator) -> [WanderRoutine.Step] {
        var steps: [WanderRoutine.Step] = []
        repeat {
            guard let step = routine.next(from: here, others: others, now: now, using: &rng) else { break }
            steps.append(step)
        } while !routine.plan.isEmpty
        return steps
    }

    // MARK: - 資料

    @Test func bundledFileIsValid() throws {
        try Self.expectUsable(try #require(WanderConfig.bundled(), "wander.json 讀不進來"), "預設")
    }

    /// 測試用的角色包裡有 `wander.json` 的（每隻自己的閒晃，作者 2026-11-19 決定）。不進 git，乾淨 clone 下來是空的。
    static let packsWithWander = VectorPackParityTests.allPacks.filter {
        FileManager.default.fileExists(atPath: $0.appending(path: "wander.json").path)
    }

    /// 訊息只寫第幾隻，不寫角色 id（角色名稱只能出現在私有 repo）。
    @Test(.enabled(if: !packsWithWander.isEmpty, "沒有角色包自己的閒晃資料（乾淨 clone），跳過"))
    func packFilesAreValid() throws {
        for (i, pack) in Self.packsWithWander.enumerated() {
            let data = try Data(contentsOf: pack.appending(path: "wander.json"))
            let config = try #require(try? WanderConfig.decode(data), "第 \(i + 1) 個角色包的 wander.json 讀不進來")
            try Self.expectUsable(config, "第 \(i + 1) 個角色包")
        }
    }

    /// 每個「走去家具旁邊」在屋內都有站得到的位置。
    static func expectUsable(_ config: WanderConfig, _ label: String) throws {
        for activity in config.activities where activity.kind == .visit {
            let target = try #require(activity.target)
            #expect(!room.spots(beside: target).isEmpty, "\(label)：\(activity.id) 在屋內沒有站得到的位置")
        }
    }

    @Test func rejectsNumbersThatMakeNoSense() {
        func problem(_ change: (inout WanderConfig) -> Void) -> WanderConfigError? {
            var config = Self.config([Self.activity("z", .zoneOut), Self.visit(.window)])
            change(&config)
            do {
                try config.validate()
                return nil
            } catch {
                return error as? WanderConfigError
            }
        }
        #expect(problem { _ in } == nil)
        #expect(problem { $0.version = 2 } == .unsupportedVersion(2))
        #expect(problem { $0.pace = .init(walk: 0, trot: 0) } == .invalid("pace"))
        #expect(problem { $0.breaks = .init(everyTiles: 0...2, seconds: 1...1) } == .invalid("breaks"))
        #expect(problem { $0.activities[0].weight = -1 } == .invalid("z.weight"))
        #expect(problem { $0.activities[0].cooldown = -1 } == .invalid("z.cooldown"))
        #expect(problem { $0.activities[0].seconds = -1...1 } == .invalid("z.seconds"))
        #expect(problem { $0.activities[1].id = "z" } == .invalid("z.id"))
        #expect(problem { $0.activities[1].target = nil } == .invalid("window.target"))
        #expect(problem { $0.activities = $0.activities.map { var a = $0; a.weight = 0; return a } } == .invalid("activities"))
        #expect(problem { $0.activities.append(Self.activity("s", .stroll)) } == .invalid("s.tiles"))
        #expect(problem { $0.activities.append(Self.activity("l", .lookAround)) } == .invalid("l.glances"))
        #expect(problem {
            var look = Self.activity("l", .lookAround)
            look.glances = 2...3
            $0.activities.append(look)
            $0.glanceFacings = [.front, .front]
        } == .invalid("glanceFacings"))
    }

    @Test func rejectsBrokenJSON() {
        func decodes(_ activity: String) -> Bool {
            let json = #"{ "version": 1, "pace": { "walk": 1, "trot": 0 }, "activities": [\#(activity)] }"#
            return (try? WanderConfig.decode(Data(json.utf8))) != nil
        }
        #expect(decodes(#"{ "id": "z", "kind": "zoneOut", "weight": 1, "cooldown": 0, "seconds": [5, 10] }"#))
        #expect(decodes(#"{ "id": "c", "kind": "stayClose", "weight": 1, "cooldown": 0, "seconds": [5, 10] }"#))
        #expect(!decodes(#"{ "id": "z", "kind": "zoneOut", "weight": 1, "cooldown": 0, "seconds": [10, 5] }"#))   // 範圍顛倒
        #expect(!decodes(#"{ "id": "v", "kind": "visit", "target": "kitchen", "weight": 1, "cooldown": 0, "seconds": [1, 2] }"#))
        #expect(!decodes(#"{ "id": "x", "kind": "dance", "weight": 1, "cooldown": 0, "seconds": [1, 2] }"#))
        #expect(!decodes(#"{ "id": "z", "kind": "zoneOut", "weight": 1, "cooldown": 0, "seconds": [5, 10], "facing": "up" }"#))
    }

    // MARK: - 挑活動

    @Test func onlyPicksWhatHasWeight() {
        var routine = WanderRoutine(config: Self.config([Self.activity("z", .zoneOut), Self.visit(.window, weight: 0)]),
                                    room: Self.room)
        var rng = SeededGenerator(seed: 1)
        for t in 0..<20 {
            #expect(routine.next(from: Self.here, now: Double(t), using: &rng) == .stand(facing: nil, seconds: 1))
            #expect(routine.activity == "z")
        }
    }

    @Test func weightsSetHowOften() {
        var routine = WanderRoutine(config: Self.config([Self.activity("a", .zoneOut, weight: 3), Self.activity("b", .zoneOut)]),
                                    room: Self.room)
        var rng = SeededGenerator(seed: 2)
        var picks: [String: Int] = [:]
        for t in 0..<4000 {
            _ = routine.next(from: Self.here, now: Double(t), using: &rng)
            picks[routine.activity ?? "", default: 0] += 1
        }
        #expect(abs(picks["a", default: 0] - 3000) < 150)   // 3 : 1
    }

    @Test func coolingDownActivityWaits() {
        // a 的權重大很多，但挑過之後 30 秒內不再挑
        var routine = WanderRoutine(config: Self.config([Self.activity("a", .zoneOut, weight: 100, cooldown: 30),
                                                         Self.activity("b", .zoneOut)]), room: Self.room)
        var rng = SeededGenerator(seed: 3)
        var times: [Double] = []
        for t in 0...100 {
            _ = routine.next(from: Self.here, now: Double(t), using: &rng)
            if routine.activity == "a" { times.append(Double(t)) }
        }
        #expect(times.count >= 3)
        #expect(zip(times, times.dropFirst()).allSatisfy { $1 - $0 >= 30 })
    }

    @Test func everythingCoolingStillDoesSomething() {
        // 全部在冷卻時不讓牠呆站著沒事做：照樣從冷卻中的挑
        var routine = WanderRoutine(config: Self.config([Self.activity("a", .zoneOut, cooldown: 100)]), room: Self.room)
        var rng = SeededGenerator(seed: 4)
        #expect(routine.next(from: Self.here, now: 0, using: &rng) != nil)
        #expect(routine.next(from: Self.here, now: 1, using: &rng) != nil)
    }

    @Test func nothingToDoGivesNil() {
        // 房間裡沒有窗戶，只會「走去窗邊」：什麼都做不了
        let bare = RoomLayout(widthTiles: 4, depthTiles: 4, wallHeight: 40, furniture: [], wallItems: [])
        var routine = WanderRoutine(config: Self.config([Self.visit(.window)]), room: bare)
        var rng = SeededGenerator(seed: 5)
        #expect(routine.next(from: Tile(i: 1, j: 1), now: 0, using: &rng) == nil)
        #expect(routine.activity == nil)
    }

    // MARK: - 排步驟

    @Test func visitEndsBesideTheTargetFacingIt() throws {
        var rng = SeededGenerator(seed: 6)
        for target in FurnitureKind.allCases {
            for _ in 0..<5 {
                var routine = WanderRoutine(config: Self.config([Self.visit(target)]), room: Self.room)
                let steps = Self.wholeActivity(&routine, rng: &rng)
                #expect(steps.count == 2)
                guard case .walk(let tile, .walk) = steps.first, case .stand(let facing?, 1) = steps.last else {
                    Issue.record("\(target)：\(steps)")
                    continue
                }
                #expect(Self.room.spots(beside: target).contains(RoomSpot(tile: tile, facing: facing)), "\(target)")
            }
        }
    }

    @Test func alreadyThereJustStands() {
        // 窗戶只有一格寬，牠就站在窗下：不用走，直接面向窗戶
        let room = RoomLayout(widthTiles: 4, depthTiles: 4, wallHeight: 40, furniture: [], wallItems: [
            WallItem(kind: .window, side: .right, start: 2, length: 1, bottom: 10, top: 30),
        ])
        var routine = WanderRoutine(config: Self.config([Self.visit(.window)]), room: room)
        var rng = SeededGenerator(seed: 7)
        #expect(Self.wholeActivity(&routine, from: Tile(i: 2, j: 0), rng: &rng) == [.stand(facing: .backRight, seconds: 1)])
    }

    @Test func unreachableTargetIsSkipped() {
        // 窗下那一格被箱子佔住：走不到窗邊，改做別的
        let room = RoomLayout(widthTiles: 4, depthTiles: 4, wallHeight: 40, furniture: [
            Furniture(kind: .storageBox, footprint: TileRect(x: 2, y: 0, width: 1, height: 1), height: 14),
        ], wallItems: [
            WallItem(kind: .window, side: .right, start: 2, length: 1, bottom: 10, top: 30),
        ])
        var routine = WanderRoutine(config: Self.config([Self.visit(.window, weight: 100), Self.activity("z", .zoneOut)]),
                                    room: room)
        var rng = SeededGenerator(seed: 8)
        for t in 0..<10 {
            #expect(routine.next(from: Tile(i: 1, j: 1), now: Double(t), using: &rng) == .stand(facing: nil, seconds: 1))
        }
    }

    @Test func strollGoesTheRightDistance() throws {
        var stroll = Self.activity("s", .stroll, seconds: 1...3)
        stroll.tiles = 2...4
        var routine = WanderRoutine(config: Self.config([stroll]), room: Self.room)
        var rng = SeededGenerator(seed: 9)
        let counts = Self.room.stepCounts(from: Self.here)
        var goals: Set<Tile> = []
        for t in 0..<50 {
            let steps = Self.wholeActivity(&routine, now: Double(t), rng: &rng)
            guard steps.count == 2, case .walk(let goal, _) = steps[0], case .stand(nil, let seconds) = steps[1] else {
                Issue.record("\(steps)")
                continue
            }
            #expect((2...4).contains(counts[goal] ?? -1))
            #expect((1...3).contains(seconds))
            goals.insert(goal)
        }
        #expect(goals.count > 10)   // 每次去的地方不一樣
    }

    @Test func longWalksStopEveryFewTiles() throws {
        // 每走 3 步停半秒；停完至少還要走 2 步，所以最後一段是 2～4 步
        var routine = WanderRoutine(config: Self.config([Self.visit(.storageBox)],
                                                        breaks: .init(everyTiles: 3...3, seconds: 0.5...0.5)),
                                    room: Self.room)
        var rng = SeededGenerator(seed: 10)
        let start = Tile(i: 11, j: 0)
        let steps = Self.wholeActivity(&routine, from: start, rng: &rng)
        var at = start
        var legs: [Int] = []
        for (n, step) in steps.dropLast().enumerated() {
            if n % 2 == 0 {
                guard case .walk(let tile, .walk) = step else { Issue.record("第 \(n) 步：\(step)"); return }
                legs.append(try #require(Self.room.stepCounts(from: at)[tile]))
                at = tile
            } else {
                #expect(step == .stand(facing: nil, seconds: 0.5), "第 \(n) 步")
            }
        }
        #expect(legs.count >= 4)                         // 角落到對角的箱子很遠，停好幾次
        #expect(legs.dropLast().allSatisfy { $0 == 3 })
        #expect((2...4).contains(legs.last ?? 0))
        #expect(Self.room.spots(beside: .storageBox).map(\.tile).contains(at))
    }

    @Test func lookAroundTurnsADifferentWayEachTime() {
        var look = Self.activity("l", .lookAround, seconds: 0.8...1.6)
        look.glances = 4...4
        var routine = WanderRoutine(config: Self.config([look], glanceFacings: [.front, .frontLeft, .frontRight]),
                                    room: Self.room)
        var rng = SeededGenerator(seed: 11)
        for t in 0..<10 {
            let steps = Self.wholeActivity(&routine, now: Double(t), rng: &rng)
            let facings = steps.compactMap { step -> Facing? in
                guard case .stand(let facing?, let seconds) = step, (0.8...1.6).contains(seconds) else { return nil }
                return facing
            }
            #expect(facings.count == 4)
            #expect(zip(facings, facings.dropFirst()).allSatisfy { $0 != $1 })
        }
    }

    @Test func zoneOutKeepsItsDirectionUnlessTold() {
        var rng = SeededGenerator(seed: 12)
        var keep = WanderRoutine(config: Self.config([Self.activity("z", .zoneOut, seconds: 5...10)]), room: Self.room)
        guard case .stand(nil, let seconds) = keep.next(from: Self.here, now: 0, using: &rng) else {
            Issue.record("發呆要維持原本的方向")
            return
        }
        #expect((5...10).contains(seconds))
        var front = Self.activity("z", .zoneOut)
        front.facing = .front
        var facingFront = WanderRoutine(config: Self.config([front]), room: Self.room)
        #expect(facingFront.next(from: Self.here, now: 0, using: &rng) == .stand(facing: .front, seconds: 1))
    }

    @Test func paceFollowsTheWeights() {
        var stroll = Self.activity("s", .stroll)
        stroll.tiles = 2...2
        var routine = WanderRoutine(config: Self.config([stroll], pace: .init(walk: 0, trot: 1)), room: Self.room)
        var rng = SeededGenerator(seed: 13)
        guard case .walk(_, let pace) = routine.next(from: Self.here, now: 0, using: &rng) else {
            Issue.record("隨便走走的第一步要是走路")
            return
        }
        #expect(pace == .trot)
    }

    // MARK: - 兩隻（A1 第 12 項）

    @Test func stayCloseEndsNextToTheOtherFacingIt() {
        // 另一隻在 (7, 4)：走到最近的一側 (6, 4)，面向牠（往右前）
        var routine = WanderRoutine(config: Self.config([Self.activity("c", .stayClose, seconds: 5...10)]), room: Self.room)
        var rng = SeededGenerator(seed: 14)
        for t in 0..<10 {
            let steps = Self.wholeActivity(&routine, others: [Tile(i: 7, j: 4)], now: Double(t), rng: &rng)
            guard steps.count == 2, case .walk(Tile(i: 6, j: 4), .walk) = steps[0],
                  case .stand(.frontRight?, let seconds) = steps[1] else {
                Issue.record("\(steps)")
                continue
            }
            #expect((5...10).contains(seconds))
        }
    }

    @Test func stayCloseWhenAlreadyBesideJustTurns() {
        // 另一隻就在左前方的格子：不用走，直接轉向牠
        var routine = WanderRoutine(config: Self.config([Self.activity("c", .stayClose)]), room: Self.room)
        var rng = SeededGenerator(seed: 15)
        #expect(Self.wholeActivity(&routine, others: [Tile(i: 4, j: 5)], rng: &rng) == [.stand(facing: .frontLeft, seconds: 1)])
    }

    @Test func stayCloseNeedsSomeoneElse() {
        // 台上只有自己：不挑「黏著」，改做別的
        var routine = WanderRoutine(config: Self.config([Self.activity("c", .stayClose, weight: 100), Self.activity("z", .zoneOut)]),
                                    room: Self.room)
        var rng = SeededGenerator(seed: 16)
        for t in 0..<10 {
            #expect(routine.next(from: Self.here, now: Double(t), using: &rng) == .stand(facing: nil, seconds: 1))
        }
    }

    @Test func goalsAreNeverWhereTheOtherIs() {
        var rng = SeededGenerator(seed: 17)
        // 隨便走走 1 步遠：四個方向有三格是別隻的，只剩 (4, 3)
        var stroll = Self.activity("s", .stroll)
        stroll.tiles = 1...1
        var strolling = WanderRoutine(config: Self.config([stroll]), room: Self.room)
        let around: Set<Tile> = [Tile(i: 5, j: 4), Tile(i: 3, j: 4), Tile(i: 4, j: 5)]
        for t in 0..<10 {
            let steps = Self.wholeActivity(&strolling, others: around, now: Double(t), rng: &rng)
            #expect(steps.first == .walk(to: Tile(i: 4, j: 3), pace: .walk))
        }
        // 走去窗邊：窗下三格有兩格是別隻的
        var visiting = WanderRoutine(config: Self.config([Self.visit(.window)]), room: Self.room)
        for t in 0..<10 {
            let steps = Self.wholeActivity(&visiting, others: [Tile(i: 6, j: 0), Tile(i: 7, j: 0)], now: Double(t), rng: &rng)
            #expect(steps.first == .walk(to: Tile(i: 8, j: 0), pace: .walk))
        }
    }

    @Test func doesNotStopOnTheOthersTileOnTheWay() throws {
        // 每走 3 步停一下，但停的那一格剛好是別隻的：那一次不停，接著走
        var routine = WanderRoutine(config: Self.config([Self.visit(.storageBox)],
                                                        breaks: .init(everyTiles: 3...3, seconds: 0.5...0.5)),
                                    room: Self.room)
        var rng = SeededGenerator(seed: 10)
        let start = Tile(i: 11, j: 0)
        let plain = Self.wholeActivity(&routine, from: start, rng: &rng)
        guard case .walk(let firstBreak, _) = plain.first else { Issue.record("\(plain)"); return }
        var avoiding = WanderRoutine(config: routine.config, room: Self.room)
        rng = SeededGenerator(seed: 10)
        let steps = Self.wholeActivity(&avoiding, from: start, others: [firstBreak], rng: &rng)
        #expect(!steps.contains(.walk(to: firstBreak, pace: .walk)))
        #expect(steps.count == plain.count - 2)                                     // 少停一次
    }

    @Test func stepsBecomeRequests() {
        #expect(WanderRoutine.Step.walk(to: Self.here, pace: .trot).request == .walkRequested(to: Self.here, pace: .trot))
        #expect(WanderRoutine.Step.stand(facing: .front, seconds: 2).request == .standRequested(facing: .front, seconds: 2))
    }
}
