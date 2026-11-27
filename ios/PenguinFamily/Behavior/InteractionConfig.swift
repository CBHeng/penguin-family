import Foundation
import os

/// 點一下的反應的資料（A1 第 14 項，作者 2026-11-25～27 決定；玩法見遊戲設計的「點一下」）。
///
/// 每隻各一份：角色包的 `interactions.json`，由私有素材 repo 匯出。公開 repo 的 `Resources/interactions.json` 是預設，
/// 給沒有角色包、或角色包沒帶這個檔的那隻。數字在實機上調。反應用動作的名稱寫（不分物種，ADR 0009），
/// 角色沒有的動作不挑；一個都沒有時照舊哈囉。
///
/// ```
/// { "version": 1,
///   "reactions": { "facingOwner": [{ "motions": ["tiltLeft", "tiltRight"], "weight": 1 }],
///                  "facingAway": [{ "motions": ["startle"], "weight": 1 }] },
///   "greeting": { "motion": "happyHello", "afterHours": 4 },
///   "patience": { "motion": "annoyed", "max": 100, "perTap": 25, "recoverPerSecond": 5, "below": 20 } }
/// ```
/// 閒著（待機、站著、走路中）被點時，依序：
/// 1. 背對主人（左後、右後）：從 `reactions.facingAway` 挑，連開心哈囉都排在後面（作者 2026-11-27 決定）。
///    這一下照樣扣耐心；點下去時耐心已經低於門檻，就直接播不耐煩、不播背對的反應。欠著的開心哈囉留到下一次。
/// 2. `greeting`（可以不寫）：離上一次點這隻滿 `afterHours` 小時（從來沒被點過也算），播 `motion`（開心哈囉），不扣耐心。
///    牠在打瞌睡或睡覺時先照原本的規則醒來，再接著播；沒有回應的點不算用掉。
/// 3. `patience`（可以不寫）：耐心值，滿值 `max`，打開 App 時是滿的。每點一下扣 `perTap`，每秒回 `recoverPerSecond`。
///    點下去時已經低於 `below` 就播 `motion`（不耐煩），一直戳就一直是，回升到 `below` 以上才好（作者 2026-11-27 決定）。
///    平常的反應播放中沒有回應的點也扣（那一下已經低於門檻就等播完再不耐煩）；醒來、開心哈囉、不耐煩、上下床時的點不扣。
/// 4. 其他：從 `reactions.facingOwner` 依 `weight` 挑一組，組裡的動作再隨機挑一個（例如歪頭每次隨機歪一邊）。
/// `facingAway` 可以是空的（背對時也照 2～4）。
nonisolated struct InteractionConfig: Decodable, Equatable, Sendable {
    static let supportedVersion = 1

    /// 一組反應：依權重挑到這組時，組裡的動作隨機挑一個。
    struct Reaction: Decodable, Equatable, Sendable {
        var motions: [String]
        var weight: Double
    }

    /// 看得到臉、背對時各一份。
    struct Reactions: Decodable, Equatable, Sendable {
        var facingOwner: [Reaction]
        var facingAway: [Reaction] = []
    }

    struct Greeting: Decodable, Equatable, Sendable {
        var motion: String
        var afterHours: Double

        /// 離上一次點這隻幾秒以上算「離開一陣子」。
        var afterSeconds: Double { afterHours * 3600 }
    }

    struct PatienceConfig: Decodable, Equatable, Sendable {
        var motion: String
        var max: Double
        var perTap: Double
        var recoverPerSecond: Double
        var below: Double
    }

    var version: Int
    var reactions: Reactions
    var greeting: Greeting? = nil
    var patience: PatienceConfig? = nil

    static func decode(_ data: Data) throws -> InteractionConfig {
        let config = try JSONDecoder().decode(InteractionConfig.self, from: data)
        try config.validate()
        return config
    }

    /// 檢查數字合不合理；不合理時丟出 `InteractionConfigError`，說明是哪個欄位。
    func validate() throws {
        guard version == Self.supportedVersion else { throw InteractionConfigError.unsupportedVersion(version) }
        guard reactions.facingOwner.contains(where: { $0.weight > 0 }) else { throw InteractionConfigError.invalid("reactions.facingOwner") }
        for (name, list) in [("facingOwner", reactions.facingOwner), ("facingAway", reactions.facingAway)] {
            for (i, reaction) in list.enumerated() {
                guard !reaction.motions.isEmpty, reaction.motions.allSatisfy({ !$0.isEmpty }) else {
                    throw InteractionConfigError.invalid("reactions.\(name)[\(i)].motions")
                }
                guard reaction.weight >= 0, reaction.weight.isFinite else {
                    throw InteractionConfigError.invalid("reactions.\(name)[\(i)].weight")
                }
            }
        }
        if let greeting {
            guard !greeting.motion.isEmpty else { throw InteractionConfigError.invalid("greeting.motion") }
            guard greeting.afterHours > 0, greeting.afterHours.isFinite else { throw InteractionConfigError.invalid("greeting.afterHours") }
        }
        if let patience {
            guard !patience.motion.isEmpty else { throw InteractionConfigError.invalid("patience.motion") }
            guard patience.max > 0, patience.max.isFinite else { throw InteractionConfigError.invalid("patience.max") }
            guard patience.perTap > 0, patience.perTap.isFinite else { throw InteractionConfigError.invalid("patience.perTap") }
            // 不會回升的話，不耐煩就永遠不會好
            guard patience.recoverPerSecond > 0, patience.recoverPerSecond.isFinite else {
                throw InteractionConfigError.invalid("patience.recoverPerSecond")
            }
            guard patience.below > 0, patience.below <= patience.max else { throw InteractionConfigError.invalid("patience.below") }
        }
    }

    /// 被點時挑哪個動作：背對時從 `facingAway`、否則從 `facingOwner`，只看這隻有的動作（`has`），依權重挑一組、
    /// 組裡再隨機挑一個。一個都沒有時是 nil。
    func pickReaction(facingAway: Bool, has: (String) -> Bool, using rng: inout some RandomNumberGenerator) -> String? {
        let options = (facingAway ? reactions.facingAway : reactions.facingOwner).compactMap { reaction -> (motions: [String], weight: Double)? in
            let motions = reaction.motions.filter(has)
            return motions.isEmpty || reaction.weight <= 0 ? nil : (motions, reaction.weight)
        }
        let total = options.reduce(0) { $0 + $1.weight }
        guard total > 0 else { return nil }
        var roll = Double.random(in: 0..<total, using: &rng)
        for option in options {
            if roll < option.weight { return option.motions.randomElement(using: &rng) }
            roll -= option.weight
        }
        return options.last?.motions.randomElement(using: &rng)
    }

    private static let log = Logger(subsystem: "PenguinFamily", category: "Interaction")

    /// App 裡的預設 `interactions.json`。讀不到或內容不合理時是 nil（沒帶自己資料的角色被點就照舊哈囉）；`TapReactionTests` 守著這個檔案。
    static func bundled(_ bundle: Bundle = .main) -> InteractionConfig? {
        do {
            guard let url = bundle.url(forResource: "interactions", withExtension: "json") else {
                log.error("找不到 interactions.json")
                return nil
            }
            return try decode(Data(contentsOf: url))
        } catch {
            log.error("interactions.json 讀取失敗：\(String(describing: error))")
            return nil
        }
    }
}

