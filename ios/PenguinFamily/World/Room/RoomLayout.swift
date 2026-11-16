/// 地板格子上的矩形（單位：格）。`x` 沿 i 軸（往右下），`y` 沿 j 軸（往左下）。
nonisolated struct TileRect: Equatable, Sendable {
    var x: Int
    var y: Int
    var width: Int
    var height: Int

    var maxX: Int { x + width }
    var maxY: Int { y + height }

    func contains(_ other: TileRect) -> Bool {
        other.x >= x && other.y >= y && other.maxX <= maxX && other.maxY <= maxY
    }

    func intersects(_ other: TileRect) -> Bool {
        x < other.maxX && other.x < maxX && y < other.maxY && other.y < maxY
    }
}

/// 地板上的一點（單位：格，可以有小數）。格子 (i, j) 的中心是 (i + 0.5, j + 0.5)。
nonisolated struct TilePosition: Equatable, Hashable, Sendable {
    var i: Double
    var j: Double
}

/// 畫面上的一點（單位：像素，箱庭圖的左上角是原點）。
nonisolated struct PixelPoint: Equatable, Hashable, Sendable {
    var x: Int
    var y: Int
}

nonisolated enum FurnitureKind: String, Sendable, CaseIterable {
    case bed
    case sofa
    case window
    case storageBox
}

/// 地上的一件家具。A1 是固定擺好的，之後的家具系統才會移動（見遊戲設計的家具分階段）。
nonisolated struct Furniture: Equatable, Sendable {
    let kind: FurnitureKind
    /// 佔用的地板格子。
    let footprint: TileRect
    /// 高度（像素）。
    let height: Int
}

/// 兩面後牆：左牆沿著 j 軸（i = 0），右牆沿著 i 軸（j = 0）。
nonisolated enum WallSide: Sendable {
    case left
    case right
}

/// 掛在牆上的東西，例如窗戶。
nonisolated struct WallItem: Equatable, Sendable {
    let kind: FurnitureKind
    let side: WallSide
    /// 沿著牆從第幾格開始、佔幾格。
    let start: Int
    let length: Int
    /// 離地多高到多高（像素）。
    let bottom: Int
    let top: Int
}

/// 一個區域的箱庭（等角）：菱形的地板格子加兩面後牆。
nonisolated struct RoomLayout: Equatable, Sendable {
    /// i 軸、j 軸各幾格。
    let widthTiles: Int
    let depthTiles: Int
    /// 後牆高度（像素）。
    let wallHeight: Int
    let furniture: [Furniture]
    let wallItems: [WallItem]

    var floor: TileRect { TileRect(x: 0, y: 0, width: widthTiles, height: depthTiles) }

    /// A1 的屋內：12×12 格（作者 2026-11-16 決定），四件固定家具。位置與大小是占位，美術定案時再調。
    static let indoor = RoomLayout(
        widthTiles: 12,
        depthTiles: 12,
        wallHeight: 64,
        furniture: [
            Furniture(kind: .bed, footprint: TileRect(x: 0, y: 1, width: 3, height: 2), height: 10),
            Furniture(kind: .sofa, footprint: TileRect(x: 7, y: 6, width: 1, height: 3), height: 12),
            Furniture(kind: .storageBox, footprint: TileRect(x: 0, y: 10, width: 1, height: 1), height: 14),
        ],
        wallItems: [
            WallItem(kind: .window, side: .right, start: 6, length: 3, bottom: 18, top: 52),
        ])

    /// 擺放規則有問題的地方；沒有問題時是空的。
    func problems() -> [String] {
        var found: [String] = []
        for item in furniture where !floor.contains(item.footprint) {
            found.append("\(item.kind.rawValue) 超出地板")
        }
        for (i, a) in furniture.enumerated() {
            for b in furniture[(i + 1)...] where a.footprint.intersects(b.footprint) {
                found.append("\(a.kind.rawValue) 和 \(b.kind.rawValue) 重疊")
            }
        }
        for item in wallItems {
            let wallLength = item.side == .left ? depthTiles : widthTiles
            if item.start < 0 || item.start + item.length > wallLength || item.bottom < 0 || item.top > wallHeight
                || item.bottom >= item.top {
                found.append("\(item.kind.rawValue) 超出牆面")
            }
        }
        return found
    }
}

/// 等角投影：地板格子 (i, j) 與高度 z 換算成畫面像素。每格 32×16 像素，像素線條是 2:1 的斜率。
nonisolated struct IsoProjection: Sendable {
    static let tileWidth = 32
    static let tileHeight = 16

    let room: RoomLayout

    /// 整個箱庭圖的大小（像素）：菱形地板加上方的牆。
    var canvasWidth: Int { (room.widthTiles + room.depthTiles) * Self.tileWidth / 2 }
    var canvasHeight: Int { (room.widthTiles + room.depthTiles) * Self.tileHeight / 2 + room.wallHeight }

    /// 格子 (i, j) 在高度 z 的位置。地板最上面的角（i = j = 0）在牆頂正下方。
    func screen(_ i: Double, _ j: Double, _ z: Double = 0) -> (x: Double, y: Double) {
        let x = Double(room.depthTiles * Self.tileWidth / 2) + (i - j) * Double(Self.tileWidth / 2)
        let y = Double(room.wallHeight) + (i + j) * Double(Self.tileHeight / 2) - z
        return (x, y)
    }

    /// 站在地板某一點時，腳底在畫面上的像素。
    func feet(at position: TilePosition) -> PixelPoint {
        let p = screen(position.i, position.j)
        return PixelPoint(x: Int(p.x.rounded(.down)), y: Int(p.y.rounded(.down)))
    }
}
