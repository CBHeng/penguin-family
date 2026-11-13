# 任務與進度

最後更新：2026-11-11。各階段的內容與驗收標準見[路線圖](docs/product/roadmap.md)。

## 目前進度

**素材實驗暫停，改為 App 架構先行。** 第一隻的像素正面與「哈囉」動作已定案（存在私有素材 repo）。作者 2026-11-11 決定先建 App 骨架，並把像素原型放進畫面；像素或 3D 仍未決定，[ADR 0001](docs/adr/0001-realitykit-swiftui.md) 不改。

## 目前工作：App 架構先行

作者 2026-11-11 的決定：專案名稱 `PenguinFamily`、App 程式放在根目錄的 `ios/`、最低支援 iOS 18、畫面先用像素原型、不寫任何台詞（台詞由作者寫）。做法見[架構](docs/architecture.md)的「World：目前的像素原型」。

1. [ ] 你：用 Xcode 建專案（步驟見下方）
2. [ ] Claude：把 Xcode 建立的 `PenguinFamily/` 資料夾改名為 `ios/`，檢查專案結構，最低版本改成 iOS 18，確認能編譯
3. [ ] Claude：私有素材 repo 加上角色包匯出（部件圖與 `rig.json`），輸出到 `Resources/CharacterPacks/`
4. [ ] Claude：用 Swift 改寫部件合成，加單元測試（不轉時要和定稿正面圖完全相同）
5. [ ] Claude：SwiftUI 畫面顯示第一隻，點一下播放「哈囉」；沒有角色包時顯示占位圖形
6. [ ] Claude：`Behavior` 最小狀態機（待機 → 被點 → 哈囉 → 待機），只輸出意圖，加測試
7. [ ] Claude：`Memory` 用 SwiftData 記錄「被點了一下」這類事件
8. [ ] Claude：`Soul` 只建 `DialogueEngine` 介面骨架，不寫台詞
9. [ ] Claude：在模擬器跑起來截圖給你看，確認放大後不糊；更新架構文件

**建專案步驟**（Xcode 版本不同，欄位名稱可能略有出入）

1. File → New → Project，平台 iOS，範本 App。
2. Product Name：`PenguinFamily`；Team：None；Organization Identifier：例如 `com.cbheng`（會出現在公開 repo）；Interface：SwiftUI；Language：Swift；Testing System：Swift Testing（UI Tests 可不勾）；Storage：None。
3. 存在 `/Users/boheng/projects/penguin`（公開 repo 根目錄）。Xcode 會建立 `PenguinFamily/` 資料夾，之後由 Claude 改名為 `ios/`，你不用動。
4. **取消勾選「Create Git repository on my Mac」**，這裡已經是 git repo。

| 階段 | 內容 | 粗估 | 狀態 |
|---|---|---|---|
| C0 | 專案基礎文件 | - | ✅ 完成（`0bc95e4`） |
| **A0** | **技術驗證：3D 素材、RealityKit** | **3 天** | **⏸ S1 暫停，改做 App 架構** |
| A1 | 可每天打開的雛型 | 2～3 週 | 未開始 |
| A2 | 親友測試（不含聊天） | 1 週 | 未開始 |
| A3 | 小工具與步數 | 2 週 | 未開始 |
| A4 | 地圖連動 | 另外規劃 | 未開始 |
| B1 | 聊天 | 2 週 | 未開始 |
| B2 | 開放聊天給親友 | 1 週 | 未開始 |

A 是箱庭生活，App 不接 AI；B 是聊天靈魂，App 開始接 AI。

## 現在輪到你

