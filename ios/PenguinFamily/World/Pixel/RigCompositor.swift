import Foundation

/// 合成一格畫面要的姿勢。
nonisolated struct RigPose: Equatable, Sendable {
    /// 頭的角度，正值順時針。
    var headDegrees: Double = 0
    /// 手的角度，正值順時針。
    var armDegrees: Double = 0
    /// 身體高度比例；寬度用倒數撐開，讓體積看起來差不多。
    var squash: Double = 1

    static let rest = RigPose()
}

/// 把角色包的部件依姿勢合成一張原始尺寸的像素圖。
///
/// 規則照私有素材 repo 的 `compose_from_rig()`，要逐格得到相同結果：
/// - 身體、手、頭在原始像素尺寸上縮放或旋轉，逐格反查來源像素。
/// - 帽子、嘴巴、眼睛等跟著頭的部件只移動、不轉，避免小形狀被轉碎。
/// - 外框在全部部件組好後才描。
/// - 取整與 Python 的 `round()` 相同，.5 取最近的偶數。
nonisolated struct RigCompositor: Sendable {
    let rig: CharacterRig
    /// 調色盤代碼對應的顏色。
    let colors: [Character: PixelColor]
    private let grids: [String: PixelGrid]
    private let outline: Character

    init(rig: CharacterRig) throws {
        guard rig.format == CharacterRig.supportedFormat else {
            throw CharacterRigError.unsupportedFormat(rig.format)
        }
        let codes = try Self.singleCharacters(Array(rig.palette.keys) + [rig.outline, rig.empty])
        let empty = Character(rig.empty)
        let palette = Set(codes.dropLast())
        var colors: [Character: PixelColor] = [:]
        for (code, hex) in rig.palette {
            guard let color = PixelColor(hex: hex) else { throw CharacterRigError.invalidColor(hex) }
            colors[Character(code)] = color
        }
        guard colors[Character(rig.outline)] != nil else { throw CharacterRigError.invalidCode(rig.outline) }

        for name in ["body", "arm", "armRaised", "head"] {
            guard let part = rig.parts[name] else { throw CharacterRigError.missingPart(name) }
            guard part.pivot != nil else { throw CharacterRigError.missingPivot(name) }
        }
        var grids: [String: PixelGrid] = [:]
        for (name, part) in rig.parts {
            if let target = part.follows {
                guard rig.parts[target] != nil else { throw CharacterRigError.missingPart(target) }
                guard part.anchor != nil else { throw CharacterRigError.missingAnchor(name) }
            }
            var grid = PixelGrid(width: rig.canvas.width, height: rig.canvas.height)
            for (j, line) in part.rows.enumerated() {
                for (i, c) in line.enumerated() where c != empty {
                    guard palette.contains(c) else {
                        throw CharacterRigError.unknownCode(part: name, code: c)
                    }
                    let x = part.x + i, y = part.y + j
                    guard grid.contains(x, y) else { throw CharacterRigError.partOutOfCanvas(name) }
                    grid[x, y] = c
                }
            }
            grids[name] = grid
        }
        for name in rig.drawOrder where rig.parts[name] == nil {
            throw CharacterRigError.missingPart(name)
        }
        self.rig = rig
        self.colors = colors
        self.grids = grids
        outline = Character(rig.outline)
    }

    /// 定稿正面圖放在畫布上的樣子，用來和 `compose(.rest)` 比對。
    func frontGrid() -> PixelGrid {
        let front = PixelGrid(rows: rig.front.rows, empty: Character(rig.empty))
        var grid = PixelGrid(width: rig.canvas.width, height: rig.canvas.height)
        for y in 0..<front.height {
            for x in 0..<front.width where grid.contains(rig.front.x + x, rig.front.y + y) {
                grid[rig.front.x + x, rig.front.y + y] = front[x, y]
            }
        }
        return grid
    }

    func compose(_ pose: RigPose) -> PixelGrid {
        var out = PixelGrid(width: rig.canvas.width, height: rig.canvas.height)
        let sx = 1 / pose.squash, sy = pose.squash
        let base = pivot("body")
        place("body", on: &out, degrees: 0, pivot: base, scale: (sx, sy))

        // 身體變矮，頭和手跟著往下；身體變寬，手跟著往外
        let drop = Self.roundHalfEven((base.y - rig.rig.neckY) * (1 - sy))
        let armOut = Self.roundHalfEven((pivot("arm").x - base.x) * (sx - 1))
        let arm = abs(pose.armDegrees) > rig.rig.armRaisedAboveDegrees ? "armRaised" : "arm"
        place(arm, on: &out, degrees: pose.armDegrees, pivot: pivot(arm), shift: (armOut, drop))

        let head = pivot("head")
        place("head", on: &out, degrees: pose.headDegrees, pivot: head, shift: (0, drop))

        // 跟著頭的部件：只把錨點轉到新位置，部件本身不轉
        let a = Self.radians(pose.headDegrees)
        for name in rig.drawOrder {
            guard let part = rig.parts[name], part.follows == "head", let anchor = part.anchor else { continue }
            let hx = anchor.x - head.x, hy = anchor.y - head.y
            let shift = (
                Self.roundHalfEven(hx * cos(a) - hy * sin(a) - hx),
                Self.roundHalfEven(hx * sin(a) + hy * cos(a) - hy) + drop
            )
            place(name, on: &out, degrees: 0, pivot: RigPoint(x: 0, y: 0), shift: shift)
        }

        drawOutline(on: &out)
        return out
    }

    // MARK: - 規則

    private func pivot(_ name: String) -> RigPoint {
        rig.parts[name]!.pivot!  // init 已檢查過
    }

    /// 以 pivot 為中心縮放、轉 degrees 度、再平移 shift 格；逐格反查來源像素，蓋到 out 上。
    private func place(
        _ name: String, on out: inout PixelGrid, degrees: Double, pivot: RigPoint,
        shift: (Int, Int) = (0, 0), scale: (Double, Double) = (1, 1)
    ) {
        guard let src = grids[name] else { return }
        let a = Self.radians(degrees)
        let ca = cos(a), sa = sin(a)
        for y in 0..<out.height {
            for x in 0..<out.width {
                let vx = Double(x - shift.0) + 0.5 - pivot.x
                let vy = Double(y - shift.1) + 0.5 - pivot.y
                let ux = (vx * ca + vy * sa) / scale.0 + pivot.x
                let uy = (-vx * sa + vy * ca) / scale.1 + pivot.y
                let ix = Int(ux.rounded(.down)), iy = Int(uy.rounded(.down))
                if src.contains(ix, iy), let c = src[ix, iy] {
                    out[x, y] = c
                }
            }
        }
    }

    /// 透明格只要上下左右有非外框的像素，就描成外框。
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
        for (x, y) in edge {
            out[x, y] = outline
        }
    }

    /// 和 Python 的 `math.radians` 相同的算法：x * (π / 180)。
    static func radians(_ degrees: Double) -> Double {
        degrees * (Double.pi / 180)
    }

    /// 和 Python 3 的 `round()` 相同：.5 取最近的偶數。Swift 的 `rounded()` 預設是遠離 0，結果不同。
    static func roundHalfEven(_ value: Double) -> Int {
        Int(value.rounded(.toNearestOrEven))
    }

    private static func singleCharacters(_ codes: [String]) throws -> [Character] {
        try codes.map { code in
            guard code.count == 1, let c = code.first else { throw CharacterRigError.invalidCode(code) }
            return c
        }
    }
}
