import Foundation

/// 一隻角色的動作資料（ADR 0009～0011）：動作（例如哈囉、打瞌睡）與慢、快兩種步態，都是私有素材 repo 匯出的片段。
///
/// 動作的算式只在私有素材 repo（作者在那裡設計、預覽），匯出時取樣成關鍵影格，放在角色包的 `motion.json`。
/// App 只照片段播，不分物種：加一種動物、加一個動作都不用改程式。每隻各一份（作者 2026-11-19 決定），
/// 改一隻不影響另一隻。模擬讀動作的長度、播的時候轉向哪裡、一秒走幾格；畫面準備讀某一刻每個部件的樣子。
///
/// 格式（第 4 版，ADR 0011；第 2、3 版也讀得懂：第 2 版沒有循環的動作，片段也沒有換部件與特效；第 3 版沒有姿勢與分段）：
/// ```
/// { "version": 4,
///   "motions": { "hello": { "duration": 2.8, "facing": "front", "clips": { "front": <片段> } },
///                "doze": { "cycle": 9, "clips": { "front": <片段>, "frontLeft": <片段>, "backLeft": <片段> } },
///                "sleep": { "cycle": 8, "look": "lieBack", "clips": { "lieBack": <片段> } },
///                "climbIn": { "stages": [{ "look": "backLeft", "duration": 1, "clip": <片段>, "travel": <位移> }, ...] } },
///   "gaits": { "slow": { "tilesPerSecond": 0.5, "cycle": 1, "clips": { "frontLeft": <片段>, "backLeft": <片段> } },
///              "fast": { ... } } }
/// ```
/// - 片段見 `MotionClip`。片段的方向是造型畫好的方向；翻轉的方向用來源的片段，由造型翻轉。
/// - 動作的名稱和意圖對應（`CharacterBehavior.Intent.motionName`）；角色沒有某個動作時，那個意圖馬上算播完。
/// - 動作寫了 `cycle` 就是循環的（ADR 0010，例如打瞌睡）：一直照 `cycle` 接回開頭，不會播完，由狀態機換下一件事；
///   `duration` 可以不寫。沒寫 `cycle` 的是一次性的，播 `duration` 秒。
/// - 動作寫了 `look`（ADR 0011）：不管面向哪裡，都用那個造型（例如躺著的姿勢）播。
/// - 動作寫了 `stages`（ADR 0011）：分段依序播，每段用自己的造型（`look`，方向或姿勢的名稱）與片段，可以帶位移（`Travel`）；
///   段與段之間直接切換。片段是畫好的方向的座標，`look` 是翻轉的方向時由造型翻轉。
/// - 步態的 `cycle` 是片段一個循環幾秒；沒有片段的方向（例如只有正面的造型）照速度平移、不動手腳。
nonisolated struct CharacterMotions: Equatable, Sendable {
    static let supportedVersion = 4
    /// 讀得懂的版本：第 2 版（ADR 0009）、第 3 版（ADR 0010）與第 4 版（ADR 0011）。
    static let readableVersions = 2...4

    /// 去床上睡要的動作（ADR 0011）：少一個就不會去睡，只打瞌睡。
    static let sleepMotions = ["climbIn", "sleep", "wakeTapped", "wakeRested"]

    /// 一個動作：播多久（或一個循環多久）、播的時候轉向哪裡、每個畫好的方向一段片段。
    struct Motion: Equatable, Sendable {
        /// 一次性的播完要幾秒；循環的等於 `cycle`。
        var duration: Double
        /// 播的時候轉向哪裡；nil 維持原本的方向。
        var facing: Facing? = nil
        /// 方向名稱 → 片段。沒有這個方向的片段時，那個方向站著不動。
        var clips: [String: MotionClip] = [:]
        /// 循環的動作一個循環幾秒（ADR 0010）；一次性的是 nil。
        var cycle: Double? = nil
        /// 不管面向哪裡都用這個造型（例如躺著的姿勢，ADR 0011）；nil 照面向。
        var look: String? = nil
        /// 分段的動作（ADR 0011）依序播的每一段；不分段的是空的。
        var stages: [Stage] = []

        /// 一直循環、不會播完。
        var loops: Bool { cycle != nil }

        /// 第 `t` 秒（從開始播算起）的樣子：一次性的停在兩端，循環的接回開頭，分段的看那一刻在哪一段。
        /// 造型沒有這個方向或姿勢、或這個方向沒有片段時是 nil。
        func pose(facing: Facing, rig: VectorRig, at t: Double) -> CharacterPose? {
            if let (index, local) = stage(at: t) {
                let stage = stages[index]
                return rig.look(stage.look) == nil ? nil : CharacterPose(look: stage.look, clip: stage.clip, at: local, cycle: nil)
            }
            let name = look ?? facing.rawValue
            guard let source = rig.look(name)?.source, let clip = clips[source] else { return nil }
            let time = cycle == nil ? min(max(0, t), duration) : max(0, t)
            return CharacterPose(look: name, clip: clip, at: time, cycle: cycle)
        }

        /// 分段的動作第 `t` 秒在第幾段、那一段的第幾秒；播完停在最後一段的結尾。不分段的是 nil。
        func stage(at t: Double) -> (index: Int, local: Double)? {
            guard !stages.isEmpty else { return nil }
            var rest = max(0, t)
            for (i, stage) in stages.enumerated() {
                if rest < stage.duration || i == stages.count - 1 { return (i, min(rest, stage.duration)) }
                rest -= stage.duration
            }
            return nil
        }

        /// 第 `index` 段從第幾秒開始。
        func stageStart(_ index: Int) -> Double { stages[..<index].reduce(0) { $0 + $1.duration } }
    }

    /// 分段的動作的一段（ADR 0011）。
    struct Stage: Equatable, Sendable {
        /// 方向或姿勢的名稱。
        var look: String
        var duration: Double
        var clip: MotionClip
        /// 這一段的位移；nil 停在原地。
        var travel: Travel? = nil
    }

    /// 位移（ADR 0011）：從箱庭的一個地方到另一個地方。動作資料只說「這一刻走到幾分之幾、另外離地多高」，
    /// 地方在哪裡由箱庭的床位決定（`FurnitureSlot`），所以換一張床不用重新匯出。
    /// 關鍵影格 `[秒, 比例, 離地]`，中間直線內插，兩端停住。離地高度也照比例從起點的高度到終點的高度，再加上「離地」。
    struct Travel: Equatable, Sendable {
        enum Place: String, Decodable, Sendable {
            /// 上床前站的、下床後落地的那一格。
            case entry
            /// 床邊。
            case edge
            /// 床位。
            case slot
        }

        struct Key: Equatable, Sendable {
            var time: Double
            var ratio: Double
            var lift: Double
        }

        var from: Place
        var to: Place
        var keys: [Key]

        /// 第 `t` 秒走到幾分之幾、另外離地多高。
        func at(_ t: Double) -> (ratio: Double, lift: Double) {
            guard let first = keys.first, let last = keys.last else { return (1, 0) }
            if t <= first.time { return (first.ratio, first.lift) }
            guard let next = keys.firstIndex(where: { $0.time > t }) else { return (last.ratio, last.lift) }
            let a = keys[next - 1], b = keys[next], k = (t - a.time) / (b.time - a.time)
            return (a.ratio + (b.ratio - a.ratio) * k, a.lift + (b.lift - a.lift) * k)
        }

        /// 數字合不合理：時間由小到大、在 0 到 `length` 之間，比例在 0 到 1 之間、最後走到底。
        func isValid(length: Double) -> Bool {
            guard from != to, let last = keys.last, last.ratio == 1 else { return false }
            var previous = -Double.infinity
            return keys.allSatisfy { key in
                defer { previous = key.time }
                return key.time.isFinite && key.time > previous && (0...length).contains(key.time)
                    && (0...1).contains(key.ratio) && key.lift.isFinite
            }
        }
    }

    /// 一種步態：一秒走幾格、一個循環幾秒、每個畫好的斜向一段循環的片段。
    struct Gait: Equatable, Sendable {
        var tilesPerSecond: Double
        var cycle: Double
        var clips: [String: MotionClip] = [:]
    }

    /// 慢、快各用哪個步態（不分物種，ADR 0009）。
    struct Gaits: Decodable, Equatable, Sendable {
        var slow: Gait
        var fast: Gait
    }

    var version = supportedVersion
    /// 一次性的動作，依名稱。
    var motions: [String: Motion] = [:]
    var gaits: Gaits

    /// 某個名稱的一次性動作；沒有是 nil。
    func motion(named name: String) -> Motion? {
        motions[name]
    }

    /// 有沒有去床上睡要的每個動作。
    var canSleep: Bool {
        Self.sleepMotions.allSatisfy { motions[$0] != nil } && motions["sleep"]?.loops == true
    }

    /// 移動的快慢用哪個步態。
    func gait(for pace: CharacterBehavior.Pace) -> Gait {
        switch pace {
        case .slow: gaits.slow
        case .fast: gaits.fast
        }
    }

    /// 沒有片段時的走路速度：作者 2026-11-17 定的企鵝慢走（每秒半格）與小跑（每秒一格）。
    static let defaultGaits = Gaits(slow: Gait(tilesPerSecond: 0.5, cycle: 1), fast: Gait(tilesPerSecond: 1, cycle: 0.5))

    /// 角色包沒帶動作資料、讀不懂，或片段對不上造型時：照預設的速度移動、不動手腳，
    /// 沒有一次性的動作（例如被點時馬上算哈囉完）。牠照樣上台。
    static let still = CharacterMotions(gaits: defaultGaits)

    static func decode(_ data: Data) throws -> CharacterMotions {
        let motions = try JSONDecoder().decode(CharacterMotions.self, from: data)
        try motions.validate()
        return motions
    }

    /// 檢查數字合不合理；不合理時丟出 `CharacterMotionsError`，說明是哪裡（例如 `hello.front.arm`）。
    func validate() throws {
        guard Self.readableVersions.contains(version) else { throw CharacterMotionsError.unsupportedVersion(version) }
        for (name, motion) in motions.sorted(by: { $0.key < $1.key }) {
            guard motion.duration.isFinite, motion.duration > 0 else { throw CharacterMotionsError.invalid("\(name).duration") }
            if let cycle = motion.cycle, !(cycle.isFinite && cycle > 0) { throw CharacterMotionsError.invalid("\(name).cycle") }
            if !motion.stages.isEmpty, motion.loops || !motion.clips.isEmpty { throw CharacterMotionsError.invalid("\(name).stages") }
            for (i, stage) in motion.stages.enumerated() {
                let label = "\(name).stages[\(i)]"
                guard stage.duration.isFinite, stage.duration > 0 else { throw CharacterMotionsError.invalid("\(label).duration") }
                if let part = stage.clip.problem(length: stage.duration, loops: false) {
                    throw CharacterMotionsError.invalid("\(label).\(part)")
                }
                if let travel = stage.travel, !travel.isValid(length: stage.duration) {
                    throw CharacterMotionsError.invalid("\(label).travel")
                }
            }
            for (facing, clip) in motion.clips.sorted(by: { $0.key < $1.key }) {
                if let part = clip.problem(length: motion.cycle ?? motion.duration, loops: motion.loops) {
                    throw CharacterMotionsError.invalid("\(name).\(facing).\(part)")
                }
            }
        }
        for pace in CharacterBehavior.Pace.allCases {
            let gait = gait(for: pace), name = pace.rawValue
            guard gait.tilesPerSecond.isFinite, gait.tilesPerSecond > 0 else {
                throw CharacterMotionsError.invalid("\(name).tilesPerSecond")
            }
            guard gait.cycle.isFinite, gait.cycle > 0 else { throw CharacterMotionsError.invalid("\(name).cycle") }
            for (facing, clip) in gait.clips.sorted(by: { $0.key < $1.key }) {
                if let part = clip.problem(length: gait.cycle, loops: true) {
                    throw CharacterMotionsError.invalid("\(name).\(facing).\(part)")
                }
            }
        }
    }

    /// 片段用到的方向、姿勢與部件（含顯示或藏起來的部件），造型裡都有嗎；對不上時回傳哪裡（例如 `hello.front.arm`）。
    /// 片段只能用畫好的方向或姿勢（翻轉的方向由造型從來源翻過去；分段的動作可以指定翻轉的方向，片段照樣是來源的）。
    /// 特效的名稱不在這裡檢查：沒有那個形狀時畫面準備直接不畫。
    func problem(with rig: VectorRig) -> String? {
        for (name, motion) in motions.sorted(by: { $0.key < $1.key }) {
            if let look = motion.look, rig.look(look) == nil { return "\(name).look" }
            for (i, stage) in motion.stages.enumerated() where rig.look(stage.look) == nil { return "\(name).stages[\(i)].look" }
        }
        let staged = motions.flatMap { name, motion in
            motion.stages.enumerated().map { ("\(name).stages[\($0.offset)]", rig.look($0.element.look)?.source ?? "", $0.element.clip) }
        }
        let clips = staged + motions.flatMap { name, motion in motion.clips.map { ("\(name).\($0.key)", $0.key, $0.value) } }
            + CharacterBehavior.Pace.allCases.flatMap { pace in
                gait(for: pace).clips.map { ("\(pace.rawValue).\($0.key)", $0.key, $0.value) }
            }
        for (label, facing, clip) in clips.sorted(by: { $0.0 < $1.0 }) {
            guard let drawn = rig.drawn(facing) else { return label }
            if let part = clip.tracks.keys.sorted().first(where: { drawn.parts[$0] == nil }) { return "\(label).\(part)" }
            if let part = clip.visible.keys.sorted().first(where: { drawn.parts[$0] == nil }) { return "\(label).visible.\(part)" }
        }
        return nil
    }
}

