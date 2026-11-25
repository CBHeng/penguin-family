import Foundation

/// 向量角色包（`vector.json`，ADR 0007）：每個方向（與姿勢，ADR 0011）的部件形狀、轉軸、畫的順序與外框顏色。
///
/// 由私有素材 repo 的 `vector/export.js` 產生。形狀只有兩種：橢圓，和只有直線、三次曲線的路徑
/// （弧線、二次曲線在匯出時就轉好了），App 這邊不用解析 SVG。
/// 座標的單位和箱庭相同（企鵝約 38 單位寬，一格地板 32×16 單位），角色畫布左上角為原點，y 往下。
///
/// 不分物種（ADR 0009）：部件叫什麼、有幾個由角色包決定，這裡不要求特定部件。
/// 部件怎麼動是動作資料（`CharacterMotions`）的事；讀角色包時再檢查片段用到的部件這裡都有。
/// 匯出的檔可能還帶著私有素材 repo 的算式用的欄位（例如 `neckY`、`walk`、`anchors`），App 不讀。
nonisolated struct VectorRig: Decodable, Sendable {
    static let supportedFormat = 1

    let format: Int
    let outline: Outline
    /// 畫好的方向：`front`，和斜向的 `frontLeft`、`backLeft`（名稱和 `Facing` 相同）。
    let facings: [String: Facing]
    /// 翻轉的方向：右邊由左邊左右翻轉，不另外存形狀，貼圖也共用。
    let mirrors: [String: Mirror]
    /// 姿勢（ADR 0011）：方向之外另外畫的造型，例如躺在床上（`lieBack`）。沒有方向、不翻轉；動作的片段指定用哪個。
    let postures: [String: Facing]

    private enum CodingKeys: String, CodingKey { case format, outline, facings, mirrors, postures }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        format = try c.decode(Int.self, forKey: .format)
        outline = try c.decode(Outline.self, forKey: .outline)
        facings = try c.decode([String: Facing].self, forKey: .facings)
        mirrors = try c.decodeIfPresent([String: Mirror].self, forKey: .mirrors) ?? [:]
        postures = try c.decodeIfPresent([String: Facing].self, forKey: .postures) ?? [:]
    }

    /// 由程式組出來的造型（例如借別隻的形狀塗灰，見 `graySilhouette()`）。
    init(format: Int = supportedFormat, outline: Outline, facings: [String: Facing], mirrors: [String: Mirror],
         postures: [String: Facing] = [:]) {
        self.format = format
        self.outline = outline
        self.facings = facings
        self.mirrors = mirrors
        self.postures = postures
    }

    struct Outline: Decodable, Sendable {
        let color: String
        /// 外框露在形狀外面的寬度（單位）。
        let width: Double
    }

    struct Point: Decodable, Equatable, Sendable {
        let x: Double
        let y: Double
    }

    struct Size: Decodable, Equatable, Sendable {
        let width: Double
        let height: Double
    }

    /// 一個畫好的方向或姿勢。
    struct Facing: Decodable, Sendable {
        let canvas: Size
        /// 腳底中心：放到箱庭上的那一點；翻轉的方向以這裡為軸。姿勢是放在家具上的那一點（例如床位）。
        let feet: Point
        /// 由後往前畫的部件名稱。
        let drawOrder: [String]
        let parts: [String: Part]
        /// 畫在角色底下的半透明影子（ADR 0011）；沒有是 nil。
        var shadow: Shadow? = nil
        /// 觸控範圍（ADR 0011）：畫布上的凸多邊形；nil 用整張畫布。兩隻躺在一起時畫布重疊很多，會點到錯的那隻。
        var touch: [Point]? = nil
    }

    /// 半透明的影子：形狀合成一張再乘不透明度（重疊處不會變深），畫在外框之前，不跟著部件動。
    struct Shadow: Decodable, Sendable {
        let color: String
        let opacity: Double
        let shapes: [Shape]

        /// 畫成貼圖用：只有一層顏色、不描外框的部件。
        var part: Part {
            Part(pivot: Point(x: 0, y: 0), silhouette: [],
                 layers: [Layer(fill: color, stroke: nil, width: nil, shapes: shapes, clip: nil)])
        }
    }

    /// 翻轉的方向：把 `of` 以腳底中心左右翻轉。部件先照 `shift` 挪（翻轉前的座標，例如帽子不跟著翻），
    /// 畫的先後照自己的 `drawOrder`（例如帽子改畫在頭後面）。
    struct Mirror: Decodable, Sendable {
        let of: String
        let drawOrder: [String]
        let shift: [String: Point]
    }

    /// 某個方向實際怎麼畫：用哪個畫好的方向的部件（貼圖）、畫的先後、要不要翻轉。
    struct Look: Sendable {
        let source: String
        let drawOrder: [String]
        let mirror: Mirror?
    }

    static let obliqueNames = ["frontLeft", "backLeft", "frontRight", "backRight"]

    struct Part: Decodable, Sendable {
        /// 轉軸。
        let pivot: Point
        /// 外形：描外框用（先用外框色加粗描一次，再畫顏色）。可以是空的（ADR 0010）：那個部件不描共用的外框，
        /// 例如畫在頭上的眼睛；畫在別的部件前面、要自己有外框的部件，在顏色層裡加一層外框色的描線。
        let silhouette: [Shape]
        /// 由下往上畫的顏色層。
        let layers: [Layer]
        /// 平常藏起來（ADR 0010）：片段說要顯示時才畫，例如閉眼、坐著時伸到身體前面的腳。
        var hidden = false

        private enum CodingKeys: String, CodingKey { case pivot, silhouette, layers, hidden }

        init(pivot: Point, silhouette: [Shape], layers: [Layer], hidden: Bool = false) {
            self.pivot = pivot
            self.silhouette = silhouette
            self.layers = layers
            self.hidden = hidden
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            self.init(pivot: try c.decode(Point.self, forKey: .pivot),
                      silhouette: try c.decode([Shape].self, forKey: .silhouette),
                      layers: try c.decode([Layer].self, forKey: .layers),
                      hidden: try c.decodeIfPresent(Bool.self, forKey: .hidden) ?? false)
        }

        /// 這個部件畫得出東西嗎（外形或顏色層至少一個形狀）。
        var hasShapes: Bool { !silhouette.isEmpty || layers.contains { !$0.shapes.isEmpty } }

        /// 檢查顏色與形狀；`label` 是錯誤訊息裡的位置，例如 `front.head`。
        func validate(_ label: String) throws {
            guard hasShapes else { throw VectorRigError.missingPart(label) }
            for layer in layers {
                switch (layer.fill, layer.stroke, layer.width) {
                case let (fill?, nil, _):
                    guard RGBColor(hex: fill) != nil else { throw VectorRigError.invalidColor(fill) }
                case let (nil, stroke?, width?) where width > 0:
                    guard RGBColor(hex: stroke) != nil else { throw VectorRigError.invalidColor(stroke) }
                default:
                    throw VectorRigError.invalidDirection(label)
                }
                guard !layer.shapes.isEmpty, layer.clip?.contains(where: \.isEmpty) != true else {
                    throw VectorRigError.missingPart(label)
                }
            }
        }
    }

    /// 一層：填滿（`fill`）或描線（`stroke`＋`width`），可以只畫在 `clip` 的範圍內：
    /// 每一組的形狀取聯集，好幾組時要同時在每一組裡面（例如肚子的陰影要在肚子裡、也要在身體裡）。
    struct Layer: Decodable, Sendable {
        let fill: String?
        let stroke: String?
        let width: Double?
        let shapes: [Shape]
        let clip: [[Shape]]?
    }

    enum Shape: Decodable, Equatable, Sendable {
        case ellipse(cx: Double, cy: Double, rx: Double, ry: Double)
        case path([PathCommand])

        private enum Keys: String, CodingKey { case ellipse, path }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: Keys.self)
            if let e = try c.decodeIfPresent([Double].self, forKey: .ellipse) {
                guard e.count == 4, e[2] > 0, e[3] > 0 else {
                    throw DecodingError.dataCorruptedError(forKey: .ellipse, in: c, debugDescription: "橢圓要有 cx、cy、rx、ry，半徑大於 0")
                }
                self = .ellipse(cx: e[0], cy: e[1], rx: e[2], ry: e[3])
            } else {
                let commands = try c.decode([PathCommand].self, forKey: .path)
                guard case .move = commands.first else {
                    throw DecodingError.dataCorruptedError(forKey: .path, in: c, debugDescription: "路徑要用 M 開頭")
                }
                self = .path(commands)
            }
        }

        /// 外接矩形（路徑用控制點算，可能比實際大一點）。
        var bounds: (minX: Double, minY: Double, maxX: Double, maxY: Double) {
            switch self {
            case let .ellipse(cx, cy, rx, ry):
                return (cx - rx, cy - ry, cx + rx, cy + ry)
            case .path(let commands):
                let points = commands.flatMap(\.points)
                return (points.map(\.x).min() ?? 0, points.map(\.y).min() ?? 0,
                        points.map(\.x).max() ?? 0, points.map(\.y).max() ?? 0)
            }
        }
    }

    /// JSON 裡寫成 `["M", x, y]`、`["L", x, y]`、`["C", x1, y1, x2, y2, x, y]`、`["Z"]`。
    enum PathCommand: Decodable, Equatable, Sendable {
        case move(x: Double, y: Double)
        case line(x: Double, y: Double)
        case curve(x1: Double, y1: Double, x2: Double, y2: Double, x: Double, y: Double)
        case close

        init(from decoder: Decoder) throws {
            var c = try decoder.unkeyedContainer()
            let name = try c.decode(String.self)
            var numbers: [Double] = []
            while !c.isAtEnd { numbers.append(try c.decode(Double.self)) }
            switch (name, numbers.count) {
            case ("M", 2): self = .move(x: numbers[0], y: numbers[1])
            case ("L", 2): self = .line(x: numbers[0], y: numbers[1])
            case ("C", 6): self = .curve(x1: numbers[0], y1: numbers[1], x2: numbers[2], y2: numbers[3], x: numbers[4], y: numbers[5])
            case ("Z", 0): self = .close
            default:
                throw DecodingError.dataCorruptedError(in: c, debugDescription: "不認得的路徑指令 \(name)（\(numbers.count) 個數字）")
            }
        }

        var points: [(x: Double, y: Double)] {
            switch self {
            case let .move(x, y), let .line(x, y): [(x, y)]
            case let .curve(x1, y1, x2, y2, x, y): [(x1, y1), (x2, y2), (x, y)]
            case .close: []
            }
        }
    }

    /// 正面：一定要有。
    var front: Facing { facings["front"]! }

    /// 畫好的方向或姿勢；翻轉的方向與沒有的是 nil。
    func drawn(_ name: String) -> Facing? { facings[name] ?? postures[name] }

    /// 某個方向（`Facing` 的名稱）或姿勢怎麼畫；角色包沒有時是 nil。
    func look(_ name: String) -> Look? {
        if let facing = drawn(name) { return Look(source: name, drawOrder: facing.drawOrder, mirror: nil) }
        guard let mirror = mirrors[name] else { return nil }
        return Look(source: mirror.of, drawOrder: mirror.drawOrder, mirror: mirror)
    }

    /// 身體中央在腳底上方幾個單位：正面畫布的一半高度（鏡頭對準這裡）。
    var bodyCenterAboveFeet: Double {
        front.feet.y - front.canvas.height / 2
    }

    /// 讀進來後檢查內容；有問題就丟錯，不讓壞掉的角色包上台。
    static func decode(_ data: Data) throws -> VectorRig {
        let rig = try JSONDecoder().decode(VectorRig.self, from: data)
        try rig.validate()
        return rig
    }

    func validate() throws {
        guard format == Self.supportedFormat else { throw VectorRigError.unsupportedFormat(format) }
        guard RGBColor(hex: outline.color) != nil, outline.width > 0 else { throw VectorRigError.invalidColor(outline.color) }
        guard facings["front"] != nil else { throw VectorRigError.invalidDirection("front") }
        for (name, facing) in facings {
            guard name == "front" || Self.obliqueNames.contains(name) else { throw VectorRigError.invalidDirection(name) }
            try validate(facing, name)
        }
        for (name, posture) in postures {
            // 姿勢不能和方向同名
            guard name != "front", !Self.obliqueNames.contains(name) else { throw VectorRigError.invalidDirection(name) }
            try validate(posture, name)
        }
        for (name, mirror) in mirrors {
            guard Self.obliqueNames.contains(name), facings[name] == nil, mirror.of != "front",
                  let source = facings[mirror.of],
                  mirror.drawOrder.count == source.parts.count, Set(mirror.drawOrder) == Set(source.parts.keys),
                  mirror.shift.keys.allSatisfy({ source.parts[$0] != nil })
            else { throw VectorRigError.invalidDirection(name) }
        }
    }

    /// 一個畫好的方向或姿勢：部件剛好列一次、每個部件畫得出來、影子與觸控範圍合理。
    private func validate(_ facing: Facing, _ name: String) throws {
        guard !facing.drawOrder.isEmpty, facing.drawOrder.count == facing.parts.count,
              Set(facing.drawOrder) == Set(facing.parts.keys)
        else { throw VectorRigError.invalidDirection(name) }
        for (partName, part) in facing.parts {
            do {
                try part.validate("\(name).\(partName)")
            } catch VectorRigError.missingPart {
                throw VectorRigError.missingPart(partName)
            }
        }
        if let shadow = facing.shadow {
            guard RGBColor(hex: shadow.color) != nil else { throw VectorRigError.invalidColor(shadow.color) }
            guard !shadow.shapes.isEmpty, shadow.opacity > 0, shadow.opacity <= 1 else {
                throw VectorRigError.invalidDirection("\(name).shadow")
            }
        }
        if let touch = facing.touch, touch.count < 3 { throw VectorRigError.invalidDirection("\(name).touch") }
    }
}

