# 任務與進度

最後更新：2026-11-16。各階段的內容與驗收標準見[路線圖](docs/product/roadmap.md)。

## 目前進度

**App 架構先行完成，改走像素，正在重整計畫。** 2026-11-16：App 骨架跑起來了（第一隻企鵝、點一下哈囉、狀態機、事件紀錄）。作者決定角色走像素、維持原生 Swift（[ADR 0005](docs/adr/0005-pixel-art-swiftui.md)，實機確認後定案），接著寫遊戲設計文件，再改寫路線圖與 TASKS。

## 目前工作：App 架構先行

作者 2026-11-11 的決定：專案名稱 `PenguinFamily`、App 程式放在根目錄的 `ios/`、最低支援 iOS 18、畫面先用像素原型、不寫任何台詞（台詞由作者寫）。做法見[架構](docs/architecture.md)的「World：目前的像素原型」。

1. [x] 你：用 Xcode 建專案（2026-11-13 完成；Xcode 26.6 沒有出現「Create Git repository」選項，直接把檔案加進現有 repo 的暫存區，沒有多建 repo）
2. [x] Claude：把 Xcode 建立的 `PenguinFamily/` 資料夾改名為 `ios/`，檢查專案結構，最低版本改成 iOS 18，確認能編譯（2026-11-13：在 iPhone 17 模擬器（iOS 26.5）上編譯、測試通過；iOS 18 之後用作者的 iOS 18.8 實機驗證）
3. [x] Claude：私有素材 repo 加上角色包匯出，輸出到 `Resources/CharacterPacks.bundle/`（2026-11-16 完成：部件像素寫進 `rig.json`，匯出時檢查和定稿正面圖、哈囉 56 格都相同；格式見[架構](docs/architecture.md)）
4. [x] Claude：用 Swift 改寫部件合成，加單元測試（2026-11-16 完成：假資料測規則；有角色包時，靜止姿勢和定稿相同、哈囉 56 格和 Python 逐格相同；沒有角色包時跳過）
5. [x] Claude：SwiftUI 畫面顯示第一隻，點一下播放「哈囉」；沒有角色包時顯示占位圖形（2026-11-16：模擬器截圖確認像素清楚；哈囉 56 格與 Python 逐格相同；作者在模擬器確認點擊播放正常；實機手感待確認）
6. [x] Claude：`Behavior` 最小狀態機（待機 → 被點 → 哈囉 → 待機），只輸出意圖，加測試（2026-11-16 完成：`PenguinBehavior`，6 個測試；「哈囉中再點不重來」從畫面移到 `Behavior`）
7. [x] Claude：`Memory` 用 SwiftData 記錄「被點了一下」這類事件（2026-11-16 完成：`EventLog` 只存手機、關閉 CloudKit；模擬器實測點 11 下存了 11 筆）
8. [-] Claude：`Soul` 只建 `DialogueEngine` 介面骨架，不寫台詞（2026-11-16 作者決定併入 A1 設計：台詞怎麼選要等事件清單與角色聖經）
9. [x] Claude：在模擬器跑起來截圖給你看，確認放大後不糊；更新架構文件（2026-11-16：截圖中企鵝區域只有 14 種顏色，都是調色盤色與背景色，放大沒有平滑處理）

**建專案步驟**（Xcode 版本不同，欄位名稱可能略有出入）

1. File → New → Project，平台 iOS，範本 App。
2. Product Name：`PenguinFamily`；Team：None；Organization Identifier：例如 `com.cbheng`（會出現在公開 repo）；Interface：SwiftUI；Language：Swift；Testing System：Swift Testing（UI Tests 可不勾）；Storage：None。
3. 存在 `/Users/boheng/projects/penguin`（公開 repo 根目錄）。Xcode 會建立 `PenguinFamily/` 資料夾，之後由 Claude 改名為 `ios/`，你不用動。
4. **取消勾選「Create Git repository on my Mac」**，這裡已經是 git repo。Xcode 26.6 存進現有 repo 時不會出現這個選項，找不到就不用管。

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
- [ ] 準備一台實機 iPhone（2026-11-13：作者的 iPhone 是 iOS 18.8，可用來驗證最低支援版本。2026-11-16：Xcode 已登入 Apple ID、選好 Personal Team，Team ID 在本機的 `ios/Config/Signing.local.xcconfig`；**暫停，等有傳輸線**再做：接線執行、開發者模式、信任開發者、勾選無線連線，步驟見[實機測試](docs/research/device-testing.md)）
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
- [x] Claude：查證上實機需要哪種 Apple 帳號與簽署方式（2026-11-16：自己的 iPhone 用免費 Apple ID 即可，7 天要重裝；給親友要付費會員。見[實機測試](docs/research/device-testing.md)）
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
| 有空時 | 公開 repo 目前沒有授權條款（LICENSE）：是否要加 |
| 有空時 | 看過我加的底線是否同意：[語氣底線](.claude/rules/character-voice.md)、[安全與隱私底線](.claude/rules/safety-privacy.md) |
| A2 發送前 | 玩偶造型：改為原創、取得授權，或了解風險後維持原樣（見 [ADR 0004](docs/adr/0004-plush-likeness-private-use.md)） |
| A2 之後 | 先做 A3（小工具與步數）還是 B1（聊天） |
| B1 | AI 供應商與模型（盲測後決定） |
