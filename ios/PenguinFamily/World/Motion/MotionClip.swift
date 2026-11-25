import Foundation

/// 一個部件從原位怎麼動（ADR 0009）：以轉軸為中心先縮放、再旋轉，最後位移。
/// 單位是角色畫布的單位，角度正值是畫面上的順時針（y 往下）。
nonisolated struct PartPose: Equatable, Sendable {
    var rotate = 0.0
    var scaleX = 1.0
    var scaleY = 1.0
    var x = 0.0
    var y = 0.0

    static let rest = PartPose()

    /// 換成矩陣。順序和私有素材 repo 匯出時拆解矩陣的順序相同，在關鍵影格上會得到和 JS 算式一樣的矩陣。
    func matrix(pivot: VectorRig.Point) -> Affine2D {
        .translation(x, y) * .around(pivot, .rotation(degrees: rotate) * .scale(scaleX, scaleY))
    }

    /// `a` 到 `b` 之間第 `k`（0～1）的樣子：每個數字直線內插，角度往比較近的那一邊轉。
    static func between(_ a: PartPose, _ b: PartPose, _ k: Double) -> PartPose {
        func mix(_ p: Double, _ q: Double) -> Double { p + (q - p) * k }
        let turn = remainder(b.rotate - a.rotate, 360)
        return PartPose(rotate: a.rotate + turn * k, scaleX: mix(a.scaleX, b.scaleX), scaleY: mix(a.scaleY, b.scaleY),
                        x: mix(a.x, b.x), y: mix(a.y, b.y))
    }

    fileprivate var isFinite: Bool { [rotate, scaleX, scaleY, x, y].allSatisfy(\.isFinite) }
}

/// 一個特效這一刻的樣子（ADR 0010）：哪個特效（共用的形狀，`EffectLibrary`）、以特效的轉軸怎麼動、透明度。
nonisolated struct EffectPose: Equatable, Sendable {
    let name: String
    let pose: PartPose
    /// 0 看不到、1 不透明。
    let alpha: Double
}

