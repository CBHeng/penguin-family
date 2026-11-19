/// 箱庭上的一塊凸多邊形與它的顏色（單位：箱庭的單位）。繪圖層把它切成三角形交給 GPU 畫，任何倍率都清楚（ADR 0007）。
nonisolated struct ColoredPolygon: Equatable, Sendable {
    let points: [ScenePoint]
    let color: RGBColor
}

/// 把等角箱庭畫成多邊形。目前的家具都是色塊占位，美術定案後再換。
///
/// 背景（牆、地板、掛在牆上的東西）是一組；地上的家具各自一組，才能和企鵝依前後排序。
/// 每塊都是凸多邊形，繪圖層用扇形切成三角形。
nonisolated enum RoomRenderer {
    /// 占位色塊的顏色，只在箱庭內使用，和角色包的顏色無關。
    enum Palette {
        static let leftWall = RGBColor(hex: "#E8D9C4")!
        static let rightWall = RGBColor(hex: "#D6C5AC")!
        static let floor = RGBColor(hex: "#CFAE84")!
        static let floorAlternate = RGBColor(hex: "#C7A67C")!   // 交錯的格子
        static let outline = RGBColor(hex: "#6B5844")!          // 家具外框
        static let glass = RGBColor(hex: "#BFE3F2")!            // 窗戶玻璃（白天）
        static let windowFrame = RGBColor(hex: "#8A6E52")!

        /// 家具的頂面、左前面、右前面。
        static func faces(_ kind: FurnitureKind) -> (top: RGBColor, left: RGBColor, right: RGBColor) {
            switch kind {
            case .bed: (RGBColor(hex: "#F2E6D8")!, RGBColor(hex: "#A07C60")!, RGBColor(hex: "#7A5C44")!)
            case .sofa: (RGBColor(hex: "#D98C7A")!, RGBColor(hex: "#C47A68")!, RGBColor(hex: "#AA6858")!)
            case .storageBox, .window: (RGBColor(hex: "#C9A26B")!, RGBColor(hex: "#B48E5A")!, RGBColor(hex: "#9E7A4B")!)
            }
        }
    }

    /// 家具外框露在外面的寬度（單位），和角色的外框一樣粗（遊戲設計：外框粗細一致）。
    static let outlineWidth = 0.75

    /// 牆、地板與掛在牆上的東西，由後往前。
    static func background(_ room: RoomLayout) -> [ColoredPolygon] {
        let iso = IsoProjection(room: room)
        let w = Double(room.widthTiles), d = Double(room.depthTiles), h = Double(room.wallHeight)
        var polygons = [
            polygon([iso.screen(0, 0, h), iso.screen(0, d, h), iso.screen(0, d), iso.screen(0, 0)], Palette.leftWall),
            polygon([iso.screen(0, 0, h), iso.screen(w, 0, h), iso.screen(w, 0), iso.screen(0, 0)], Palette.rightWall),
        ]
        for item in room.wallItems { polygons += window(item, iso: iso) }
        for i in 0..<room.widthTiles {
            for j in 0..<room.depthTiles {
                let (a, b) = (Double(i), Double(j))
                polygons.append(polygon([iso.screen(a, b), iso.screen(a + 1, b), iso.screen(a + 1, b + 1), iso.screen(a, b + 1)],
                                        (i + j) % 2 == 0 ? Palette.floor : Palette.floorAlternate))
            }
        }
        return polygons
    }

    /// 地上一件家具：立體的盒子（頂面、左前面、右前面），外面一圈外框。由後往前。
    static func furniture(_ item: Furniture, in room: RoomLayout) -> [ColoredPolygon] {
        let iso = IsoProjection(room: room)
        let r = item.footprint
        let (i0, j0, i1, j1) = (Double(r.x), Double(r.y), Double(r.maxX), Double(r.maxY))
        let z = Double(item.height)
        let top = [iso.screen(i0, j0, z), iso.screen(i1, j0, z), iso.screen(i1, j1, z), iso.screen(i0, j1, z)]
        let rightFront = [iso.screen(i1, j0, z), iso.screen(i1, j1, z), iso.screen(i1, j1), iso.screen(i1, j0)]
        let leftFront = [iso.screen(i0, j1, z), iso.screen(i1, j1, z), iso.screen(i1, j1), iso.screen(i0, j1)]
        let faces = Palette.faces(item.kind)
        let silhouette = convexHull((top + rightFront + leftFront).map { ScenePoint(x: $0.x, y: $0.y) })
        return [
            ColoredPolygon(points: expanded(silhouette, by: outlineWidth), color: Palette.outline),
            polygon(rightFront, faces.right),
            polygon(leftFront, faces.left),
            polygon(top, faces.top),
        ]
    }

    /// 排前後用的深度：家具最靠近主人的那個角在畫面上的高度（單位）。越大越前面。
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

    /// 一組多邊形的外接矩形。
    static func bounds(_ polygons: [ColoredPolygon]) -> (minX: Double, minY: Double, maxX: Double, maxY: Double) {
        let points = polygons.flatMap(\.points)
        return (points.map(\.x).min() ?? 0, points.map(\.y).min() ?? 0, points.map(\.x).max() ?? 0, points.map(\.y).max() ?? 0)
    }

    // MARK: - 幾何小工具

    /// 凸包（Andrew 單調鏈）。共線的點不留。
    static func convexHull(_ points: [ScenePoint]) -> [ScenePoint] {
        let sorted = Array(Set(points)).sorted { ($0.x, $0.y) < ($1.x, $1.y) }
        guard sorted.count > 2 else { return sorted }
        func cross(_ o: ScenePoint, _ a: ScenePoint, _ b: ScenePoint) -> Double {
            (a.x - o.x) * (b.y - o.y) - (a.y - o.y) * (b.x - o.x)
        }
        var lower: [ScenePoint] = [], upper: [ScenePoint] = []
        for p in sorted {
            while lower.count >= 2, cross(lower[lower.count - 2], lower[lower.count - 1], p) <= 0 { lower.removeLast() }
            lower.append(p)
        }
        for p in sorted.reversed() {
            while upper.count >= 2, cross(upper[upper.count - 2], upper[upper.count - 1], p) <= 0 { upper.removeLast() }
            upper.append(p)
        }
        return Array(lower.dropLast() + upper.dropLast())
    }

    /// 凸多邊形每條邊往外推 `width`，轉角用斜接（等角盒子的角度都不尖，不會突出太多）。
    static func expanded(_ polygon: [ScenePoint], by width: Double) -> [ScenePoint] {
        let n = polygon.count
        guard n >= 3 else { return polygon }
        let cx = polygon.map(\.x).reduce(0, +) / Double(n), cy = polygon.map(\.y).reduce(0, +) / Double(n)
        /// 邊 a→b 朝外的單位法向量。
        func normal(_ a: ScenePoint, _ b: ScenePoint) -> (x: Double, y: Double) {
            let dx = b.x - a.x, dy = b.y - a.y, length = (dx * dx + dy * dy).squareRoot()
            var nx = dy / length, ny = -dx / length
            let mx = (a.x + b.x) / 2 - cx, my = (a.y + b.y) / 2 - cy
            if nx * mx + ny * my < 0 { nx = -nx; ny = -ny }
            return (nx, ny)
        }
        return polygon.indices.map { i in
            let prev = polygon[(i + n - 1) % n], here = polygon[i], next = polygon[(i + 1) % n]
            let n1 = normal(prev, here), n2 = normal(here, next)
            let scale = width / (1 + n1.x * n2.x + n1.y * n2.y)
            return ScenePoint(x: here.x + (n1.x + n2.x) * scale, y: here.y + (n1.y + n2.y) * scale)
        }
    }

    private static func polygon(_ points: [(x: Double, y: Double)], _ color: RGBColor) -> ColoredPolygon {
        ColoredPolygon(points: points.map { ScenePoint(x: $0.x, y: $0.y) }, color: color)
    }

    private static func window(_ item: WallItem, iso: IsoProjection) -> [ColoredPolygon] {
        let s = Double(item.start), e = Double(item.start + item.length)
        let b = Double(item.bottom), t = Double(item.top)
        let at: (Double, Double) -> (x: Double, y: Double) = { along, z in
            item.side == .right ? iso.screen(along, 0, z) : iso.screen(0, along, z)
        }
        return [
            polygon([at(s, t), at(e, t), at(e, b), at(s, b)], Palette.windowFrame),
            polygon([at(s + 0.15, t - 3), at(e - 0.15, t - 3), at(e - 0.15, b + 3), at(s + 0.15, b + 3)], Palette.glass),
        ]
    }
}