// MARK: - 部件的矩陣

/// 平面上的仿射變換：x' = a·x + c·y + tx、y' = b·x + d·y + ty（和 Core Graphics、SVG 的 matrix() 相同）。
/// 角度正值是畫面上的順時針（y 往下）。算式和私有素材 repo 的 `vector.js` 一樣，在關鍵影格上才會得到相同的矩陣。
nonisolated struct Affine2D: Equatable, Sendable {
    var a: Double, b: Double, c: Double, d: Double, tx: Double, ty: Double

    static let identity = Affine2D(a: 1, b: 0, c: 0, d: 1, tx: 0, ty: 0)

    static func translation(_ x: Double, _ y: Double) -> Affine2D { Affine2D(a: 1, b: 0, c: 0, d: 1, tx: x, ty: y) }
    static func scale(_ sx: Double, _ sy: Double) -> Affine2D { Affine2D(a: sx, b: 0, c: 0, d: sy, tx: 0, ty: 0) }
    static func rotation(degrees: Double) -> Affine2D {
        let r = degrees * (Double.pi / 180)
        return Affine2D(a: cos(r), b: sin(r), c: -sin(r), d: cos(r), tx: 0, ty: 0)
    }

    /// 先套 `n`、再套 `m`。
    static func * (m: Affine2D, n: Affine2D) -> Affine2D {
        Affine2D(a: m.a * n.a + m.c * n.b, b: m.b * n.a + m.d * n.b,
                 c: m.a * n.c + m.c * n.d, d: m.b * n.c + m.d * n.d,
                 tx: m.a * n.tx + m.c * n.ty + m.tx, ty: m.b * n.tx + m.d * n.ty + m.ty)
    }

    /// 以某一點為中心套用 `m`（例如繞轉軸旋轉）。
    static func around(_ p: VectorRig.Point, _ m: Affine2D) -> Affine2D {
        translation(p.x, p.y) * (m * translation(-p.x, -p.y))
    }

    func apply(_ x: Double, _ y: Double) -> (x: Double, y: Double) {
        (a * x + c * y + tx, b * x + d * y + ty)
    }
}

