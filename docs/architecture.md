# 架構

程式與這份文件不同時，以程式為準並更新這份文件。2026-11-16「App 架構先行」完成時，已實作的是 `World`、`Behavior`、`Memory` 的最小版本，以及 `Resources` 的角色包；其餘模組還是規劃。

專案名稱 `PenguinFamily`，最低支援 iOS 18；App 程式放在根目錄的 `ios/`（作者 2026-11-11 決定）。專案層級的建置設定在 `ios/Config/`，簽署用的 Team ID 不進 git（見[實機測試](research/device-testing.md)）。

```
penguin-family/                    公開 repo
├─ ios/                           App
│  ├─ PenguinFamily.xcodeproj
│  ├─ Config/        Base.xcconfig；Signing.local.xcconfig（不進 git）
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

- **`Behavior` 只輸出意圖，`World` 負責呈現。** `Behavior` 不匯入任何繪圖框架，所以可以單獨測試，換畫面技術時也能沿用。目前的 `PenguinBehavior` 是最小狀態機（2026-11-16）：待機 →（主人點一下）→ 哈囉 →（`World` 回報播完）→ 待機；哈囉中再點會被忽略。動作播多久由 `World` 決定，`Behavior` 不處理時間。
- **`DialogueEngine` 是台詞來源的 protocol。** 路線一用 `ScriptedEngine`，路線二加 `CloudEngine`。決策原因見 [ADR 0002](adr/0002-hybrid-soul-engine.md)。
- **箱庭與聊天透過事件紀錄連接。** 箱庭寫入發生的事，聊天讀取後才能提到；聊天再把主人的心情和共同回憶寫回，影響箱庭。路線一就要記下事件，避免之後重工。
- **`CharacterPack` 把造型與個性資料化。** 換造型不用改程式，原因見 [ADR 0004](adr/0004-plush-likeness-private-use.md)。
- **`CharacterPacks.bundle/` 不進 git。** repo 是公開的，所以乾淨 clone 下來沒有角色包；這時 App 顯示簡單的占位圖形，不能壞掉。單元測試用測試專用的假資料，不依賴這個資料夾。
- **程式不寫死角色 id。** 角色包的資料夾名稱就是角色 id，可能帶有角色名稱，而角色名稱只能出現在私有 repo；App 要列出 `CharacterPacks.bundle/` 底下有哪些角色，不在程式或測試裡寫死。
- **人設是資料。** 台詞與個性放 JSON，作者不改程式也能調教。填好的角色聖經是權威來源（位置見[範本](characters/bible.md)），JSON 依它產生；內容有出入時，以角色聖經為準。兩隻共有的關係資料放 `duo.json`。
- **聊天內容與共同回憶由 `Memory` 管理，只存手機。** 後端只轉發，原因見 [ADR 0003](adr/0003-on-device-memory.md)。
- **事件紀錄目前只記「主人點了企鵝」**（2026-11-16）：`Memory/EventLog` 用 SwiftData 存在手機上，明確關閉 CloudKit 同步；換機與備份到 B1 再決定。每次點擊都記，包含哈囉中被忽略的點擊；記下是哪一隻（角色包 id）。事件種類存字串，之後新增種類不用遷移資料庫；舊版本讀到不認得的種類會略過。資料庫打不開時改用暫存，企鵝照樣能用。
- **日誌不寫角色 id 與內容**：錯誤訊息可能含檔案路徑（帶角色 id），用 `privacy: .private` 讓系統日誌預設遮蔽。

## World：像素

角色與箱庭走像素，畫面用 SwiftUI 與自寫的部件合成，見 [ADR 0005](adr/0005-pixel-art-swiftui.md)（2026-11-16，取代以真 3D 為前提的 ADR 0001；實機確認後定案）。

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
- **箱庭（等角）**：`World/Room/`。`RoomLayout` 是邏輯：地板格子、家具佔用的格子與高度、牆上的東西、擺放檢查，不管畫面。`IsoProjection` 把格子 (i, j) 與高度換算成像素（每格 32×16，2:1 斜率）。`RoomRenderer` 畫背景（牆、地板、窗戶）與每件家具的色塊盒子，並依「最靠近主人的角」排前後。`RoomView` 把背景、家具與企鵝疊起來，每個像素最大 3pt。找路與行為只用格子座標，換畫法時不受影響。
- **鏡頭與縮放**：`RoomCamera` 記畫面中央對著箱庭的哪一點（箱庭像素），限制在範圍內；`RoomZoom` 決定每個像素幾 pt（最大 3pt，最小房間左右塞滿畫面），兩者都是純數學、有單元測試。`RoomView` 把整張箱庭反向位移後裁切。位移對齊螢幕實體像素（依 `displayScale`），畫面跟著手指走又不糊；整張一起移動，像素彼此仍對齊。捏合時連續縮放，放開後吸附到整數個實體像素，讓每個像素一樣大。拖曳量用不會動的外框（具名座標空間）量：手勢掛在會移動的背景上，用預設的 `.local` 量會來回閃（2026-11-16 模擬器實測）。
- **顯示**：`World/PenguinView` 每格先合成原始尺寸的圖，再以整數倍放大、關閉平滑處理（`interpolation(.none)`）。哈囉以每秒 20 格播放，時間軸 `HelloMotion` 照私有素材 repo 的 `hello_pose()`，兩隻共用。`PenguinView` 照 `Behavior` 的意圖播放，點擊與播完都交回 `Behavior`。`CharacterPackLibrary` 列出 App 裡的角色包，載入第一隻能用的；沒有或全壞時顯示灰色占位剪影。
- **取整要和 Python 相同**：Python 3 的 `round()` 遇到 .5 取最近的偶數，Swift 的 `rounded()` 預設遠離 0，所以 Swift 版明確用 `.toNearestOrEven`（2026-11-16 查證：[SE-0113](https://github.com/swiftlang/swift-evolution/blob/main/proposals/0113-rounding-functions-on-floatingpoint.md)、[Apple `rounded(_:)`](https://developer.apple.com/documentation/swift/double/rounded(_:))、[Python 文件討論](https://www.python.org/pipermail/docs/2013-February/012898.html)）。

## 測試

單元測試涵蓋行為狀態轉換、部件合成規則、台詞選擇規則和 AI 失敗回退。

部件合成分兩層測（作者 2026-11-16 決定）：

- **合成規則**（`RigCompositorTests`）：用測試裡手寫的 10x10 假角色，永遠會跑。測靜止時和手算結果相同、跟著頭的部件只移動不轉、手超過角度換成舉手圖、.5 取偶數、格式錯誤會被拒絕。
- **和 Python 逐格相同**（`CharacterPackParityTests`）：私有素材 repo 的匯出程式把 `rig.json` 和每個動作的對照檔 `<動作>.golden.json` 寫到 `PenguinFamilyTests/CharacterPacks.bundle/<角色>/`（不進 git；跑測試時會跟著測試 bundle 放進 App 的 `PlugIns/`，一般建置的 App 不含，2026-11-16 實測 Release 建置）。測靜止時和定稿正面圖相同、動作每一格和 Python 相同，App 用的哈囉時間軸每一格的姿勢也和 Python 相同。沒有角色包時自動跳過。
- **事件紀錄**（`EventLogTests`）：每個測試用自己的記憶體資料庫，不碰手機上的資料。
- **顯示需要的部分**（`PenguinDisplayTests`）：哈囉時間軸頭尾都是站好、顏色轉換精確、找角色包（沒有、壞掉、只有部分能用）。點擊與動畫的手感不在單元測試裡，以模擬器與實機確認。
