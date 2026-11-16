import Testing
@testable import PenguinFamily

/// 等角箱庭的版面、投影、色塊與前後排序。只測純邏輯，不碰畫面。
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
        // 12+12 格，每格半寬 16、半高 8；上面加 64 像素的牆
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
        #expect(iso.feet(at: TilePosition(i: 0.5, j: 0.5)) == PixelPoint(x: 192, y: 72))
    }

    // MARK: - 色塊

    @Test func furnitureSpriteIsABoxWithOutline() {
        let room = RoomLayout.indoor
        let box = Furniture(kind: .storageBox, footprint: TileRect(x: 2, y: 2, width: 1, height: 1), height: 14)
        let (grid, origin) = RoomRenderer.sprite(for: box, in: room)
        // 一格的菱形 32×16，加上 14 像素高
        #expect(grid.width == 32)
        #expect(grid.height == 30)
        #expect(origin == PixelPoint(x: 176, y: 82))
        #expect(grid[16, 8] == "X")   // 頂面中央
        #expect(grid[8, 22] == "x")   // 左前面
        #expect(grid[24, 22] == "y")  // 右前面
        #expect(grid[0, 15] == "O")   // 左邊緣是外框
        #expect(grid[0, 0] == nil)    // 菱形外面是透明的
    }

    @Test func backgroundHasWallsFloorAndWindow() {
        let room = RoomLayout.indoor
        let iso = IsoProjection(room: room)
        let grid = RoomRenderer.background(room)
        #expect(grid.width == iso.canvasWidth)
        // 牆跟著菱形往外下斜：x=100 的左牆在 y 約 46～110，x=280 的右牆在 y 約 44～108
        #expect(grid[100, 70] == "L")
        #expect(grid[280, 70] == "R")
        #expect(grid[100, 40] == nil)
        #expect([Character("F"), "f"].contains(grid[192, 160]))
        #expect(grid[0, 0] == nil)  // 左上角在牆外，透明
        let window = room.wallItems[0]
        let middle = iso.screen(Double(window.start) + Double(window.length) / 2, 0, Double(window.bottom + window.top) / 2)
        #expect(grid[Int(middle.x), Int(middle.y)] == "G")
    }

    @Test func everyCodeHasAColor() {
        let room = RoomLayout.indoor
        var codes = Set<Character>()
        let grids = [RoomRenderer.background(room)] + room.furniture.map { RoomRenderer.sprite(for: $0, in: room).grid }
        for grid in grids {
            for y in 0..<grid.height {
                for x in 0..<grid.width {
                    if let code = grid[x, y] { codes.insert(code) }
                }
            }
        }
        #expect(codes.isSubset(of: Set(RoomRenderer.colors.keys)))
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
        let behind = iso.feet(at: TilePosition(i: 6.5, j: 5.5)).y
        let inFront = iso.feet(at: TilePosition(i: 8.5, j: 9.5)).y
        let depth = RoomRenderer.depth(of: sofa, in: room)
        #expect(RoomRenderer.drawOrder([(id: "sofa", depth: depth), (id: "penguin", depth: behind)]) == ["penguin", "sofa"])
        #expect(RoomRenderer.drawOrder([(id: "sofa", depth: depth), (id: "penguin", depth: inFront)]) == ["sofa", "penguin"])
    }

    @Test func sameDepthKeepsOriginalOrder() {
        let order = RoomRenderer.drawOrder([(id: "a", depth: 10), (id: "b", depth: 10), (id: "c", depth: 5)])
        #expect(order == ["c", "a", "b"])
    }

    // MARK: - 占位剪影

    @Test func placeholderStandsOnItsAnchor() {
        let grid = PlaceholderSilhouette.grid
        let anchor = PlaceholderSilhouette.anchor
        // 腳底那一列有像素，下面沒有
        #expect((0..<grid.width).contains { grid[$0, anchor.y] != nil })
        #expect(anchor.y + 1 == grid.height || (0..<grid.width).allSatisfy { grid[$0, anchor.y + 1] == nil })
    }
}