nonisolated enum InteractionConfigError: Error, Equatable {
    case unsupportedVersion(Int)
    /// 哪個欄位不合理，例如 `patience.below`。
    case invalid(String)
}

/// 一隻角色的耐心值（作者 2026-11-27 決定）：被點一下扣一些，沒被點時慢慢回升到滿值，低於門檻就不耐煩。
///
/// 和睏意（`Sleepiness`）一樣只記「某一刻是多少」，要用時再算，模擬停下來不跑節拍時也不用一直更新。
/// 不碰畫面、不讀時鐘：時間（模擬的秒）由外面給。打開 App 時是滿的，不跨次保存。
nonisolated struct Patience: Equatable, Sendable {
    let max: Double
    let recoverPerSecond: Double
    /// `since` 那一刻的值。
    private(set) var value: Double
    private(set) var since: Double

    init(max: Double, recoverPerSecond: Double, at time: Double) {
        self.max = max
        self.recoverPerSecond = recoverPerSecond
        value = max
        since = time
    }

    /// `time` 那一刻的值（0～滿值）。
    func level(at time: Double) -> Double {
        min(max, value + recoverPerSecond * Swift.max(0, time - since))
    }

    /// 在 `time` 扣 `amount`（不低於 0）。
    mutating func spend(_ amount: Double, at time: Double) {
        value = Swift.max(0, level(at: time) - amount)
        since = time
    }
}