extension VectorRig {
    /// 某一格的樣子 → 怎麼畫與每個部件的矩陣；角色包沒有這個方向時是 nil。
    /// 部件照姿勢以自己的轉軸動，姿勢沒列到的部件在原位（ADR 0009）。
    /// 翻轉的方向：用來源的部件與姿勢，部件先照 `shift` 挪，最後以腳底中心左右翻轉（同 `vector.js` 的 `facingTransforms`）。
    nonisolated func frame(_ pose: CharacterPose) -> (look: Look, transforms: [String: Affine2D])? {
        guard let look = look(pose.look), let source = drawn(look.source) else { return nil }
        var t: [String: Affine2D] = [:]
        for name in source.drawOrder {
            if let part = pose.parts[name], let pivot = source.parts[name]?.pivot {
                t[name] = part.matrix(pivot: pivot)
            } else {
                t[name] = .identity
            }
        }
        guard let mirror = look.mirror else { return (look, t) }
        let flip = Affine2D(a: -1, b: 0, c: 0, d: 1, tx: 2 * source.feet.x, ty: 0)
        var out: [String: Affine2D] = [:]
        for name in look.drawOrder {
            let base = t[name] ?? .identity
            out[name] = flip * (mirror.shift[name].map { base * .translation($0.x, $0.y) } ?? base)
        }
        return (look, out)
    }

