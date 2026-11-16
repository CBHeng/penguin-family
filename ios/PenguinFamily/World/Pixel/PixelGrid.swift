/// 一張原始尺寸的像素圖，每格存調色盤代碼；`nil` 表示透明。
nonisolated struct PixelGrid: Equatable, Sendable {
    let width: Int
    let height: Int
    private var cells: [Character?]

    init(width: Int, height: Int) {
        self.width = width
        self.height = height
        cells = Array(repeating: nil, count: width * height)
    }

    /// 由每列字串建立，`empty` 字元表示透明。
    init(rows: [String], empty: Character) {
        let chars = rows.map(Array.init)
        self.init(width: chars.first?.count ?? 0, height: chars.count)
        for (y, line) in chars.enumerated() {
            for (x, c) in line.enumerated() where c != empty {
                self[x, y] = c
            }
        }
    }

    func contains(_ x: Int, _ y: Int) -> Bool {
        x >= 0 && x < width && y >= 0 && y < height
    }

    subscript(x: Int, y: Int) -> Character? {
        get { cells[y * width + x] }
        set { cells[y * width + x] = newValue }
    }

    /// 轉回每列字串，`empty` 字元表示透明。
    func rows(empty: Character) -> [String] {
        (0..<height).map { y in
            String((0..<width).map { x in self[x, y] ?? empty })
        }
    }
}
