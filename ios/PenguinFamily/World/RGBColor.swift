/// 不透明的 sRGB 顏色：角色包的顏色層、箱庭的色塊都用它。
nonisolated struct RGBColor: Hashable, Sendable {
    let red: UInt8
    let green: UInt8
    let blue: UInt8

    /// 解析 `#RRGGBB`（大小寫都可以）。
    init?(hex: String) {
        guard hex.count == 7, hex.first == "#", let value = UInt32(hex.dropFirst(), radix: 16) else { return nil }
        red = UInt8((value >> 16) & 0xFF)
        green = UInt8((value >> 8) & 0xFF)
        blue = UInt8(value & 0xFF)
    }
}