- [x] 安裝 Xcode（2026-11-04 檢查：Xcode 26.6 已在 `/Applications`）
- [x] 同意 Xcode 授權條款，並讓指令列改用 Xcode（2026-11-04 檢查：`xcodebuild` 正常，有 iOS 26.5 SDK）
- [x] 下載 iOS 模擬器（2026-11-04 檢查：iOS 26.5 已就緒）
- [ ] 準備一台實機 iPhone
- [ ] 自己拍兩隻玩偶的多角度照片，放進 `penguin-family-assets/`（私有 repo `CBHeng/penguin-family-assets`，2026-11-07 已上傳）。2026-11-05：第一隻已換成 9 張去背 PNG，檢查過角度足夠，有 3 張要修去背；第二隻等第一隻外觀滿意後再補
- [x] 決定何時開始 A0（2026-11-05：先開始 S1，先做第一隻）

## A0 工作清單

**S1 素材實驗**
- [ ] Claude：查 Meshy、Tripo 的現行條款，並確認生成的模型會不會公開（2026-11-05：Meshy 已讀；Tripo 官網回 403，還沒讀到）
- [ ] 你：確認要用哪個工具、可以上傳照片
- [x] Claude 和你：畫第一隻的像素圖正面（2026-11-05 定稿，存在 `penguin-family-assets/`）
- [x] Claude 和你：第一隻的「哈囉」動作（2026-11-07 定案；拆成部件各自動，整張圖一起晃太單調）
- [ ] Claude 和你：生成第一隻的 3D 模型，匯出 USDZ（是否還要做，看下方「像素或 3D」的決定）
- [ ] 你：第一隻外觀滿意後，補第二隻的照片並生成
- [ ] 你：在 iPhone 上看遠景與近景，判斷是否通過
- [ ] Claude：把素材路線的結果寫成 ADR

**S2 RealityKit 驗證**
- [ ] Claude：查證上實機需要哪種 Apple 帳號與簽署方式
- [ ] Claude：建立固定鏡頭的場景（Xcode 專案改在「App 架構先行」建立）
- [ ] Claude：做搖擺走路、點擊反應、長按拉近與觸覺回饋
- [x] 確認最低 iOS 版本（2026-11-11 作者決定：iOS 18）
- [ ] 你：在實機試抱抱手感，判斷是否通過

## 之後要你準備的

**A1 開始前**
- [ ] 兩隻玩偶的名字、各自的個性與差異（填在 `penguin-family-assets/bible.md`，不要填在公開的[角色聖經範本](docs/characters/bible.md)上）。2026-11-05：第一隻的名字與外觀已填，個性和第二隻待填
- [ ] 30～50 句真實講過的話或情境

**A1 期間**
- [ ] 依事件與台詞清單撰寫台詞（台詞量決定企鵝多快開始重複）

## 等你決定

| 什麼時候 | 要決定什麼 |
|---|---|
| 有空時 | `penguin-family` 是正式 App 名稱，還是開發代號 |
| 有空時 | commit 裡的 email 是公開的：是否改用 GitHub 的 noreply 信箱 |
| 有空時 | 公開 repo 目前沒有授權條款（LICENSE）：是否要加 |
| 有空時 | 看過我加的底線是否同意：[語氣底線](.claude/rules/character-voice.md)、[安全與隱私底線](.claude/rules/safety-privacy.md) |
| App 原型跑起來後 | 角色走像素或 3D：走像素要重新檢視 [ADR 0001](docs/adr/0001-realitykit-swiftui.md) 的真 3D 前提（2026-11-11 先不決定，畫面先用像素原型） |
| S1 上傳前 | 市售玩偶的照片能否上傳：Meshy 禁止上傳含第三方受著作權保護內容的參考圖（見[素材調查](docs/research/asset-and-engine.md)） |
| S2 卡住時 | 是否改用 Unity |
| A2 發送前 | 玩偶造型：改為原創、取得授權，或了解風險後維持原樣（見 [ADR 0004](docs/adr/0004-plush-likeness-private-use.md)） |
| A2 之後 | 先做 A3（小工具與步數）還是 B1（聊天） |
| B1 | AI 供應商與模型（盲測後決定） |