/// 一段片段（ADR 0009、0010）：每個部件一條軌道，軌道是依時間排好的關鍵影格；沒有軌道的部件在原位。
///
/// 由私有素材 repo 從動作的算式取樣匯出（角色包的 `motion.json`），App 只內插，不知道是哪種動物、哪個動作。
/// - 第 2 版的 JSON 只有軌道：`{ 部件: [[秒, 旋轉, 橫向縮放, 縱向縮放, 位移 x, 位移 y], ...] }`。
/// - 第 3 版（ADR 0010）：`{ "tracks": { 同上 }, "visible": { 部件: [[秒, 1 或 0], ...] },
///   "effects": [{ "name": "z", "keys": [[秒, 旋轉, 橫向縮放, 縱向縮放, 位移 x, 位移 y, 透明度], ...] }] }`，
///   `visible`、`effects` 可以不寫。
///   - `visible`：從那一秒起顯示或藏起來，不內插；沒寫到的部件照造型（`hidden` 的平常藏起來）。
///   - `effects`：每條是一個特效（同一個特效可以有好幾條，例如同時飄著的 Z），位置是這隻角色畫布的座標；
///     透明度和其他數字一樣直線內插，0 的時候不畫。
nonisolated struct MotionClip: Equatable, Sendable {
    struct Key: Equatable, Sendable {
        let time: Double
        let pose: PartPose
    }

    /// 從 `time` 起顯示（`shown`）或藏起來。
    struct Visibility: Equatable, Sendable {
        let time: Double
        let shown: Bool
    }

    struct EffectKey: Equatable, Sendable {
        let time: Double
        let pose: PartPose
        let alpha: Double
    }

    /// 一個特效的軌道。
    struct EffectTrack: Equatable, Sendable {
        let name: String
        let keys: [EffectKey]
    }

    let tracks: [String: [Key]]
    let visible: [String: [Visibility]]
    let effects: [EffectTrack]

    init(tracks: [String: [Key]], visible: [String: [Visibility]] = [:], effects: [EffectTrack] = []) {
        self.tracks = tracks
        self.visible = visible
        self.effects = effects
    }

    /// 第 `t` 秒每個有軌道的部件的樣子。
    /// - 一次性（`cycle` 是 nil）：第一個關鍵影格之前用第一個，最後一個之後用最後一個。
    /// - 循環（`cycle` 是一個循環幾秒）：時間取餘數；最後一個關鍵影格之後，在 `cycle` 秒接回第一個。
    func poses(at t: Double, cycle: Double? = nil) -> [String: PartPose] {
        tracks.mapValues { Self.pose(of: $0, at: t, cycle: cycle) }
    }

    /// 第 `t` 秒片段說要顯示或藏起來的部件（沒寫到的不在裡面）。
    /// 第一個之前：一次性的用第一個，循環的用最後一個（接回來）。
    func visibility(at t: Double, cycle: Double? = nil) -> [String: Bool] {
        visible.compactMapValues { keys in
            guard let first = keys.first, let last = keys.last else { return nil }
            let time = Self.wrap(t, cycle)
            guard time >= first.time else { return cycle == nil ? first.shown : last.shown }
            return keys.last { $0.time <= time }?.shown ?? first.shown
        }
    }

    /// 第 `t` 秒看得到的特效（透明度大於 0），依軌道的順序。`includeHidden` 時看不到的也列出來（測試比對每條軌道用）。
    func effectPoses(at t: Double, cycle: Double? = nil, includeHidden: Bool = false) -> [EffectPose] {
        effects.compactMap { track in
            guard let (a, b, k) = Self.segment(track.keys.map(\.time), at: t, cycle: cycle) else { return nil }
            let p = track.keys[a], q = track.keys[b]
            let alpha = p.alpha + (q.alpha - p.alpha) * k
            guard alpha > 0 || includeHidden else { return nil }
            return EffectPose(name: track.name, pose: PartPose.between(p.pose, q.pose, k), alpha: min(1, alpha))
        }
    }

    /// 一條軌道第 `t` 秒的樣子；剛好在關鍵影格上時就是那一格的數字。
    static func pose(of keys: [Key], at t: Double, cycle: Double?) -> PartPose {
        guard let (a, b, k) = segment(keys.map(\.time), at: t, cycle: cycle) else { return .rest }
        return k == 0 ? keys[a].pose : PartPose.between(keys[a].pose, keys[b].pose, k)
    }

    /// 循環的話，時間取餘數。
    private static func wrap(_ t: Double, _ cycle: Double?) -> Double {
        guard let cycle else { return t }
        let time = t.truncatingRemainder(dividingBy: cycle)
        return time < 0 ? time + cycle : time
    }

    /// 第 `t` 秒落在哪兩個關鍵影格之間（第 `a` 個到第 `b` 個的 `k`，0～1）。沒有關鍵影格是 nil。
    /// 一次性的在兩端停住；循環的在最後一個之後、第一個之前接回去（第一個在 `cycle` 秒後再出現一次）。
    private static func segment(_ times: [Double], at t: Double, cycle: Double?) -> (Int, Int, Double)? {
        guard let first = times.first, let last = times.last else { return nil }
        let time = wrap(t, cycle)
        let n = times.count
        guard time >= first else {
            guard let cycle else { return (0, 0, 0) }
            let start = last - cycle
            return (n - 1, 0, (time - start) / (first - start))
        }
        // 最後一個不晚於 time 的關鍵影格
        var low = 0, high = n - 1
        while low < high {
            let mid = (low + high + 1) / 2
            if times[mid] <= time { low = mid } else { high = mid - 1 }
        }
        if times[low] == time { return (low, low, 0) }
        guard low + 1 < n else {
            guard let cycle else { return (n - 1, n - 1, 0) }
            return (n - 1, 0, (time - last) / (first + cycle - last))
        }
        return (low, low + 1, (time - times[low]) / (times[low + 1] - times[low]))
    }

    /// 數字合不合理；不合理時回傳哪條軌道。`length` 是一次性動作的長度或一個循環的長度：
    /// 關鍵影格的時間要由小到大、在 0 到 `length` 之間（循環的不含 `length`，那一刻就是第一格），縮放要大於 0；
    /// 特效的透明度在 0 到 1 之間。
    func problem(length: Double, loops: Bool) -> String? {
        func timesOK(_ times: [Double]) -> Bool {
            guard !times.isEmpty else { return false }
            var previous = -Double.infinity
            for time in times {
                guard time.isFinite, time > previous, time >= 0, loops ? time < length : time <= length else { return false }
                previous = time
            }
            return true
        }
        for (part, keys) in tracks.sorted(by: { $0.key < $1.key }) {
            guard timesOK(keys.map(\.time)), keys.allSatisfy({ $0.pose.isFinite && $0.pose.scaleX > 0 && $0.pose.scaleY > 0 })
            else { return part }
        }
        for (part, keys) in visible.sorted(by: { $0.key < $1.key }) where !timesOK(keys.map(\.time)) {
            return "visible.\(part)"
        }
        for (i, track) in effects.enumerated() {
            guard !track.name.isEmpty, timesOK(track.keys.map(\.time)),
                  track.keys.allSatisfy({ $0.pose.isFinite && $0.pose.scaleX > 0 && $0.pose.scaleY > 0 && (0...1).contains($0.alpha) })
            else { return "effects[\(i)]" }
        }
        return nil
    }
}

