import Foundation
import os

/// 閒晃的資料：每種活動的權重、冷卻時間、待多久（遊戲設計：行為、權重與冷卻時間寫成資料，調整時不用改程式）。
///
/// 每隻各一份（作者 2026-11-19 決定兩隻各自獨立）：角色包的 `wander.json`，由私有素材 repo 匯出。
/// 公開 repo 的 `Resources/wander.json` 是預設，給沒有角色包、或角色包沒帶這個檔的那隻。數字在實機上調。
/// 秒數、格數都寫成範圍 `[最少, 最多]`，每次在範圍裡隨機挑。
///
/// - `version`：格式版本，目前是 2。第 1 版的 `pace` 寫成 `walk`、`trot`（企鵝的慢走、小跑），也讀得懂。
/// - `pace`：移動時慢（`slow`）、快（`fast`）的權重，不分物種（ADR 0009）。平常慢，偶爾快。
/// - `breaks`（可以不寫）：路長的時候，每走 `everyTiles` 格停一下，停 `seconds` 秒（「走幾步就停一下」）。
/// - `glanceFacings`：東張西望時會看哪些方向（`front`、`frontLeft`、`backLeft`、`frontRight`、`backRight`）。
/// - `activities`：每種活動。共同的欄位是 `id`（不能重複，冷卻用它記）、`kind`、`weight`（權重，0 是不做）、
///   `cooldown`（秒：開始做之後多久內不再挑它）、`seconds`；各種活動另外的欄位：
///   - `visit`：走到 `target`（`bed`、`sofa`、`window`、`storageBox`）旁邊，面向它待 `seconds` 秒。
///   - `stroll`：隨便走走，走到 `tiles` 步遠的地方，停 `seconds` 秒。
///   - `zoneOut`：發呆，原地站 `seconds` 秒。`facing` 不寫就維持原本的方向（作者 2026-11-19 決定）。
///   - `lookAround`：東張西望，連續看 `glances` 個方向，每個看 `seconds` 秒。
///   - `stayClose`：走去黏著另一隻：走到牠旁邊緊鄰的一格，面向牠待 `seconds` 秒（作者 2026-11-19 決定）。
///     牠正在走的話，走去牠要去的那一格旁邊。台上只有自己時不挑。
nonisolated struct WanderConfig: Decodable, Equatable, Sendable {
    static let supportedVersion = 2

    enum Kind: String, Decodable, Sendable {
        case visit, stroll, zoneOut, lookAround, stayClose
    }

    struct Activity: Decodable, Equatable, Sendable {
        var id: String
        var kind: Kind
        var weight: Double
        var cooldown: Double
        var seconds: ClosedRange<Double>
        /// `visit` 走去哪。
        var target: FurnitureKind? = nil
        /// `stroll` 走幾步遠。
        var tiles: ClosedRange<Int>? = nil
        /// `lookAround` 看幾個方向。
        var glances: ClosedRange<Int>? = nil
        /// `zoneOut` 轉向哪裡；nil 維持原本的方向。
        var facing: Facing? = nil
    }

    struct PaceWeights: Equatable, Sendable {
        var slow: Double
        var fast: Double
    }

    struct Breaks: Decodable, Equatable, Sendable {
        var everyTiles: ClosedRange<Int>
        var seconds: ClosedRange<Double>
    }

    var version: Int
    var pace: PaceWeights
    var breaks: Breaks? = nil
    var glanceFacings: [Facing] = []
    var activities: [Activity]

    static func decode(_ data: Data) throws -> WanderConfig {
        let config = try JSONDecoder().decode(WanderConfig.self, from: data)
        try config.validate()
        return config
    }

    /// 檢查數字合不合理；不合理時丟出 `WanderConfigError`，說明是哪個欄位。
    func validate() throws {
        guard (1...Self.supportedVersion).contains(version) else { throw WanderConfigError.unsupportedVersion(version) }
        guard pace.slow >= 0, pace.fast >= 0, pace.slow + pace.fast > 0 else { throw WanderConfigError.invalid("pace") }
        if let breaks {
            guard breaks.everyTiles.lowerBound >= 1, breaks.seconds.lowerBound >= 0 else {
                throw WanderConfigError.invalid("breaks")
            }
        }
        guard activities.contains(where: { $0.weight > 0 }) else { throw WanderConfigError.invalid("activities") }
        var ids: Set<String> = []
        for activity in activities {
            let name = activity.id
            guard ids.insert(name).inserted else { throw WanderConfigError.invalid("\(name).id") }
            guard activity.weight >= 0 else { throw WanderConfigError.invalid("\(name).weight") }
            guard activity.cooldown >= 0 else { throw WanderConfigError.invalid("\(name).cooldown") }
            guard activity.seconds.lowerBound >= 0 else { throw WanderConfigError.invalid("\(name).seconds") }
            switch activity.kind {
            case .visit:
                guard activity.target != nil else { throw WanderConfigError.invalid("\(name).target") }
            case .stroll:
                guard let tiles = activity.tiles, tiles.lowerBound >= 1 else { throw WanderConfigError.invalid("\(name).tiles") }
            case .zoneOut, .stayClose:
                break
            case .lookAround:
                guard let glances = activity.glances, glances.lowerBound >= 1 else {
                    throw WanderConfigError.invalid("\(name).glances")
                }
                // 連續兩眼要看不同方向，所以至少要兩個
                guard Set(glanceFacings).count >= 2 else { throw WanderConfigError.invalid("glanceFacings") }
            }
        }
    }

    private static let log = Logger(subsystem: "PenguinFamily", category: "Wander")

    /// App 裡的預設 `wander.json`。讀不到或內容不合理時是 nil（沒帶自己閒晃資料的角色只站著）；`WanderTests` 守著這個檔案。
    static func bundled(_ bundle: Bundle = .main) -> WanderConfig? {
        do {
            guard let url = bundle.url(forResource: "wander", withExtension: "json") else {
                log.error("找不到 wander.json")
                return nil
            }
            return try decode(Data(contentsOf: url))
        } catch {
            log.error("wander.json 讀取失敗：\(String(describing: error))")
            return nil
        }
    }
}