// 自動產生的解碼不認預設值；可以不寫的欄位自己解。寫在 extension 裡，保留逐欄位的建構式。
nonisolated extension CharacterMotions: Decodable {
    private enum CodingKeys: String, CodingKey { case version, motions, gaits }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(version: try c.decode(Int.self, forKey: .version),
                  motions: try c.decodeIfPresent([String: Motion].self, forKey: .motions) ?? [:],
                  gaits: try c.decode(Gaits.self, forKey: .gaits))
    }
}

nonisolated extension CharacterMotions.Motion: Decodable {
    private enum CodingKeys: String, CodingKey { case duration, facing, clips, cycle, look, stages }

    /// 循環的動作可以只寫 `cycle`，這時 `duration` 等於它；分段的不寫，是每一段加起來。
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let cycle = try c.decodeIfPresent(Double.self, forKey: .cycle)
        let stages = try c.decodeIfPresent([CharacterMotions.Stage].self, forKey: .stages) ?? []
        let total = stages.isEmpty ? nil : stages.reduce(0) { $0 + $1.duration }
        guard let duration = try c.decodeIfPresent(Double.self, forKey: .duration) ?? cycle ?? total else {
            throw DecodingError.keyNotFound(CodingKeys.duration, .init(codingPath: c.codingPath,
                                                                      debugDescription: "動作要有 duration、cycle 或 stages"))
        }
        self.init(duration: duration,
                  facing: try c.decodeIfPresent(Facing.self, forKey: .facing),
                  clips: try c.decodeIfPresent([String: MotionClip].self, forKey: .clips) ?? [:],
                  cycle: cycle,
                  look: try c.decodeIfPresent(String.self, forKey: .look),
                  stages: stages)
    }
}

