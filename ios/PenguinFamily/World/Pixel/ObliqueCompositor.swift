import Foundation

/// 把角色包斜向的部件依姿勢合成一張原始尺寸的像素圖（走路、小跑、斜向站著）。
///
/// 規則照私有素材 repo 的 `compose_oblique_from_rig()`，要逐格得到相同結果：
/// - 全部是整格平移，不旋轉、不縮放（像素才不會碎）：身體各列依高度往旁邊移（傾斜）、上半身下沉、
///   近的手肩膀以下往外張並上下晃、兩隻腳各自平移，嘴、眼睛、絨球、帽子整塊跟著錨點那一列移。
/// - 右前、右後用左邊的部件與同一個姿勢組好（不含帽子）再左右翻轉；帽子不跟著翻，
///   另外放在頭後面（只填空著的格子），跟著頭的傾斜（反方向）與下沉移動。
/// - 外框在全部組好後才描。取整與 Python 的 `round()` 相同，.5 取最近的偶數。
nonisolated struct ObliqueCompositor: Sendable {
    /// 左前、左後：部件與走法。
    private struct Side: Sendable {
        let drawOrder: [String]
        let grids: [String: PixelGrid]
        /// 只整塊平移的小部件 → 跟著哪一列（錨點的列）。
        let rigidRows: [String: Int]
        let walk: WalkSide
    }

    private enum Look: Sendable {
        case side(Side)
        /// 右前、右後：翻轉哪個方向，帽子另外放。
        case mirror(of: Facing, hat: PixelGrid)
    }

    let width: Int
    let height: Int
    /// 腳底在圖上的位置（像素），和正面的取法相同（x 往下取整、y 往上取整）。
    let anchor: PixelPoint
    private let looks: [Facing: Look]
    private let rests: [Facing: PixelGrid]
    private let leanBaseY: Double
    private let shoulderY: Double
    private let hatRow: Int
    private let outline: Character

    /// 角色包沒有斜向時是 nil；內容不完整時丟錯。
    init?(rig: CharacterRig) throws {
        guard let ob = rig.oblique else { return nil }
        let empty = Character(rig.empty)
        let palette = Set(rig.palette.keys.compactMap(\.first))
        width = ob.canvas.width
        height = ob.canvas.height
        anchor = PixelPoint(x: Int(ob.anchor.x.rounded(.down)), y: Int(ob.anchor.y.rounded(.up)))
        leanBaseY = ob.leanBaseY
        shoulderY = ob.shoulderY
        hatRow = ob.hatRow
        outline = Character(rig.outline)

        func grid(_ layer: CharacterRig.Layer, _ name: String) throws -> PixelGrid {
            var grid = PixelGrid(width: ob.canvas.width, height: ob.canvas.height)
            for (j, line) in layer.rows.enumerated() {
                for (i, c) in line.enumerated() where c != empty {
                    guard palette.contains(c) else { throw CharacterRigError.unknownCode(part: name, code: c) }
                    guard grid.contains(layer.x + i, layer.y + j) else { throw CharacterRigError.partOutOfCanvas(name) }
                    grid[layer.x + i, layer.y + j] = c
                }
            }
            return grid
        }

        var looks: [Facing: Look] = [:]
        var rests: [Facing: PixelGrid] = [:]
        for facing in Facing.oblique {
            guard let d = ob.directions[facing.rawValue] else { throw CharacterRigError.invalidDirection(facing.rawValue) }
            rests[facing] = try grid(d.rest, "\(facing.rawValue).rest")
            if let source = d.mirrorOf {
                guard let of = Facing(rawValue: source), let hat = d.hat, ob.directions[source]?.mirrorOf == nil
                else { throw CharacterRigError.invalidDirection(facing.rawValue) }
                looks[facing] = .mirror(of: of, hat: try grid(hat, "\(facing.rawValue).hat"))
                continue
            }
            guard let parts = d.parts, let order = d.drawOrder, let forward = d.forward, forward.count == 2,
                  let leftFoot = d.leftFoot, let armSide = d.armSide, parts["arm"] != nil,
                  let rightFoot = [Self.farFoot, Self.nearFoot].first(where: { $0 != leftFoot }),
                  [Self.farFoot, Self.nearFoot].contains(leftFoot), order.allSatisfy({ parts[$0] != nil })
            else { throw CharacterRigError.invalidDirection(facing.rawValue) }
            var grids: [String: PixelGrid] = [:]
            for (name, layer) in parts { grids[name] = try grid(layer, name) }
            looks[facing] = .side(Side(
                drawOrder: order, grids: grids,
                rigidRows: (d.rigid ?? [:]).mapValues { Int($0.y.rounded(.down)) },
                walk: WalkSide(forward: (forward[0], forward[1]), leftFoot: leftFoot, rightFoot: rightFoot,
                               armSide: armSide, peek: d.peek ?? [:])))
        }
        self.looks = looks
        self.rests = rests
    }

    static let farFoot = "farFoot"
    static let nearFoot = "nearFoot"

    /// 某個斜向方向怎麼走（右邊方向回傳翻轉前那一邊的走法，姿勢照它算）。
    func walkSide(_ facing: Facing) -> WalkSide? {
        switch looks[facing] {
        case .side(let side): side.walk
        case .mirror(let of, _): walkSide(of)
        case nil: nil
        }
    }

    /// 定稿圖放在畫布上的樣子，用來和 `compose(_, .rest)` 比對。
    func restGrid(_ facing: Facing) -> PixelGrid? { rests[facing] }

    /// 斜向一格（已描外框）。不是斜向的方向回傳 nil。
    func compose(_ facing: Facing, _ pose: WalkPose) -> PixelGrid? {
        var out: PixelGrid
        switch looks[facing] {
        case .side(let side):
            out = place(side, pose)
        case .mirror(let of, let hat):
            guard case .side(let side) = looks[of] else { return nil }
            let placed = place(side, pose, skipping: "hat")
            out = PixelGrid(width: width, height: height)
            for y in 0..<height {
                for x in 0..<width { out[x, y] = placed[width - 1 - x, y] }
            }
            // 帽子：翻轉後往反方向傾，只填空著的格子（畫在頭後面）
            let dx = -leanShift(row: Double(hatRow), pose.lean)
            for y in 0..<height {
                for x in 0..<width where out[x, y] == nil {
                    let sx = x - dx, sy = y - pose.dip
                    if hat.contains(sx, sy), let c = hat[sx, sy] { out[x, y] = c }
                }
            }
        case nil:
            return nil
        }
        drawOutline(on: &out)
        return out
    }

    // MARK: - 規則

    /// 身體傾斜時這一列往右移幾格：腳底那一列不動，越上面移越多。
    private func leanShift(row: Double, _ lean: Double) -> Int {
        RigCompositor.roundHalfEven(lean * (leanBaseY - (row + 0.5)))
    }

    private func place(_ side: Side, _ pose: WalkPose, skipping skip: String? = nil) -> PixelGrid {
        var out = PixelGrid(width: width, height: height)
        for name in side.drawOrder where name != skip {
            guard let src = side.grids[name] else { continue }
            let source: (Int, Int) -> (Int, Int)
            if name == Self.farFoot || name == Self.nearFoot {
                let offset = pose.feet[name] ?? WalkPose.Offset(dx: 0, dy: 0)
                source = { x, y in (x - offset.dx, y - offset.dy) }
            } else if let row = side.rigidRows[name] {
                // 小部件整塊跟著錨點那一列移，不跟著斜
                let dx = leanShift(row: Double(row), pose.lean)
                source = { x, y in (x - dx, y - pose.dip) }
            } else if name == "arm" {
                source = { x, y in
                    let sy = y - pose.dip - pose.armDy
                    var sx = x - leanShift(row: Double(sy), pose.lean)
                    if Double(sy) + 0.5 > shoulderY {
                        sx -= side.walk.armSide * RigCompositor.roundHalfEven(pose.armOpen * (Double(sy) + 0.5 - shoulderY))
                    }
                    return (sx, sy)
                }
            } else {
                source = { x, y in
                    let sy = y - pose.dip
                    return (x - leanShift(row: Double(sy), pose.lean), sy)
                }
            }
            for y in 0..<height {
                for x in 0..<width {
                    let (ix, iy) = source(x, y)
                    if src.contains(ix, iy), let c = src[ix, iy] { out[x, y] = c }
                }
            }
        }
        return out
    }

    /// 透明格只要上下左右有非外框的像素，就描成外框（同 `RigCompositor`）。
    private func drawOutline(on out: inout PixelGrid) {
        var edge: [(Int, Int)] = []
        for y in 0..<out.height {
            for x in 0..<out.width where out[x, y] == nil {
                let near = [(x + 1, y), (x - 1, y), (x, y + 1), (x, y - 1)]
                if near.contains(where: { out.contains($0.0, $0.1) && out[$0.0, $0.1].map { $0 != outline } == true }) {
                    edge.append((x, y))
                }
            }
        }
        for (x, y) in edge { out[x, y] = outline }
    }
}
