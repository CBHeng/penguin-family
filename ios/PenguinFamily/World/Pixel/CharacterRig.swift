import Foundation

/// 角色包 `rig.json` 的內容：部件像素、轉軸與合成參數。
///
/// 由私有素材 repo 的匯出程式產生，格式見 `docs/architecture.md`。
/// 所有座標都是部件畫布上的格子座標；像素用調色盤代碼表示，一個字元一格。
nonisolated struct CharacterRig: Decodable, Sendable {
    static let supportedFormat = 1

    struct Size: Decodable, Sendable {
        let width: Int
        let height: Int
    }

    struct Part: Decodable, Sendable {
        let x: Int
        let y: Int
        let rows: [String]
        /// 會轉的部件才有：縮放與旋轉的中心。
        let pivot: RigPoint?
        /// 只移動不轉的部件才有：跟著哪個部件移動。
        let follows: String?
        /// 只移動不轉的部件才有：跟著轉的那一點。
        let anchor: RigPoint?
    }

    struct Parameters: Decodable, Sendable {
        /// 身體壓扁時，頭和手跟著下沉的計算基準。
        let neckY: Double
        /// 手的角度超過這個值（絕對值）時，改用舉手的部件。
        let armRaisedAboveDegrees: Double
    }

    struct Front: Decodable, Sendable {
        let x: Int
        let y: Int
        let rows: [String]
    }

    /// 畫布上的一張圖：左上角與每列像素。
    struct Layer: Decodable, Sendable {
        let x: Int
        let y: Int
        let rows: [String]
    }

    /// 斜向四個方向（沿格線走時用）的部件與走法，畫布和正面不同。
    /// 左前、左後帶部件；右前、右後只帶翻轉後另外放的帽子（帽子歪戴在一側，不跟著翻）。
    struct Oblique: Decodable, Sendable {
        let canvas: Size
        /// 腳底中心，和正面的身體轉軸對到同一點，換方向時不會跳。
        let anchor: RigPoint
        /// 身體傾斜時不動的那一列。
        let leanBaseY: Double
        /// 近的手從這一列以下才往外張。
        let shoulderY: Double
        /// 右邊方向的帽子跟著這一列傾斜。
        let hatRow: Int
        /// 方向名稱（`Facing` 的 rawValue）→ 內容。
        let directions: [String: Direction]
    }

    /// 斜向的一個方向。左邊方向有部件與走法；右邊方向有 `mirrorOf` 與帽子。
    struct Direction: Decodable, Sendable {
        let parts: [String: Layer]?
        let drawOrder: [String]?
        /// 往前一步在畫面上是 (x, y) 像素。
        let forward: [Int]?
        /// 畫面左邊的是哪一隻腳（`farFoot` 或 `nearFoot`）。
        let leftFoot: String?
        /// 近的手在身體哪一側：1 右、-1 左。
        let armSide: Int?
        /// 只整塊平移的小部件 → 錨點。
        let rigid: [String: RigPoint]?
        /// 被身體擋住的腳，往後踩時多往下幾格露出來。
        let peek: [String: Int]?
        let mirrorOf: String?
        let hat: Layer?
        /// 定稿圖：部件都不動時，合成結果要和它完全相同。
        let rest: Layer
    }

    let format: Int
    let canvas: Size
    let palette: [String: String]
    let outline: String
    let empty: String
    let drawOrder: [String]
    let parts: [String: Part]
    let rig: Parameters
    /// 定稿正面圖在畫布上的位置與像素：部件都不動時，合成結果要和它完全相同。
    let front: Front
    /// 斜向四個方向；舊的角色包沒有（只能面向鏡頭）。
    let oblique: Oblique?
}

nonisolated struct RigPoint: Decodable, Equatable, Sendable {
    let x: Double
    let y: Double

    init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }

    /// JSON 裡寫成 `[x, y]`。
    init(from decoder: Decoder) throws {
        var c = try decoder.unkeyedContainer()
        x = try c.decode(Double.self)
        y = try c.decode(Double.self)
    }
}

/// 不透明的 sRGB 顏色。
nonisolated struct PixelColor: Hashable, Sendable {
    let red: UInt8
    let green: UInt8
    let blue: UInt8

    /// 解析 `#RRGGBB`。
    init?(hex: String) {
        guard hex.count == 7, hex.first == "#", let value = UInt32(hex.dropFirst(), radix: 16) else { return nil }
        red = UInt8((value >> 16) & 0xFF)
        green = UInt8((value >> 8) & 0xFF)
        blue = UInt8(value & 0xFF)
    }
}

nonisolated enum CharacterRigError: Error, Equatable {
    case unsupportedFormat(Int)
    case invalidCode(String)
    case invalidColor(String)
    case missingPart(String)
    case missingPivot(String)
    case missingAnchor(String)
    case unknownCode(part: String, code: Character)
    case partOutOfCanvas(String)
    /// 斜向少了某個方向，或方向的內容不完整。
    case invalidDirection(String)
}
