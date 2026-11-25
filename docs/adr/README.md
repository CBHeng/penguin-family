# 決策紀錄（ADR）

每份 ADR 記一個重要決定：決定了什麼、為什麼、代價。ADR 只新增、不搬動；決定改變時寫新的一份，舊的標成「已取代」留著。來龍去脈依日期整理在[時間線](../history/timeline.md)。

狀態：`accepted` 已定案；`proposed` 提案中，寫明什麼條件下定案。改動已定案的決定前要先問作者。

## 現行

| ADR | 決定 | 狀態 |
|---|---|---|
| [0002](0002-hybrid-soul-engine.md) | 預寫台詞優先，只有聊天用雲端 AI | accepted |
| [0003](0003-on-device-memory.md) | 記憶存手機，後端不保留聊天內容 | accepted |
| [0004](0004-plush-likeness-private-use.md) | 照玩偶原樣僅限自用與小範圍；造型可替換；公開 repo 的界線 | accepted |
| [0005](0005-pixel-art-swiftui.md) | 維持原生 Swift（「走像素、部件在原始像素尺寸合成」已由 0007 取代；「畫面用 SwiftUI」已由 0006 取代） | accepted |
| [0006](0006-metal-rendering.md) | 箱庭用 Metal 畫，遊戲迴圈有變化才畫（「對齊像素格子、取最近的像素」已由 0007 取代；推進世界移到模擬的執行緒，見 0008） | accepted |
| [0007](0007-flat-vector-art.md) | 角色與箱庭改走平面向量：企鵝部件畫成貼圖再轉動，箱庭用多邊形；形狀格式自己定 | accepted |
| [0008](0008-simulation-frame-render-layers.md) | 狀態與繪圖分成模擬、畫面準備、繪圖三層；模擬在自己的執行緒、固定節拍每秒 30 次，畫面內插；狀態機不參與 render | accepted |
| [0009](0009-characters-species-motion-data.md) | 角色不分物種：名單（幾隻、哪種動物）與動作都是資料，動作由私有素材 repo 匯出成關鍵影格，App 只放播放器（片段的格式由 0010 擴充） | accepted |
| [0010](0010-motion-visibility-loops-effects.md) | 片段可以換部件（藏起來、換顯示哪一個）、動作可以循環；特效的形狀不分物種共用，怎麼動照樣是匯出的片段（擴充 0009） | accepted |
| [0011](0011-postures-staged-motions-bed.md) | 躺姿是另一個造型（姿勢），動作可以分段帶位移，家具有床位、角色可以在家具上；半透明的影子、躺著的觸控範圍（擴充 0009、0010） | accepted |

## 已取代

| ADR | 決定 | 被誰取代 |
|---|---|---|
| [0001](0001-realitykit-swiftui.md) | 用 RealityKit＋SwiftUI（前提是真 3D） | 0005（2026-11-16 改走像素） |
