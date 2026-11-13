# 架構

目前還沒有程式碼，這裡是規劃中的結構。實作後，以程式碼為準並更新這份文件。

專案名稱 `PenguinFamily`，最低支援 iOS 18；App 程式放在根目錄的 `ios/`（作者 2026-11-11 決定）。Xcode 建專案時會建立 `PenguinFamily/` 資料夾，建好後改名為 `ios/`；實際路徑以建好的專案為準。

```
penguin-family/                    公開 repo
├─ ios/                           App
│  ├─ PenguinFamily.xcodeproj
│  ├─ PenguinFamily/
│  │  ├─ App/        SwiftUI 外殼、抱抱介面、Chat/ 聊天介面
│  │  ├─ World/      畫面：箱庭、鏡頭、企鵝的呈現
│  │  ├─ Behavior/   行為狀態機與隨機事件（純 Swift）
│  │  ├─ Soul/       角色聖經、台詞選擇、DialogueEngine
│  │  ├─ Memory/     本機關係狀態、事件紀錄、聊天內容與共同回憶（SwiftData）
│  │  ├─ Activity/   A3 才加入的步數連動
│  │  ├─ Feel/       觸覺與音效
│  │  └─ Resources/  CharacterPacks/<角色>/、CharacterPacks/duo.json（不進 git）
│  ├─ PenguinFamilyTests/   單元測試
│  └─ PenguinFamilyWidget/  A3 才加入
├─ backend/                       B1 才加入的薄後端
└─ penguin-family-assets/         私有 repo，不進公開 repo（見 ADR 0004）
```

## 模組邊界

- **`Behavior` 只輸出意圖，`World` 負責呈現。** `Behavior` 不匯入任何繪圖框架，所以可以單獨測試，換畫面技術時也能沿用。
- **`DialogueEngine` 是台詞來源的 protocol。** 路線一用 `ScriptedEngine`，路線二加 `CloudEngine`。決策原因見 [ADR 0002](adr/0002-hybrid-soul-engine.md)。
- **箱庭與聊天透過事件紀錄連接。** 箱庭寫入發生的事，聊天讀取後才能提到；聊天再把主人的心情和共同回憶寫回，影響箱庭。路線一就要記下事件，避免之後重工。
- **`CharacterPack` 把造型與個性資料化。** 換造型不用改程式，原因見 [ADR 0004](adr/0004-plush-likeness-private-use.md)。
- **`CharacterPacks/` 不進 git。** repo 是公開的，所以乾淨 clone 下來沒有角色包；這時 App 顯示簡單的占位圖形，不能壞掉。單元測試用測試專用的假資料，不依賴這個資料夾。
- **人設是資料。** 台詞與個性放 JSON，作者不改程式也能調教。填好的角色聖經是權威來源（位置見[範本](characters/bible.md)），JSON 依它產生；內容有出入時，以角色聖經為準。兩隻共有的關係資料放 `duo.json`。
- **聊天內容與共同回憶由 `Memory` 管理，只存手機。** 後端只轉發，原因見 [ADR 0003](adr/0003-on-device-memory.md)。

## World：目前的像素原型

[ADR 0001](adr/0001-realitykit-swiftui.md) 的 RealityKit 真 3D 還沒有被推翻；像素或 3D 尚未決定（2026-11-11）。在那之前，`World` 先用像素圖做原型，之後若走 3D 只替換這一層。

- **部件合成**：企鵝拆成身體、手、頭與五官等部件。每格先在原始像素尺寸的小畫布上合成，再整數倍放大顯示，所以結果和私有素材 repo 的動作預覽 GIF 一致。
- **合成規則**：身體、手、頭的底色與輪廓可以旋轉；帽子、嘴巴、眼睛等小部件只跟著移動、不轉，因為像素圖轉小角度會把小形狀弄碎；外框在每格組好後才統一描。
- **合成是純 Swift**：不依賴繪圖框架，可以寫單元測試；顯示層只負責把合成好的圖放大貼上，放大時不能做平滑處理。
- **為什麼不直接用 SpriteKit 旋轉部件**：SpriteKit 是在螢幕解析度旋轉放大後的貼圖，像素不會重新對齊格子，和調好的預覽不同，帽子與五官錯位的問題可能再出現（推測，未實測）。查證紀錄見[素材調查](research/asset-and-engine.md)。
- **角色包內容**：部件圖與骨架設定 `rig.json`（部件、轉軸、哪些部件只移動不轉），由私有素材 repo 的程式匯出到 `Resources/CharacterPacks/<角色>/`。

## 測試

單元測試涵蓋行為狀態轉換、部件合成規則、台詞選擇規則和 AI 失敗回退。
