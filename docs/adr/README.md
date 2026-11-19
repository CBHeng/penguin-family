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
| [0006](0006-metal-rendering.md) | 箱庭用 Metal 畫，遊戲迴圈有變化才畫（「對齊像素格子、取最近的像素」已由 0007 取代） | accepted |
| [0007](0007-flat-vector-art.md) | 角色與箱庭改走平面向量：企鵝部件畫成貼圖再轉動，箱庭用多邊形；形狀格式自己定 | accepted |

## 已取代

| ADR | 決定 | 被誰取代 |
|---|---|---|
| [0001](0001-realitykit-swiftui.md) | 用 RealityKit＋SwiftUI（前提是真 3D） | 0005（2026-11-16 改走像素） |
