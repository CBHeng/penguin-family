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
│  │  └─ Resources/  CharacterPacks.bundle/<角色>/rig.json、CharacterPacks.bundle/duo.json（不進 git）
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
- **`CharacterPacks.bundle/` 不進 git。** repo 是公開的，所以乾淨 clone 下來沒有角色包；這時 App 顯示簡單的占位圖形，不能壞掉。單元測試用測試專用的假資料，不依賴這個資料夾。
- **程式不寫死角色 id。** 角色包的資料夾名稱就是角色 id，可能帶有角色名稱，而角色名稱只能出現在私有 repo；App 要列出 `CharacterPacks.bundle/` 底下有哪些角色，不在程式或測試裡寫死。
- **人設是資料。** 台詞與個性放 JSON，作者不改程式也能調教。填好的角色聖經是權威來源（位置見[範本](characters/bible.md)），JSON 依它產生；內容有出入時，以角色聖經為準。兩隻共有的關係資料放 `duo.json`。
- **聊天內容與共同回憶由 `Memory` 管理，只存手機。** 後端只轉發，原因見 [ADR 0003](adr/0003-on-device-memory.md)。

## World：目前的像素原型

[ADR 0001](adr/0001-realitykit-swiftui.md) 的 RealityKit 真 3D 還沒有被推翻；像素或 3D 尚未決定（2026-11-11）。在那之前，`World` 先用像素圖做原型，之後若走 3D 只替換這一層。

- **部件合成**：企鵝拆成身體、手、頭與五官等部件。每格先在原始像素尺寸的小畫布上合成，再整數倍放大顯示，所以結果和私有素材 repo 的動作預覽 GIF 一致。
- **合成規則**：身體、手、頭的底色與輪廓可以旋轉；帽子、嘴巴、眼睛等小部件只跟著移動、不轉，因為像素圖轉小角度會把小形狀弄碎；外框在每格組好後才統一描。
- **合成是純 Swift**：不依賴繪圖框架，可以寫單元測試；顯示層只負責把合成好的圖放大貼上，放大時不能做平滑處理。
- **為什麼不直接用 SpriteKit 旋轉部件**：SpriteKit 是在螢幕解析度旋轉放大後的貼圖，像素不會重新對齊格子，和調好的預覽不同，帽子與五官錯位的問題可能再出現（推測，未實測）。查證紀錄見[素材調查](research/asset-and-engine.md)。
- **角色包內容**：每隻角色一個 `rig.json`，由私有素材 repo 的 `export_pack.py` 匯出到 `Resources/CharacterPacks.bundle/<角色>/`（作者 2026-11-16 決定）。內容：
  - `canvas`：部件畫布的寬高；以下座標都是這個畫布上的格子座標。
  - `palette`、`outline`、`empty`：調色盤代碼對應的顏色、外框用哪個代碼、哪個字元代表透明。
  - `parts`：每個部件的左上角 `x`、`y` 與每列像素 `rows`（一個字元一格，用調色盤代碼）。會轉的部件有轉軸 `pivot`；只移動不轉的部件標 `follows`（跟著哪個部件）與 `anchor`（跟著轉的那一點）。
  - `drawOrder`、`rig`：疊放順序，以及合成用的參數（脖子高度、手舉多高換成舉手圖）。
  - `front`：定稿正面圖在畫布上的位置與像素，用來檢查「部件都不動時和定稿完全相同」。
- **部件像素寫在 JSON，不用 PNG**：合成與測試只需要純 Swift，不用解碼圖片；顏色也一定精確，不會被色彩管理改掉（後者是推測，未實測）。要看圖時，看私有素材 repo 的預覽 GIF。
- **為什麼是 `.bundle`**：2026-11-16 用 Xcode 26.6 實測，專案同步的資料夾會把子資料夾的檔案攤平放進 App，兩隻角色的 `rig.json` 會撞名、編譯失敗；資料夾名稱以 `.bundle` 結尾時會整包複製、保留結構。沒有角色包時也能編譯。
- **合成的對照規格**：私有素材 repo 匯出程式裡的 `compose_from_rig()` 只用 `rig.json` 合成，匯出時會和原本的動作程式逐格比對；Swift 版 `World/Pixel/RigCompositor` 照它實作。
- **取整要和 Python 相同**：Python 3 的 `round()` 遇到 .5 取最近的偶數，Swift 的 `rounded()` 預設遠離 0，所以 Swift 版明確用 `.toNearestOrEven`（2026-11-16 查證：[SE-0113](https://github.com/swiftlang/swift-evolution/blob/main/proposals/0113-rounding-functions-on-floatingpoint.md)、[Apple `rounded(_:)`](https://developer.apple.com/documentation/swift/double/rounded(_:))、[Python 文件討論](https://www.python.org/pipermail/docs/2013-February/012898.html)）。

## 測試

單元測試涵蓋行為狀態轉換、部件合成規則、台詞選擇規則和 AI 失敗回退。

部件合成分兩層測（作者 2026-11-16 決定）：

- **合成規則**（`RigCompositorTests`）：用測試裡手寫的 10x10 假角色，永遠會跑。測靜止時和手算結果相同、跟著頭的部件只移動不轉、手超過角度換成舉手圖、.5 取偶數、格式錯誤會被拒絕。
- **和 Python 逐格相同**（`CharacterPackParityTests`）：私有素材 repo 的匯出程式把 `rig.json` 和每個動作的對照檔 `<動作>.golden.json` 寫到 `PenguinFamilyTests/CharacterPacks.bundle/<角色>/`（不進 git；跑測試時會跟著測試 bundle 放進 App 的 `PlugIns/`，一般建置的 App 不含，2026-11-16 實測 Release 建置）。測靜止時和定稿正面圖相同、動作每一格和 Python 相同。沒有角色包時自動跳過。