nonisolated extension CharacterMotions.Stage: Decodable {
    private enum CodingKeys: String, CodingKey { case look, duration, clip, travel }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(look: try c.decode(String.self, forKey: .look), duration: try c.decode(Double.self, forKey: .duration),
                  clip: try c.decode(MotionClip.self, forKey: .clip),
                  travel: try c.decodeIfPresent(CharacterMotions.Travel.self, forKey: .travel))
    }
}

nonisolated extension CharacterMotions.Travel: Decodable {
    private enum CodingKeys: String, CodingKey { case from, to, keys }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let keys = try c.decode([[Double]].self, forKey: .keys).map { k in
            guard k.count == 3 else {
                throw DecodingError.dataCorruptedError(forKey: .keys, in: c, debugDescription: "位移的關鍵影格要有 3 個數字")
            }
            return Key(time: k[0], ratio: k[1], lift: k[2])
        }
        self.init(from: try c.decode(Place.self, forKey: .from), to: try c.decode(Place.self, forKey: .to), keys: keys)
    }
}

nonisolated extension CharacterMotions.Gait: Decodable {
    private enum CodingKeys: String, CodingKey { case tilesPerSecond, cycle, clips }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(tilesPerSecond: try c.decode(Double.self, forKey: .tilesPerSecond),
                  cycle: try c.decode(Double.self, forKey: .cycle),
                  clips: try c.decodeIfPresent([String: MotionClip].self, forKey: .clips) ?? [:])
    }
}

nonisolated enum CharacterMotionsError: Error, Equatable {
    case unsupportedVersion(Int)
    /// 哪裡不合理，例如 `hello.front.arm`、`slow.tilesPerSecond`。
    case invalid(String)
}