    /// 這一格要畫的部件，依畫的先後（ADR 0010）：片段說顯示或藏起來的照片段，其他照造型（`hidden` 的平常藏起來）。
    nonisolated func shownParts(_ look: Look, _ pose: CharacterPose) -> [String] {
        let parts = drawn(look.source)?.parts ?? [:]
        return look.drawOrder.filter { name in pose.shown[name] ?? !(parts[name]?.hidden ?? false) }
    }

    /// 特效放到角色畫布上的矩陣（ADR 0010）：照特效軌道的樣子以特效的轉軸動。
    /// 翻轉的方向只翻位置（轉軸落在哪裡），形狀不翻、轉的方向相反，所以 Z 不會變成反的。
    nonisolated func effectMatrix(_ effect: EffectPose, pivot: Point, look: Look) -> Affine2D {
        let m = effect.pose.matrix(pivot: pivot)
        guard look.mirror != nil, let source = facings[look.source] else { return m }
        let at = m.apply(pivot.x, pivot.y)
        return .translation(2 * source.feet.x - at.x, at.y) * .rotation(degrees: -effect.pose.rotate)
            * .scale(effect.pose.scaleX, effect.pose.scaleY) * .translation(-pivot.x, -pivot.y)
    }
}

/// 角色包壞掉的地方。
nonisolated enum VectorRigError: Error, Equatable {
    case unsupportedFormat(Int)
    case invalidColor(String)
    case missingPart(String)
    /// 方向少了必要的內容，或內容不一致（例如 `drawOrder` 沒有剛好列出每個部件）。
    case invalidDirection(String)
}
