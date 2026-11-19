import Testing
@testable import PenguinFamily

/// 等角箱庭的版面、投影、色塊（多邊形）與前後排序。只測純邏輯，不碰畫面。
struct RoomTests {
    // MARK: - 版面

    @Test func indoorLayoutHasNoProblems() {
        #expect(RoomLayout.indoor.problems().isEmpty)
    }

    @Test func indoorIsTwelveByTwelveWithAllFurniture() {
        let room = RoomLayout.indoor
        #expect(room.widthTiles == 12)
        #expect(room.depthTiles == 12)
        let kinds = Set(room.furniture.map(\.kind)).union(room.wallItems.map(\.kind))
        #expect(kinds == Set(FurnitureKind.allCases))
    }

    @Test func detectsOverlapAndOutOfBounds() {
        let room = RoomLayout(widthTiles: 6, depthTiles: 6, wallHeight: 40, furniture: [
            Furniture(kind: .bed, footprint: TileRect(x: 0, y: 0, width: 3, height: 2), height: 8),
            Furniture(kind: .sofa, footprint: TileRect(x: 2, y: 1, width: 1, height: 3), height: 8),
            Furniture(kind: .storageBox, footprint: TileRect(x: 5, y: 5, width: 2, height: 1), height: 8),
        ], wallItems: [
            WallItem(kind: .window, side: .left, start: 4, length: 3, bottom: 10, top: 30),
        ])
        #expect(room.problems() == ["storageBox 超出地板", "bed 和 sofa 重疊", "window 超出牆面"])
    }

    // MARK: - 投影

    @Test func canvasFitsDiamondFloorAndWalls() {
        let iso = IsoProjection(room: .indoor)
        // 12+12 格，每格半寬 16、半高 8；上面加 64 單位的牆
        #expect(iso.canvasWidth == 384)
        #expect(iso.canvasHeight == 256)
    }

    @Test func cornersLandOnTheDiamond() {
        let iso = IsoProjection(room: .indoor)
        #expect(iso.screen(0, 0) == (x: 192, y: 64))     // 最遠的角，在牆底的正中央
        #expect(iso.screen(12, 0) == (x: 384, y: 160))   // 右角
        #expect(iso.screen(0, 12) == (x: 0, y: 160))     // 左角
        #expect(iso.screen(12, 12) == (x: 192, y: 256))  // 最靠近主人的角
        #expect(iso.screen(0, 0, 64) == (x: 192, y: 0))  // 牆頂
    }

    @Test func gridLinesUseTwoToOneSlope() {
        let iso = IsoProjection(room: .indoor)
        let a = iso.screen(3, 5), b = iso.screen(4, 5)
        #expect(b.x - a.x == 16)
        #expect(b.y - a.y == 8)
    }

    @Test func feetSitAtTheTileCenter() {
        let iso = IsoProjection(room: .indoor)
        #expect(iso.feet(at: TilePosition(i: 0.5, j: 0.5)) == ScenePoint(x: 192, y: 72))
        let between = iso.feet(at: TilePosition(i: 0.6, j: 0.5))                     // 不取整數，走路才平滑
        #expect(abs(between.x - 193.6) < 1e-9 && abs(between.y - 72.8) < 1e-9)
    }

    // MARK: - 色塊（多邊形）

    /// 點在凸多邊形裡面（含邊上）。
    static func inside(_ polygon: ColoredPolygon, _ x: Double, _ y: Double) -> Bool {
        let p = polygon.points
        let signs = p.indices.map { i -> Double in
            let a = p[i], b = p[(i + 1) % p.count]
            return (b.x - a.x) * (y - a.y) - (b.y - a.y) * (x - a.x)
        }
        return signs.allSatisfy { $0 >= -1e-9 } || signs.allSatisfy { $0 <= 1e-9 }
    }

    @Test func furnitureIsABoxWithOutline() {
        let room = RoomLayout.indoor
        let box = Furniture(kind: .storageBox, footprint: TileRect(x: 2, y: 2, width: 1, height: 1), height: 14)
        let polygons = RoomRenderer.furniture(box, in: room)
        let faces = RoomRenderer.Palette.faces(.storageBox)
        #expect(polygons.map(\.color) == [RoomRenderer.Palette.outline, faces.right, faces.left, faces.top])
        // 一格的菱形 32×16，加上 14 單位高：左上角 (176, 82)、右下角 (208, 112)
        let b = RoomRenderer.bounds(Array(polygons.dropFirst()))
        #expect(b.minX == 176 && b.minY == 82 && b.maxX == 208 && b.maxY == 112)
        #expect(Self.inside(polygons[3], 192, 90))     // 頂面中央
        #expect(Self.inside(polygons[2], 184, 104))    // 左前面
        #expect(Self.inside(polygons[1], 200, 104))    // 右前面
        // 外框整圈往外推 0.75 單位
        let outline = RoomRenderer.bounds([polygons[0]])
        #expect(abs(outline.minX - (176 - RoomRenderer.outlineWidth)) < 1e-9)
        #expect(abs(outline.maxX - (208 + RoomRenderer.outlineWidth)) < 1e-9)
        #expect(outline.minY < 82 && outline.maxY > 112)
        for face in polygons.dropFirst() {
            #expect(face.points.allSatisfy { Self.inside(polygons[0], $0.x, $0.y) })
        }
    }

