import Foundation

/// 一隻角色的動作資料（ADR 0009）：一次性的動作（例如哈囉）與慢、快兩種步態，都是私有素材 repo 匯出的片段。
///
/// 動作的算式只在私有素材 repo（作者在那裡設計、預覽），匯出時取樣成關鍵影格，放在角色包的 `motion.json`。
/// App 只照片段播，不分物種：加一種動物、加一個動作都不用改程式。每隻各一份（作者 2026-11-19 決定），
/// 改一隻不影響另一隻。模擬讀動作的長度、播的時候轉向哪裡、一秒走幾格；畫面準備讀某一刻每個部件的樣子。
///
/// 格式（第 2 版）：
/// ```
/// { "version": 2,
///   "motions": { "hello": { "duration": 2.8, "facing": "front", "clips": { "front": <片段> } } },
///   "gaits": { "slow": { "tilesPerSecond": 0.5, "cycle": 1, "clips": { "frontLeft": <片段>, "backLeft": <片段> } },
///              "fast": { ... } } }
/// ```
/// - 片段見 `MotionClip`。片段的方向是造型畫好的方向；翻轉的方向用來源的片段，由造型翻轉。
/// - 一次性動作的名稱和意圖對應（`CharacterBehavior.Intent.motionName`）；角色沒有某個動作時，那個意圖馬上算播完。
/// - 步態的 `cycle` 是片段一個循環幾秒；沒有片段的方向（例如只有正面的造型）照速度平移、不動手腳。
nonisolated struct CharacterMotions: Equatable, Sendable {
    static let supportedVersion = 2

    /// 一次性的動作：播完要幾秒、播的時候轉向哪裡、每個畫好的方向一段片段。
    struct Motion: Equatable, Sendable {
        var duration: Double
        /// 播的時候轉向哪裡；nil 維持原本的方向。
        var facing: Facing? = nil
        /// 方向名稱 → 片段。沒有這個方向的片段時，那個方向站著不動。
        var clips: [String: MotionClip] = [:]
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
        guard version == Self.supportedVersion else { throw CharacterMotionsError.unsupportedVersion(version) }
        for (name, motion) in motions.sorted(by: { $0.key < $1.key }) {
            guard motion.duration.isFinite, motion.duration > 0 else { throw CharacterMotionsError.invalid("\(name).duration") }
            for (facing, clip) in motion.clips.sorted(by: { $0.key < $1.key }) {
                if let part = clip.problem(length: motion.duration, loops: false) {
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

    /// 片段用到的方向與部件，造型裡都有嗎；對不上時回傳哪裡（例如 `hello.front.arm`）。
    /// 片段只能用畫好的方向（翻轉的方向由造型從來源翻過去）。
    func problem(with rig: VectorRig) -> String? {
        let clips = motions.flatMap { name, motion in motion.clips.map { ("\(name).\($0.key)", $0.key, $0.value) } }
            + CharacterBehavior.Pace.allCases.flatMap { pace in
                gait(for: pace).clips.map { ("\(pace.rawValue).\($0.key)", $0.key, $0.value) }
            }
        for (label, facing, clip) in clips.sorted(by: { $0.0 < $1.0 }) {
            guard let drawn = rig.facings[facing] else { return label }
            if let part = clip.tracks.keys.sorted().first(where: { drawn.parts[$0] == nil }) { return "\(label).\(part)" }
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
    private enum CodingKeys: String, CodingKey { case duration, facing, clips }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(duration: try c.decode(Double.self, forKey: .duration),
                  facing: try c.decodeIfPresent(Facing.self, forKey: .facing),
                  clips: try c.decodeIfPresent([String: MotionClip].self, forKey: .clips) ?? [:])
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
