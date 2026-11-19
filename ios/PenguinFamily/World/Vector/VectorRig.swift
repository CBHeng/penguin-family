import Foundation

/// 向量角色包（`vector.json`，ADR 0007）：每個方向的部件形狀、轉軸、畫的順序與外框顏色。
///
/// 由私有素材 repo 的 `vector/export.js` 產生。形狀只有兩種：橢圓，和只有直線、三次曲線的路徑
/// （弧線、二次曲線在匯出時就轉好了），App 這邊不用解析 SVG。
/// 座標的單位和箱庭相同（一個單位等於原本像素版的一格），角色畫布左上角為原點，y 往下。
nonisolated struct VectorRig: Decodable, Sendable {
    static let supportedFormat = 1

    let format: Int
    let outline: Outline
    /// 畫好的方向：`front`，和斜向的 `frontLeft`、`backLeft`（名稱和 `Facing` 相同）。
    let facings: [String: Facing]
    /// 翻轉的方向：右邊由左邊左右翻轉，不另外存形狀，貼圖也共用。
    let mirrors: [String: Mirror]

    private enum CodingKeys: String, CodingKey { case format, outline, facings, mirrors }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        format = try c.decode(Int.self, forKey: .format)
        outline = try c.decode(Outline.self, forKey: .outline)
        facings = try c.decode([String: Facing].self, forKey: .facings)
        mirrors = try c.decodeIfPresent([String: Mirror].self, forKey: .mirrors) ?? [:]
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

    /// 一個畫好的方向。
    struct Facing: Decodable, Sendable {
        let canvas: Size
        /// 腳底中心：放到箱庭上的那一點，也是身體壓扁的基準；翻轉的方向以這裡為軸。
        let feet: Point
        /// 正面才有：身體變矮時，頭和手往下移的量以這條線算。
        let neckY: Double?
        /// 斜向才有：怎麼走。
        let walk: Walk?
        /// 由後往前畫的部件名稱。
        let drawOrder: [String]
        let parts: [String: Part]
    }

    /// 斜向怎麼走（同像素版 `walk.py` 的 Direction）：往前一個步幅單位在畫面上是 `forward` 單位、畫面左邊是哪隻腳、
    /// 近的手在身體哪側（1 右、-1 左）、哪隻腳往後踩時多往下露（每往後一個單位露幾個單位）。
    struct Walk: Decodable, Sendable {
        let forward: Point
        let leftFoot: String
        let armSide: Int
        let peek: [String: Double]
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

    /// 斜向的腳。
    static let feetParts = ["farFoot", "nearFoot"]
    static let obliqueNames = ["frontLeft", "backLeft", "frontRight", "backRight"]

    struct Part: Decodable, Sendable {
        /// 轉軸。
        let pivot: Point
        /// 外形：描外框用（先用外框色加粗描一次，再畫顏色）。
        let silhouette: [Shape]
        /// 由下往上畫的顏色層。
        let layers: [Layer]
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

    /// 正面：哈囉會動到的三個部件一定要有。
    var front: Facing { facings["front"]! }

    /// 某個方向（`Facing` 的名稱）怎麼畫；角色包沒有這個方向時是 nil。
    func look(_ name: String) -> Look? {
        if let facing = facings[name] { return Look(source: name, drawOrder: facing.drawOrder, mirror: nil) }
        guard let mirror = mirrors[name] else { return nil }
        return Look(source: mirror.of, drawOrder: mirror.drawOrder, mirror: mirror)
    }

    /// 斜向怎麼走；翻轉的方向用來源的（姿勢在翻轉前算）。
    func walk(_ name: String) -> Walk? {
        look(name).flatMap { facings[$0.source]?.walk }
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
        guard let front = facings["front"], front.neckY != nil else { throw VectorRigError.invalidDirection("front") }
        for part in ["body", "arm", "head"] where front.parts[part] == nil {
            throw VectorRigError.missingPart(part)
        }
        for (name, facing) in facings {
            guard facing.drawOrder.count == facing.parts.count, Set(facing.drawOrder) == Set(facing.parts.keys) else {
                throw VectorRigError.invalidDirection(name)
            }
            if name != "front" {
                // 斜向：走路會動到身體、手、頭與兩隻腳
                guard Self.obliqueNames.contains(name), let walk = facing.walk, Self.feetParts.contains(walk.leftFoot),
                      abs(walk.armSide) == 1, walk.peek.keys.allSatisfy(Self.feetParts.contains)
                else { throw VectorRigError.invalidDirection(name) }
                for part in ["body", "arm", "head"] + Self.feetParts where facing.parts[part] == nil {
                    throw VectorRigError.missingPart(part)
                }
            }
            for (partName, part) in facing.parts {
                guard !part.silhouette.isEmpty else { throw VectorRigError.missingPart(partName) }
                for layer in part.layers {
                    switch (layer.fill, layer.stroke, layer.width) {
                    case let (fill?, nil, _):
                        guard RGBColor(hex: fill) != nil else { throw VectorRigError.invalidColor(fill) }
                    case let (nil, stroke?, width?) where width > 0:
                        guard RGBColor(hex: stroke) != nil else { throw VectorRigError.invalidColor(stroke) }
                    default:
                        throw VectorRigError.invalidDirection("\(name).\(partName)")
                    }
                    guard !layer.shapes.isEmpty, layer.clip?.contains(where: \.isEmpty) != true else {
                        throw VectorRigError.missingPart(partName)
                    }
                }
            }
        }
        for (name, mirror) in mirrors {
            guard Self.obliqueNames.contains(name), facings[name] == nil, mirror.of != "front",
                  let source = facings[mirror.of],
                  mirror.drawOrder.count == source.parts.count, Set(mirror.drawOrder) == Set(source.parts.keys),
                  mirror.shift.keys.allSatisfy({ source.parts[$0] != nil })
            else { throw VectorRigError.invalidDirection(name) }
        }
    }
}

// MARK: - 某一格的樣子

/// 向量企鵝某一格的樣子：正面（站著、哈囉）或斜向（站著、走路）。
nonisolated enum VectorPose: Equatable, Sendable {
    case front(RigPose)
    case oblique(Facing, VectorWalkPose)

    var facing: Facing {
        switch self {
        case .front: .front
        case .oblique(let facing, _): facing
        }
    }
}

// MARK: - 姿勢 → 每個部件的矩陣

/// 平面上的仿射變換：x' = a·x + c·y + tx、y' = b·x + d·y + ty（和 Core Graphics、SVG 的 matrix() 相同）。
/// 角度正值是畫面上的順時針（y 往下）。算式和私有素材 repo 的 `vector.js` 一樣，逐格比對才會相同。
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

extension VectorRig.Facing {
    /// 正面的姿勢 → 每個部件的矩陣（沒列到的部件不動）。
    ///
    /// 和像素版的連動相同：身體以腳底為基準壓扁（寬度用 1 / 高度）；身體變矮，頭和手跟著往下；身體變寬，手跟著往外。
    /// 像素版的往下、往外要取整數格，這裡不取整數。
    nonisolated func frontTransforms(_ pose: RigPose) -> [String: Affine2D] {
        var out = Dictionary(uniqueKeysWithValues: drawOrder.map { ($0, Affine2D.identity) })
        guard let body = parts["body"], let arm = parts["arm"], let head = parts["head"] else { return out }
        let sx = 1 / pose.squash, sy = pose.squash
        let drop = (body.pivot.y - (neckY ?? body.pivot.y)) * (1 - sy)
        let armOut = (arm.pivot.x - body.pivot.x) * (sx - 1)
        out["body"] = .around(body.pivot, .scale(sx, sy))
        out["arm"] = .translation(armOut, drop) * .around(arm.pivot, .rotation(degrees: pose.armDegrees))
        out["head"] = .translation(0, drop) * .around(head.pivot, .rotation(degrees: pose.headDegrees))
        return out
    }

    /// 斜向的姿勢 → 每個部件的矩陣（畫好的那一邊）。
    /// 上半身（腳以外）以身體的轉軸（腳底）傾斜再往下沉；近的手先以肩膀往外張開；腳只平移。
    nonisolated func obliqueTransforms(_ pose: VectorWalkPose) -> [String: Affine2D] {
        guard let body = parts["body"], let arm = parts["arm"], let walk else {
            return Dictionary(uniqueKeysWithValues: drawOrder.map { ($0, Affine2D.identity) })
        }
        let sway = Affine2D.around(body.pivot, .rotation(degrees: pose.swayDegrees))
        let upper = Affine2D.translation(0, pose.dip) * sway
        var out = Dictionary(uniqueKeysWithValues: drawOrder.map { ($0, upper) })
        // 手在右側（armSide 1）往外是往右：下面往右等於逆時針
        out["arm"] = .translation(0, pose.dip + pose.armDy)
            * (sway * .around(arm.pivot, .rotation(degrees: -Double(walk.armSide) * pose.armOpenDegrees)))
        for name in VectorRig.feetParts {
            let offset = pose.feet[name]
            out[name] = .translation(offset?.dx ?? 0, offset?.dy ?? 0)
        }
        return out
    }
}

extension VectorRig {
    /// 某一格的樣子 → 怎麼畫與每個部件的矩陣；角色包沒有這個方向時是 nil。
    /// 翻轉的方向：部件先照 `shift` 挪，再套來源的姿勢，最後以腳底中心左右翻轉（同 `vector.js` 的 `facingTransforms`）。
    nonisolated func frame(_ pose: VectorPose) -> (look: Look, transforms: [String: Affine2D])? {
        switch pose {
        case .front(let p):
            guard let look = look("front"), let front = facings["front"] else { return nil }
            return (look, front.frontTransforms(p))
        case .oblique(let facing, let p):
            guard facing != .front, let look = look(facing.rawValue), let source = facings[look.source] else { return nil }
            let t = source.obliqueTransforms(p)
            guard let mirror = look.mirror else { return (look, t) }
            let flip = Affine2D(a: -1, b: 0, c: 0, d: 1, tx: 2 * source.feet.x, ty: 0)
            var out: [String: Affine2D] = [:]
            for name in look.drawOrder {
                let base = t[name] ?? .identity
                out[name] = flip * (mirror.shift[name].map { base * .translation($0.x, $0.y) } ?? base)
            }
            return (look, out)
        }
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