extension MotionClip: Decodable {
    private struct Name: CodingKey {
        let stringValue: String
        var intValue: Int? { nil }
        init(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { nil }
    }

    private struct RawEffect: Decodable {
        let name: String
        let keys: [[Double]]
    }

    nonisolated init(from decoder: Decoder) throws {
        let keyed = try decoder.container(keyedBy: Name.self)
        func corrupted(_ message: String) -> DecodingError {
            DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: message))
        }
        func tracks(_ raw: [String: [[Double]]]) throws -> [String: [Key]] {
            try raw.mapValues { keys in
                try keys.map { k in
                    guard k.count == 6 else { throw corrupted("部件的關鍵影格要有 6 個數字") }
                    return Key(time: k[0], pose: PartPose(rotate: k[1], scaleX: k[2], scaleY: k[3], x: k[4], y: k[5]))
                }
            }
        }
        // 第 3 版有 tracks；第 2 版整個就是軌道
        guard keyed.contains(Name(stringValue: "tracks")) else {
            self.init(tracks: try tracks(try decoder.singleValueContainer().decode([String: [[Double]]].self)))
            return
        }
        let rawVisible = try keyed.decodeIfPresent([String: [[Double]]].self, forKey: Name(stringValue: "visible")) ?? [:]
        let visible = try rawVisible.mapValues { keys in
            try keys.map { k in
                guard k.count == 2, k[1] == 0 || k[1] == 1 else { throw corrupted("顯示的關鍵影格要是 [秒, 1 或 0]") }
                return Visibility(time: k[0], shown: k[1] == 1)
            }
        }
        let rawEffects = try keyed.decodeIfPresent([RawEffect].self, forKey: Name(stringValue: "effects")) ?? []
        let effects = try rawEffects.map { effect in
            EffectTrack(name: effect.name, keys: try effect.keys.map { k in
                guard k.count == 7 else { throw corrupted("特效的關鍵影格要有 7 個數字") }
                return EffectKey(time: k[0], pose: PartPose(rotate: k[1], scaleX: k[2], scaleY: k[3], x: k[4], y: k[5]),
                                 alpha: k[6])
            })
        }
        self.init(tracks: try tracks(try keyed.decode([String: [[Double]]].self, forKey: Name(stringValue: "tracks"))),
                  visible: visible, effects: effects)
    }
}

/// 一隻角色某一格的樣子（ADR 0009～0011）：用哪個造型（方向或姿勢的名稱），每個部件從原位怎麼動（沒列到的在原位）、
/// 片段說要顯示或藏起來的部件（沒列到的照造型），與看得到的特效。
/// 畫面準備照片段算出來，`VectorRig.frame` 換成每個部件的矩陣。
nonisolated struct CharacterPose: Equatable, Sendable {
    /// `Facing` 的名稱，或姿勢的名稱（例如 `lieBack`）。
    var look: String
    var parts: [String: PartPose] = [:]
    var shown: [String: Bool] = [:]
    var effects: [EffectPose] = []

    init(look: String, parts: [String: PartPose] = [:], shown: [String: Bool] = [:], effects: [EffectPose] = []) {
        self.look = look
        self.parts = parts
        self.shown = shown
        self.effects = effects
    }

    init(facing: Facing, parts: [String: PartPose] = [:], shown: [String: Bool] = [:], effects: [EffectPose] = []) {
        self.init(look: facing.rawValue, parts: parts, shown: shown, effects: effects)
    }

    /// 片段第 `t` 秒的樣子，畫在 `look` 上。
    init(look: String, clip: MotionClip, at t: Double, cycle: Double?) {
        self.init(look: look, parts: clip.poses(at: t, cycle: cycle), shown: clip.visibility(at: t, cycle: cycle),
                  effects: clip.effectPoses(at: t, cycle: cycle))
    }
}