nonisolated extension WanderConfig {
    private enum CodingKeys: String, CodingKey {
        case version, pace, breaks, glanceFacings, activities
    }

    private enum PaceKeys: String, CodingKey {
        case slow, fast
        /// 第 1 版的名稱（企鵝的慢走、小跑）。
        case walk, trot
    }

    /// 自動產生的解碼只讓 Optional 的欄位可以不寫；`glanceFacings` 沒有東張西望時可以不寫，所以自己解。
    /// `pace` 照版本讀：第 1 版是 `walk`、`trot`，第 2 版是 `slow`、`fast`。
    /// 寫在 extension 裡，保留逐欄位的建構式（測試用）。
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let version = try c.decode(Int.self, forKey: .version)
        let p = try c.nestedContainer(keyedBy: PaceKeys.self, forKey: .pace)
        let pace = version == 1
            ? PaceWeights(slow: try p.decode(Double.self, forKey: .walk), fast: try p.decode(Double.self, forKey: .trot))
            : PaceWeights(slow: try p.decode(Double.self, forKey: .slow), fast: try p.decode(Double.self, forKey: .fast))
        self.init(version: version,
                  pace: pace,
                  breaks: try c.decodeIfPresent(Breaks.self, forKey: .breaks),
                  glanceFacings: try c.decodeIfPresent([Facing].self, forKey: .glanceFacings) ?? [],
                  activities: try c.decode([Activity].self, forKey: .activities))
    }
}

nonisolated enum WanderConfigError: Error, Equatable {
    case unsupportedVersion(Int)
    /// 哪個欄位不合理，例如 `window.target`。
    case invalid(String)
}
