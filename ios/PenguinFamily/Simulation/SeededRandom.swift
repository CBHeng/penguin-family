/// 固定種子的亂數（SplitMix64）：模擬用它挑閒晃的下一步，同樣的種子每次得到同樣的數列（ADR 0008 的「結果固定」）。
///
/// 種子由外面給：App 啟動時隨機取一個，測試用固定的數字。
nonisolated struct SeededRandom: RandomNumberGenerator, Sendable {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}
