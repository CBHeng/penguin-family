import Foundation
import Testing
@testable import PenguinFamily

/// 向量貼圖的記憶體預算（作者 2026-11-18 決定加這個測試）：拿真實角色包，算一家在螢幕 3 倍的手機上，
/// 部件貼圖（含 mipmap）共佔多少，超過 50MB 就失敗。
///
/// 50MB 是「用記憶體換時間」要先和作者討論的門檻（`docs/architecture.md` 的技術取捨）。
/// 動作不佔貼圖（只是數字）；會讓這個數字變大的是名單多一隻、多一個畫好的方向、多一種形狀（例如表情），
/// 或貼圖準備得更細。失敗時不要直接調高預算，先和作者討論怎麼省（見架構的記憶體表）。
///
/// 作者 2026-11-19 決定：貼圖最多照螢幕 2 倍準備，所以 3 倍螢幕和 2 倍一樣大；
/// 角色包不夠時，缺的那隻是借同物種形狀塗灰的替身，貼圖另外畫一份，也算進來（和 App 的後台名單相同）。
///
/// 角色包由私有素材 repo 匯出，不進 git；乾淨 clone 下來沒有角色包，這個測試會跳過。
/// 訊息只用第幾隻，不寫角色 id（角色名稱只能出現在私有 repo）。
@MainActor
struct VectorMemoryBudgetTests {
    /// 「用記憶體換時間」的門檻（位元組）。
    static let budget = 50 * 1024 * 1024
    /// 用最細的螢幕算：iPhone 17 等機型 1pt 是 3 個實體像素。
    static let displayScale = 3.0

    private final class BundleToken {}

    /// 一家：照測試用角色包旁的名單載入，和 App 一樣（ADR 0009：幾隻由名單決定）。乾淨 clone 下來是預設的一家（都是灰色剪影）。
    static let family: [FamilyMember] = {
        let root = Bundle(for: BundleToken.self).url(forResource: "CharacterPacks", withExtension: "bundle")
        return CharacterPackLibrary.loadFamily(in: root)
    }()

    @Test(.enabled(if: family.contains { $0.character != nil }, "沒有向量角色包（乾淨 clone），跳過"))
    func familyFitsTheBudgetOnTheSharpestScreen() throws {
        let pixelsPerUnit = SpriteRenderer.vectorPixelsPerUnit(displayScale: Self.displayScale)
        // 一家每一隻實際用的造型，和 App 一樣決定（缺角色包的是同物種的替身）
        var total = 0
        var each: [String] = []
        for (i, (member, look)) in zip(Self.family, StandIn.resolve(Self.family)).enumerated() {
            let bytes = VectorRasterizer.textureBytes(look.vector, pixelsPerUnit: pixelsPerUnit)
            total += bytes
            each.append("第 \(i + 1) 隻\(member.character == nil ? "（替身）" : "") \(bytes / 1024) KB（\(look.vector.facings.count) 個畫好的方向、\(look.vector.postures.count) 個姿勢）")
        }
        #expect(total <= Self.budget,
                "一家的向量貼圖在 3 倍螢幕約 \(total / 1024) KB，超過 \(Self.budget / 1024) KB：\(each.joined(separator: "、"))")
    }

    @Test func texturesStopGrowingAbove2x() {
        // 每單位 8pt：1 倍螢幕 8 個像素、2 倍 16 個；3 倍也照 2 倍
        #expect(SpriteRenderer.vectorPixelsPerUnit(displayScale: 1) == 8)
        #expect(SpriteRenderer.vectorPixelsPerUnit(displayScale: 2) == 16)
        #expect(SpriteRenderer.vectorPixelsPerUnit(displayScale: 3) == 16)
    }
}
