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
}

/// 一段片段（ADR 0009）：每個部件一條軌道，軌道是依時間排好的關鍵影格；沒有軌道的部件在原位。
///
/// 由私有素材 repo 從動作的算式取樣匯出（角色包的 `motion.json`），App 只內插，不知道是哪種動物、哪個動作。
/// JSON 寫成 `{ 部件: [[秒, 旋轉, 橫向縮放, 縱向縮放, 位移 x, 位移 y], ...] }`。
nonisolated struct MotionClip: Equatable, Sendable {
    struct Key: Equatable, Sendable {
        let time: Double
        let pose: PartPose
    }

    let tracks: [String: [Key]]

    init(tracks: [String: [Key]]) {
        self.tracks = tracks
    }

    /// 第 `t` 秒每個有軌道的部件的樣子。
    /// - 一次性（`cycle` 是 nil）：第一個關鍵影格之前用第一個，最後一個之後用最後一個。
    /// - 循環（`cycle` 是一個循環幾秒）：時間取餘數；最後一個關鍵影格之後，在 `cycle` 秒接回第一個。
    func poses(at t: Double, cycle: Double? = nil) -> [String: PartPose] {
        tracks.mapValues { Self.pose(of: $0, at: t, cycle: cycle) }
    }

    /// 一條軌道第 `t` 秒的樣子；剛好在關鍵影格上時就是那一格的數字。
    static func pose(of keys: [Key], at t: Double, cycle: Double?) -> PartPose {
        guard let first = keys.first, let last = keys.last else { return .rest }
        var time = t
        if let cycle {
            time = t.truncatingRemainder(dividingBy: cycle)
            if time < 0 { time += cycle }
        }
        // 最後一個不晚於 time 的關鍵影格
        var low = 0, high = keys.count - 1
        guard time >= first.time else {
            guard let cycle else { return first.pose }
            let start = last.time - cycle
            return PartPose.between(last.pose, first.pose, (time - start) / (first.time - start))
        }
        while low < high {
            let mid = (low + high + 1) / 2
            if keys[mid].time <= time { low = mid } else { high = mid - 1 }
        }
        let key = keys[low]
        if key.time == time { return key.pose }
        guard low + 1 < keys.count else {
            guard let cycle else { return last.pose }
            return PartPose.between(last.pose, first.pose, (time - last.time) / (first.time + cycle - last.time))
        }
        let next = keys[low + 1]
        return PartPose.between(key.pose, next.pose, (time - key.time) / (next.time - key.time))
    }

    /// 數字合不合理；不合理時回傳哪條軌道。`length` 是一次性動作的長度或一個循環的長度：
    /// 關鍵影格的時間要由小到大、在 0 到 `length` 之間（循環的不含 `length`，那一刻就是第一格），縮放要大於 0。
    func problem(length: Double, loops: Bool) -> String? {
        for (part, keys) in tracks.sorted(by: { $0.key < $1.key }) {
            guard !keys.isEmpty else { return part }
            var previous = -Double.infinity
            for key in keys {
                let p = key.pose
                guard [key.time, p.rotate, p.scaleX, p.scaleY, p.x, p.y].allSatisfy(\.isFinite),
                      key.time > previous, key.time >= 0, loops ? key.time < length : key.time <= length,
                      p.scaleX > 0, p.scaleY > 0
                else { return part }
                previous = key.time
            }
        }
        return nil
    }
}

extension MotionClip: Decodable {
    nonisolated init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode([String: [[Double]]].self)
        var tracks: [String: [Key]] = [:]
        for (part, keys) in raw {
            tracks[part] = try keys.map { k in
                guard k.count == 6 else {
                    throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath,
                                                            debugDescription: "\(part) 的關鍵影格要有 6 個數字"))
                }
                return Key(time: k[0], pose: PartPose(rotate: k[1], scaleX: k[2], scaleY: k[3], x: k[4], y: k[5]))
            }
        }
        self.tracks = tracks
    }
}

/// 一隻角色某一格的樣子（ADR 0009）：面向哪裡，每個部件從原位怎麼動（沒列到的在原位）。
/// 畫面準備照片段算出來，`VectorRig.frame` 換成每個部件的矩陣。
nonisolated struct CharacterPose: Equatable, Sendable {
    var facing: Facing
    var parts: [String: PartPose] = [:]
}
