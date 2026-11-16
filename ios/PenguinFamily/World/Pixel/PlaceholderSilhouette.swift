/// 沒有角色包（例如公開 repo 乾淨 clone）或第二隻的美術還沒好時的占位：不像任何玩偶的灰色剪影。
nonisolated enum PlaceholderSilhouette {
    static let colors: [Character: PixelColor] = [
        "G": PixelColor(hex: "#A3A3A3")!,
        "O": PixelColor(hex: "#5E5E5E")!,
    ]

    /// 腳底在圖上的位置。
    static let anchor = PixelPoint(x: 15, y: 35)

    static let grid: PixelGrid = {
        var grid = PixelGrid(width: 31, height: 36)
        func inside(_ x: Int, _ y: Int, cx: Double, cy: Double, rx: Double, ry: Double) -> Bool {
            let dx = (Double(x) + 0.5 - cx) / rx, dy = (Double(y) + 0.5 - cy) / ry
            return dx * dx + dy * dy <= 1
        }
        for y in 0..<grid.height {
            for x in 0..<grid.width
            where inside(x, y, cx: 15.5, cy: 10, rx: 8, ry: 8) || inside(x, y, cx: 15.5, cy: 24, rx: 12, ry: 10.5) {
                grid[x, y] = "G"
            }
        }
        var edge: [(Int, Int)] = []
        for y in 0..<grid.height {
            for x in 0..<grid.width where grid[x, y] == nil {
                let near = [(x + 1, y), (x - 1, y), (x, y + 1), (x, y - 1)]
                if near.contains(where: { grid.contains($0.0, $0.1) && grid[$0.0, $0.1] == "G" }) {
                    edge.append((x, y))
                }
            }
        }
        for (x, y) in edge { grid[x, y] = "O" }
        return grid
    }()

    static let bitmap = PixelBitmap(grid, colors: colors)
}