    @Test func backgroundHasWallsFloorAndWindow() {
        let room = RoomLayout.indoor
        let iso = IsoProjection(room: room)
        let polygons = RoomRenderer.background(room)
        #expect(polygons.count == 2 + 2 * room.wallItems.count + room.widthTiles * room.depthTiles)
        #expect(polygons[0].color == RoomRenderer.Palette.leftWall && Self.inside(polygons[0], 100, 70))
        #expect(polygons[1].color == RoomRenderer.Palette.rightWall && Self.inside(polygons[1], 280, 70))
        #expect(!Self.inside(polygons[0], 100, 40))
        // 地板交錯兩種顏色
        let floor = polygons.suffix(room.widthTiles * room.depthTiles)
        #expect(Set(floor.map(\.color)) == [RoomRenderer.Palette.floor, RoomRenderer.Palette.floorAlternate])
        #expect(floor.contains { Self.inside($0, 192, 160) })
        let window = room.wallItems[0]
        let middle = iso.screen(Double(window.start) + Double(window.length) / 2, 0, Double(window.bottom + window.top) / 2)
        let glass = polygons.first { $0.color == RoomRenderer.Palette.glass }
        #expect(glass.map { Self.inside($0, middle.x, middle.y) } == true)
    }

    @Test func everyPolygonIsConvex() {
        let room = RoomLayout.indoor
        let all = RoomRenderer.background(room) + room.furniture.flatMap { RoomRenderer.furniture($0, in: room) }
        for polygon in all {
            #expect(polygon.points.count >= 3)
            #expect(polygon.points.allSatisfy { Self.inside(polygon, $0.x, $0.y) })   // 每個頂點都在其他邊的同一側
            let cx = polygon.points.map(\.x).reduce(0, +) / Double(polygon.points.count)
            let cy = polygon.points.map(\.y).reduce(0, +) / Double(polygon.points.count)
            #expect(Self.inside(polygon, cx, cy))
        }
    }

    @Test func hullAndExpand() {
        let square = [ScenePoint(x: 0, y: 0), ScenePoint(x: 2, y: 0), ScenePoint(x: 2, y: 2), ScenePoint(x: 0, y: 2),
                      ScenePoint(x: 1, y: 1), ScenePoint(x: 1, y: 0)]     // 中間的點、邊上的點都不留
        let hull = RoomRenderer.convexHull(square)
        #expect(Set(hull) == [ScenePoint(x: 0, y: 0), ScenePoint(x: 2, y: 0), ScenePoint(x: 2, y: 2), ScenePoint(x: 0, y: 2)])
        let bigger = RoomRenderer.expanded(hull, by: 1)
        #expect(Set(bigger.map { ScenePoint(x: $0.x.rounded(), y: $0.y.rounded()) })
                == [ScenePoint(x: -1, y: -1), ScenePoint(x: 3, y: -1), ScenePoint(x: 3, y: 3), ScenePoint(x: -1, y: 3)])
    }

    // MARK: - 前後排序

    @Test func furnitureDepthIsItsNearestCorner() {
        let room = RoomLayout.indoor
        let sofa = Furniture(kind: .sofa, footprint: TileRect(x: 7, y: 6, width: 1, height: 3), height: 12)
        // 最近的角是 (8, 9)：64 + (8+9)*8
        #expect(RoomRenderer.depth(of: sofa, in: room) == 200)
    }

    @Test func penguinBehindSofaIsDrawnFirst() {
        let room = RoomLayout.indoor
        let iso = IsoProjection(room: room)
        let sofa = room.furniture.first { $0.kind == .sofa }!
        let behind = Int(iso.feet(at: TilePosition(i: 6.5, j: 5.5)).y)
        let inFront = Int(iso.feet(at: TilePosition(i: 8.5, j: 9.5)).y)
        let depth = RoomRenderer.depth(of: sofa, in: room)
        #expect(RoomRenderer.drawOrder([(id: "sofa", depth: depth), (id: "penguin", depth: behind)]) == ["penguin", "sofa"])
        #expect(RoomRenderer.drawOrder([(id: "sofa", depth: depth), (id: "penguin", depth: inFront)]) == ["sofa", "penguin"])
    }

    @Test func sameDepthKeepsOriginalOrder() {
        let order = RoomRenderer.drawOrder([(id: "a", depth: 10), (id: "b", depth: 10), (id: "c", depth: 5)])
        #expect(order == ["c", "a", "b"])
    }

    // MARK: - 占位剪影

    @Test func placeholderStandsOnItsFeet() throws {
        // 身體的底部貼著腳底那一點（差不到 1 個單位），不會浮在空中或陷進地板
        let front = VectorRig.placeholder.front
        let body = try #require(front.parts["body"]?.silhouette.first?.bounds)
        #expect(front.feet.y >= body.maxY && front.feet.y - body.maxY < 1)
    }
}
