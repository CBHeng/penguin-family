import Foundation
import Testing
@testable import PenguinFamily

/// 向量貼圖的記憶體預算（作者 2026-11-18 決定加這個測試）：拿真實角色包，算一家在螢幕 3 倍的手機上，
/// 部件貼圖（含 mipmap）共佔多少，超過 50MB 就失敗。
///
/// 50MB 是「用記憶體換時間」要先和作者討論的門檻（`docs/architecture.md` 的技術取捨）。
/// 動作不佔貼圖（只是數字）；會讓這個數字變大的是多一隻角色、多一個畫好的方向、多一種形狀（例如表情），
/// 或貼圖準備得更細。失敗時不要直接調高預算，先和作者討論怎麼省（見架構的記憶體表）。
///
/// 角色包由私有素材 repo 匯出，不進 git；乾淨 clone 下來沒有角色包，這個測試會跳過。
/// 訊息只用第幾隻，不寫角色 id（角色名稱只能出現在私有 repo）。
struct VectorMemoryBudgetTests {
    /// 「用記憶體換時間」的門檻（位元組）。
    static let budget = 50 * 1024 * 1024
    /// 用最細的螢幕算：iPhone 17 等機型 1pt 是 3 個實體像素。
    static let displayScale = 3.0

    /// 一家會用到的角色包：和 `CharacterPackLibrary.loadFamily` 一樣，依名稱取前面幾隻。
    static let family = Array(VectorPackParityTests.allPacks.prefix(CharacterPackLibrary.familySize))

    @Test(.enabled(if: !family.isEmpty, "沒有向量角色包（乾淨 clone），跳過"))
    func familyFitsTheBudgetOnTheSharpestScreen() throws {
        let pixelsPerUnit = SpriteRenderer.vectorPixelsPerUnit(displayScale: Self.displayScale)
        var total = 0
        var each: [String] = []
        for (i, pack) in Self.family.enumerated() {
            let rig = try VectorRig.decode(Data(contentsOf: pack.appending(path: "vector.json")))
            let bytes = VectorRasterizer.textureBytes(rig, pixelsPerUnit: pixelsPerUnit)
            total += bytes
            each.append("第 \(i + 1) 隻 \(bytes / 1024) KB（\(rig.facings.count) 個畫好的方向）")
        }
        #expect(total <= Self.budget,
                "一家的向量貼圖在 3 倍螢幕約 \(total / 1024) KB，超過 \(Self.budget / 1024) KB：\(each.joined(separator: "、"))")
    }
}
