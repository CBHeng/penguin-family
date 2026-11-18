import Testing
@testable import PenguinFamily

/// 找路：哪些格子站得上去、沿格線走、繞過家具、最短而且轉彎最少。只測純邏輯。
struct RoomPathTests {
    static let room = RoomLayout.indoor

    /// 每一步都只沿格線走一格，而且都站得上去。
    static func isValid(_ path: RoomPath, in room: RoomLayout = room) -> Bool {
        path.tiles.allSatisfy(room.isWalkable)
            && zip(path.tiles, path.tiles.dropFirst()).allSatisfy { Step(from: $0, to: $1) != nil }
    }

    // MARK: - 格子

    @Test func furnitureAndOutsideAreNotWalkable() {
        #expect(Self.room.isWalkable(Tile(i: 4, j: 4)))
        #expect(!Self.room.isWalkable(Tile(i: 7, j: 7)))     // 沙發：i = 7、j = 6～8
        #expect(!Self.room.isWalkable(Tile(i: 1, j: 2)))     // 床：i = 0～2、j = 1～2
        #expect(!Self.room.isWalkable(Tile(i: 0, j: 10)))    // 倉庫箱子
        #expect(!Self.room.isWalkable(Tile(i: -1, j: 4)) && !Self.room.isWalkable(Tile(i: 4, j: 12)))
        #expect(Self.room.isWalkable(Tile(i: 11, j: 11)) && Self.room.isWalkable(Tile(i: 0, j: 0)))
    }

    @Test func tileOfAPositionAndItsCenter() {
        #expect(Tile(containing: TilePosition(i: 4.5, j: 4.5)) == Tile(i: 4, j: 4))
        #expect(Tile(containing: TilePosition(i: 5.99, j: 3.0)) == Tile(i: 5, j: 3))
        #expect(Tile(i: 4, j: 4).center == TilePosition(i: 4.5, j: 4.5))
    }

    @Test func stepsMatchTheFourObliqueImages() {
        // 畫面上 i 軸往右下、j 軸往左下（見 IsoProjection）
        #expect(Step.iForward.facing == .frontRight && Step.jForward.facing == .frontLeft)
        #expect(Step.iBackward.facing == .backLeft && Step.jBackward.facing == .backRight)
        let iso = IsoProjection(room: Self.room)
        let a = iso.screen(4.5, 4.5), right = iso.screen(5.5, 4.5), left = iso.screen(4.5, 5.5)
        #expect(right.x > a.x && right.y > a.y)               // i 往前：右下
        #expect(left.x < a.x && left.y > a.y)                 // j 往前：左下
        #expect(Step(from: Tile(i: 4, j: 4), to: Tile(i: 4, j: 3)) == .jBackward)
        #expect(Step(from: Tile(i: 4, j: 4), to: Tile(i: 5, j: 5)) == nil)   // 不沿格線
    }

    // MARK: - 找路

    @Test func straightLine() throws {
        let path = try #require(RoomPath.find(in: Self.room, from: Tile(i: 4, j: 4), to: Tile(i: 9, j: 4)))
        #expect(path.steps == 5 && path.turns == 0)
        #expect(path.legs == [RoomPath.Leg(step: .iForward, tiles: (5...9).map { Tile(i: $0, j: 4) })])
    }

    @Test func diagonalGoalTurnsOnlyOnce() throws {
        let path = try #require(RoomPath.find(in: Self.room, from: Tile(i: 4, j: 4), to: Tile(i: 6, j: 1)))
        #expect(path.steps == 5)                              // 最短：2 + 3
        #expect(path.turns == 1)                              // 一樣短的路裡，轉彎最少
        #expect(Self.isValid(path))
    }

    @Test func goesAroundTheSofa() throws {
        // 沙發擋在 i = 7、j = 6～8：從沙發一側走到另一側要繞過去
        let path = try #require(RoomPath.find(in: Self.room, from: Tile(i: 6, j: 7), to: Tile(i: 8, j: 7)))
        #expect(Self.isValid(path))
        #expect(path.steps == 6 && path.turns == 2)           // 往上或往下繞兩格，是最短的
        #expect(path.start == Tile(i: 6, j: 7) && path.goal == Tile(i: 8, j: 7))
    }

    @Test func samePathEveryTime() throws {
        let a = RoomPath.find(in: Self.room, from: Tile(i: 6, j: 7), to: Tile(i: 8, j: 7))
        let b = RoomPath.find(in: Self.room, from: Tile(i: 6, j: 7), to: Tile(i: 8, j: 7))
        #expect(a == b)
    }

    @Test func startEqualsGoal() throws {
        let path = try #require(RoomPath.find(in: Self.room, from: Tile(i: 4, j: 4), to: Tile(i: 4, j: 4)))
        #expect(path.tiles == [Tile(i: 4, j: 4)] && path.legs.isEmpty && path.turns == 0)
    }

    @Test func noPathToFurnitureOrOutside() {
        #expect(RoomPath.find(in: Self.room, from: Tile(i: 4, j: 4), to: Tile(i: 7, j: 7)) == nil)
        #expect(RoomPath.find(in: Self.room, from: Tile(i: 4, j: 4), to: Tile(i: 12, j: 4)) == nil)
        #expect(RoomPath.find(in: Self.room, from: Tile(i: 7, j: 7), to: Tile(i: 4, j: 4)) == nil)
    }

    @Test func noPathWhenWalledOff() {
        // 4×4 的房間，一排家具把右下角那一格隔開
        let room = RoomLayout(widthTiles: 4, depthTiles: 4, wallHeight: 40, furniture: [
            Furniture(kind: .bed, footprint: TileRect(x: 0, y: 2, width: 4, height: 1), height: 8),
        ], wallItems: [])
        #expect(RoomPath.find(in: room, from: Tile(i: 0, j: 0), to: Tile(i: 3, j: 3)) == nil)
        #expect(RoomPath.find(in: room, from: Tile(i: 0, j: 3), to: Tile(i: 3, j: 3))?.steps == 3)
    }

    @Test func everyFloorTileCanReachEveryOther() {
        // 屋內的家具擺法不能把任何一塊地板圍起來
        let tiles = (0..<Self.room.widthTiles).flatMap { i in (0..<Self.room.depthTiles).map { Tile(i: i, j: $0) } }
            .filter(Self.room.isWalkable)
        let from = Tile(i: 4, j: 4)
        for tile in tiles {
            let path = RoomPath.find(in: Self.room, from: from, to: tile)
            #expect(path.map { Self.isValid($0) } == true, "到不了 \(tile)")
        }
    }
}
