---
status: accepted
date: 2026-11-16
supersedes: 0005 的「畫面用 SwiftUI」
---

# 箱庭的繪圖改用 Metal

[ADR 0005](0005-pixel-art-swiftui.md) 決定走像素、畫面用 SwiftUI。作者 2026-11-16 要求「不以開發便利為主」重新評估渲染效能與順暢度（見[渲染效能評估](../research/rendering-performance.md)），看過 Metal、SpriteKit、Core Animation、SwiftUI Canvas 的取捨後，選了 Metal。

## 決定

- **箱庭與企鵝用 Metal 畫。** 每一格照清單把貼圖畫上去，所有東西對齊同一個像素格子，放大時取最近的像素、不平滑。（2026-11-18：「對齊像素格子、取最近的像素」由 [ADR 0007](0007-flat-vector-art.md) 取代，改走向量；用 Metal 畫與遊戲迴圈不變。）
- **走像素、部件合成自己寫的決定不變**（ADR 0005）。部件仍在原始像素尺寸合成，載入時預先算好每一格；Metal 只負責貼圖。（2026-11-18：走像素、在原始像素尺寸合成、預先算好每一格由 [ADR 0007](0007-flat-vector-art.md) 取代，改成部件畫成貼圖、每一格在 Metal 依姿勢轉動；部件合成自己寫的決定不變。）
- **遊戲迴圈**：跟著螢幕更新的節奏，最高到手機支援的更新率（ProMotion 機型 120Hz，Info.plist 加 `CADisableMinimumFrameDurationOnPhone`，不是權限）。有變化才畫，沒有東西在動時暫停，省電（作者 2026-11-16 決定）。（2026-11-20：推進世界的工作移到模擬自己的執行緒，遊戲迴圈只做畫面準備與繪圖，見 [ADR 0008](0008-simulation-frame-render-layers.md)；跟著螢幕節奏、有變化才畫、沒東西在動時暫停不變。）
- **介面仍用 SwiftUI**：載入畫面、文字、之後的對話泡泡與選單。手勢也用 SwiftUI，掛在不會移動的 Metal 畫面上。

## 為什麼

- **效能上限最高**：每一格主執行緒只做「算這一格要畫什麼」，不用像 SwiftUI 那樣比對、排版整棵 view；GPU 的工作只是貼幾十張小圖。Apple 把卡頓分成 App 來不及交出畫面與系統來不及畫兩種，我們的風險在前者（推論，見評估）。
- **像素保證對齊**：所有東西在同一個像素格子上，縮放中也一致。
- **長期最穩**：Metal 是 Apple 繪圖的底層。SpriteKit 前景不確定（Apple 2026 年 5 月說目前沒有 deprecated，但不談未來；同類的 SceneKit 已在 2025 年軟性 deprecated），而且 iOS 26 有掉幀的回報，2026 年 5 月 Apple 說 bug 仍開著。
- **代價**：貼圖、點擊判斷、文字要自己處理，工作量比 SwiftUI 多。

## 影響

- **建置需要 Metal Toolchain。** Xcode 26 起 shader 編譯器要另外下載：`xcodebuild -downloadComponent MetalToolchain`（Apple 官方，約 688MB，2026-11-16 實際下載）。每次更新 Xcode 後要重新下載（[Apple：Downloading and installing additional Xcode components](https://developer.apple.com/documentation/xcode/downloading-and-installing-additional-xcode-components)、[Apple 論壇 803174](https://developer.apple.com/forums/thread/803174)）。
- **畫面一致**：2026-11-16 在模擬器上截圖，Metal 版和 SwiftUI 版的箱庭逐像素相同（1206×2452 像素，0 個不同）。
- **沿用的部分**：房間邏輯、等角換算、鏡頭與縮放的數學、動作與預先算好的格子、`Behavior`、`Memory` 都沒有改。
- **刪除**：SwiftUI 版的 `PenguinView` 與把格子轉成 `CGImage` 的 `PixelImage`（作者 2026-11-16 同意刪除）。

## 定案

2026-11-16 在 iPhone 11（iOS 18.7.8）用正式版量 40 秒的 Animation Hitches，包含拖曳、捏合、點企鵝播哈囉與閒置：

- **卡頓（畫面晚交）0 次**。
- 每秒畫面張數：拖曳與捏合時 15～54 張（有變化才畫，手指慢時張數少）；播哈囉時穩定 20 張；不動時 0 張，確認有省電。
- 主執行緒延遲超過 33 毫秒 1 次（39 毫秒），在第一次點企鵝時。之後兩次量測結果不一（一次有 3 次延遲、最長 238 毫秒，一次 0 次），原因還在追（見 TASKS）。

作者也覺得操作順，改為 accepted。
