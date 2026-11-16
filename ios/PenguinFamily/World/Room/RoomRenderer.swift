/// 把等角箱庭畫成像素圖。目前的家具都是色塊占位，美術定案後換成像素圖。
///
/// 背景（牆、地板、掛在牆上的東西）畫成一張；地上的家具各自一張，才能和企鵝依前後排序。
nonisolated enum RoomRenderer {
    /// 占位色塊用的顏色。代碼只在箱庭內使用，和角色包的調色盤無關。
    static let colors: [Character: PixelColor] = [
        "L": PixelColor(hex: "#E8D9C4")!,  // 左牆
        "R": PixelColor(hex: "#D6C5AC")!,  // 右牆
        "F": PixelColor(hex: "#CFAE84")!,  // 地板
        "f": PixelColor(hex: "#C7A67C")!,  // 地板（交錯的格子）
        "O": PixelColor(hex: "#6B5844")!,  // 家具外框
        "G": PixelColor(hex: "#BFE3F2")!,  // 窗戶玻璃（白天）
        "K": PixelColor(hex: "#8A6E52")!,  // 窗框
        "B": PixelColor(hex: "#F2E6D8")!, "b": PixelColor(hex: "#A07C60")!, "c": PixelColor(hex: "#7A5C44")!,  // 床：頂、左前、右前
        "S": PixelColor(hex: "#D98C7A")!, "s": PixelColor(hex: "#C47A68")!, "t": PixelColor(hex: "#AA6858")!,  // 沙發
        "X": PixelColor(hex: "#C9A26B")!, "x": PixelColor(hex: "#B48E5A")!, "y": PixelColor(hex: "#9E7A4B")!,  // 箱子
    ]

    /// 牆、地板與掛在牆上的東西。
    static func background(_ room: RoomLayout) -> PixelGrid {
        let iso = IsoProjection(room: room)
        var grid = PixelGrid(width: iso.canvasWidth, height: iso.canvasHeight)
        let w = Double(room.widthTiles), d = Double(room.depthTiles), h = Double(room.wallHeight)
        fill(&grid, [iso.screen(0, 0, h), iso.screen(0, d, h), iso.screen(0, d), iso.screen(0, 0)], "L")
        fill(&grid, [iso.screen(0, 0, h), iso.screen(w, 0, h), iso.screen(w, 0), iso.screen(0, 0)], "R")
        for item in room.wallItems {
            drawWindow(item, iso: iso, on: &grid)
        }
        for i in 0..<room.widthTiles {
            for j in 0..<room.depthTiles {
                let (a, b) = (Double(i), Double(j))
                fill(&grid, [iso.screen(a, b), iso.screen(a + 1, b), iso.screen(a + 1, b + 1), iso.screen(a, b + 1)],
                     (i + j) % 2 == 0 ? "F" : "f")
            }
        }
        return grid
    }

    /// 地上家具的圖，以及它的左上角在箱庭圖上的位置。畫成立體的盒子：頂面、左前面、右前面，邊緣描外框。
    static func sprite(for item: Furniture, in room: RoomLayout) -> (grid: PixelGrid, origin: PixelPoint) {
        let iso = IsoProjection(room: room)
        let r = item.footprint
        let (i0, j0, i1, j1) = (Double(r.x), Double(r.y), Double(r.maxX), Double(r.maxY))
        let z = Double(item.height)
        let top = [iso.screen(i0, j0, z), iso.screen(i1, j0, z), iso.screen(i1, j1, z), iso.screen(i0, j1, z)]
        let rightFront = [iso.screen(i1, j0, z), iso.screen(i1, j1, z), iso.screen(i1, j1), iso.screen(i1, j0)]
        let leftFront = [iso.screen(i0, j1, z), iso.screen(i1, j1, z), iso.screen(i1, j1), iso.screen(i0, j1)]
        let all = top + rightFront + leftFront
        let minX = Int(all.map(\.x).min()!.rounded(.down)), maxX = Int(all.map(\.x).max()!.rounded(.up))
        let minY = Int(all.map(\.y).min()!.rounded(.down)), maxY = Int(all.map(\.y).max()!.rounded(.up))
        var grid = PixelGrid(width: maxX - minX, height: maxY - minY)
        let shift = { (points: [(x: Double, y: Double)]) in points.map { (x: $0.x - Double(minX), y: $0.y - Double(minY)) } }
        let (topCode, leftCode, rightCode) = faceCodes(item.kind)
        fill(&grid, shift(rightFront), rightCode)
        fill(&grid, shift(leftFront), leftCode)
        fill(&grid, shift(top), topCode)
        outline(&grid)
        return (grid, PixelPoint(x: minX, y: minY))
    }

    /// 排前後用的深度：家具最靠近主人的那個角在畫面上的高度（像素）。越大越前面。
    static func depth(of item: Furniture, in room: RoomLayout) -> Int {
        let p = IsoProjection(room: room).screen(Double(item.footprint.maxX), Double(item.footprint.maxY))
        return Int(p.y.rounded(.down))
    }

    /// 依深度由遠到近排序；深度相同時維持原本順序。
    static func drawOrder<ID>(_ items: [(id: ID, depth: Int)]) -> [ID] {
        items.enumerated()
            .sorted { ($0.element.depth, $0.offset) < ($1.element.depth, $1.offset) }
            .map(\.element.id)
    }

    // MARK: - 畫圖的小工具

    /// 填滿多邊形：像素中心落在多邊形內就填（凸多邊形與凹多邊形都適用）。
    static func fill(_ grid: inout PixelGrid, _ points: [(x: Double, y: Double)], _ code: Character) {
        guard let minY = points.map(\.y).min(), let maxY = points.map(\.y).max(),
              let minX = points.map(\.x).min(), let maxX = points.map(\.x).max() else { return }
        let ys = max(0, Int(minY.rounded(.down)))...min(grid.height - 1, Int(maxY.rounded(.up)))
        let xs = max(0, Int(minX.rounded(.down)))...min(grid.width - 1, Int(maxX.rounded(.up)))
        guard !ys.isEmpty, !xs.isEmpty else { return }
        for y in ys {
            for x in xs where contains(points, Double(x) + 0.5, Double(y) + 0.5) {
                grid[x, y] = code
            }
        }
    }

    private static func contains(_ points: [(x: Double, y: Double)], _ px: Double, _ py: Double) -> Bool {
        var inside = false
        for k in points.indices {
            let a = points[k], b = points[(k + 1) % points.count]
            if (a.y > py) != (b.y > py) && px < (b.x - a.x) * (py - a.y) / (b.y - a.y) + a.x {
                inside.toggle()
            }
        }
        return inside
    }

    /// 有像素、而且上下左右碰到透明或邊界的格子，改成外框色。
    private static func outline(_ grid: inout PixelGrid) {
        var edge: [(Int, Int)] = []
        for y in 0..<grid.height {
            for x in 0..<grid.width where grid[x, y] != nil {
                let near = [(x + 1, y), (x - 1, y), (x, y + 1), (x, y - 1)]
                if near.contains(where: { !grid.contains($0.0, $0.1) || grid[$0.0, $0.1] == nil }) {
                    edge.append((x, y))
                }
            }
        }
        for (x, y) in edge { grid[x, y] = "O" }
    }

    private static func faceCodes(_ kind: FurnitureKind) -> (top: Character, left: Character, right: Character) {
        switch kind {
        case .bed: ("B", "b", "c")
        case .sofa: ("S", "s", "t")
        case .storageBox, .window: ("X", "x", "y")
        }
    }

    private static func drawWindow(_ item: WallItem, iso: IsoProjection, on grid: inout PixelGrid) {
        let s = Double(item.start), e = Double(item.start + item.length)
        let b = Double(item.bottom), t = Double(item.top)
        let at: (Double, Double) -> (x: Double, y: Double) = { along, z in
            item.side == .right ? iso.screen(along, 0, z) : iso.screen(0, along, z)
        }
        fill(&grid, [at(s, t), at(e, t), at(e, b), at(s, b)], "K")
        fill(&grid, [at(s + 0.15, t - 3), at(e - 0.15, t - 3), at(e - 0.15, b + 3), at(s + 0.15, b + 3)], "G")
    }
}
