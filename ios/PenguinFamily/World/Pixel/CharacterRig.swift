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

nonisolated enum CharacterRigError: Error, Equatable {
    case unsupportedFormat(Int)
    case invalidCode(String)
    case missingPart(String)
    case missingPivot(String)
    case missingAnchor(String)
    case unknownCode(part: String, code: Character)
    case partOutOfCanvas(String)
}
