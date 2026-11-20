/// 要畫的東西是哪一個：箱庭的多邊形，或某一隻角色（每隻的造型不同，用身分區分）。
nonisolated enum DrawKey: Hashable, Sendable {
    /// 牆、地板與掛在牆上的東西（多邊形）。
    case background
    /// 地上的第幾件家具（多邊形）。
    case furniture(Int)
    /// 一隻角色。
    case character(CharacterID)
}

/// 繪製清單（ADR 0008）：畫面準備交給 render 的這一格，由遠到近。
///
/// render 只照它下 GPU 指令：不算姿勢、不排序、不讀模擬。座標用畫面上的 pt（左上角為原點），
/// render 再依畫布的實體像素換算。值型別、可以比較：和上一格一樣就不用重畫。
nonisolated struct DrawList: Equatable, Sendable {
    /// 角色的一個部件：照 `transform` 把部件的畫布座標（單位）換到畫面上的 pt。
    struct Part: Equatable, Sendable {
        let name: String
        let transform: Affine2D
    }

    enum Item: Equatable, Sendable {
        /// 箱庭的一組多邊形（背景或某件家具）；頂點在載入時已經送進 GPU，位置是箱庭的單位。
        case polygons(DrawKey)
        /// 一隻角色：用哪個方向的貼圖（翻轉的方向用來源的，矩陣裡已經翻好），部件依畫的先後。
        /// 先畫整隻的外框、再畫顏色，部件重疊處才不會多出內線。
        case character(CharacterID, look: String, parts: [Part])
    }

    /// 畫面大小（pt）。
    let viewportWidth: Double
    let viewportHeight: Double
    /// 畫面左上角對著箱庭的哪一點（單位）與每個單位幾 pt：多邊形的頂點在 GPU 換算。
    let topLeftX: Double
    let topLeftY: Double
    let pointsPerUnit: Double
    let items: [Item]
}
