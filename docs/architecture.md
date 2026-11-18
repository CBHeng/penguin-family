# 架構

程式與這份文件不同時，以程式為準並更新這份文件。這份寫「為什麼這樣切」；目前有哪些檔案、各自負責什麼、怎麼串起來，見[程式地圖](code-map.md)。

已實作的是 `World`、`Behavior`、`Memory` 的最小版本，以及 `Resources` 的角色包；下面目錄圖標「未建立」的還是規劃。過去的變化見[時間線](history/timeline.md)。

專案名稱 `PenguinFamily`，最低支援 iOS 18；App 程式放在根目錄的 `ios/`（作者 2026-11-11 決定）。專案層級的建置設定在 `ios/Config/`，簽署用的 Team ID 不進 git（見[實機測試](research/device-testing.md)）。

```
penguin-family/                    公開 repo
├─ ios/                           App
│  ├─ PenguinFamily.xcodeproj
│  ├─ Config/        Base.xcconfig（含版本號）；PenguinFamily-Info.plist；Signing.local.xcconfig（不進 git）
│  ├─ PenguinFamily/
│  │  ├─ PenguinFamilyApp、ContentView、LoadingView、GameView   App 外殼（載入畫面 → 主遊戲）
│  │  ├─ App/        抱抱介面、Chat/ 聊天介面（未建立；外殼目前在根目錄）
│  │  ├─ World/      畫面：箱庭、鏡頭、企鵝的呈現（Pixel/ 合成、Room/ 箱庭、Render/ Metal 繪圖）
│  │  ├─ Behavior/   行為狀態機與隨機事件（純 Swift）
│  │  ├─ Soul/       角色聖經、台詞選擇、DialogueEngine（未建立）
│  │  ├─ Memory/     本機關係狀態、事件紀錄、聊天內容與共同回憶（SwiftData）
│  │  ├─ Activity/   步數連動（未建立，A3）
│  │  ├─ Feel/       觸覺與音效（未建立）
│  │  └─ Resources/  CharacterPacks.bundle/<角色>/rig.json、CharacterPacks.bundle/duo.json（不進 git）
│  ├─ PenguinFamilyTests/   單元測試
│  └─ PenguinFamilyWidget/  小工具（未建立，A3）
├─ backend/                       薄後端（未建立，B1）
└─ penguin-family-assets/         私有 repo，不進公開 repo（見 ADR 0004）
```

## 模組邊界

- **`Behavior` 只輸出意圖，`World` 負責呈現。** `Behavior` 不匯入任何繪圖框架，所以可以單獨測試，換畫面技術時也能沿用。目前的 `PenguinBehavior` 是最小狀態機：待機 →（主人點一下）→ 哈囉 →（`World` 回報播完）→ 待機；哈囉中再點會被忽略。每隻企鵝一個，`GameView` 依企鵝的身分（`PenguinID`）分給各自的狀態機。動作播多久由 `World` 決定，`Behavior` 不處理時間。
- **舞台分後台與台上，用身分加入、移除，不用數量**（作者 2026-11-17 決定）。`RoomStage` 建立時給後台名單（一家每一隻的身分與造型），圖在載入時一次送進 GPU；誰在台上用 `add`、`remove` 決定，只有台上的會畫、點得到、鏡頭會看。點擊、動作播完、貼圖都用 `PenguinID` 認是哪一隻，不用陣列的第幾個：台上有誰會變（寫移動時第二隻先留在後台、之後屋內與庭院之間進出），用編號會對錯隻。`PenguinID` 不是 enum，因為角色 id 不能寫進程式（見下一條）。
- **`DialogueEngine` 是台詞來源的 protocol。** 路線一用 `ScriptedEngine`，路線二加 `CloudEngine`。決策原因見 [ADR 0002](adr/0002-hybrid-soul-engine.md)。
- **箱庭與聊天透過事件紀錄連接。** 箱庭寫入發生的事，聊天讀取後才能提到；聊天再把主人的心情和共同回憶寫回，影響箱庭。路線一就要記下事件，避免之後重工。
- **`CharacterPack` 把造型與個性資料化。** 換造型不用改程式，原因見 [ADR 0004](adr/0004-plush-likeness-private-use.md)。
- **`CharacterPacks.bundle/` 不進 git。** repo 是公開的，所以乾淨 clone 下來沒有角色包；這時 App 顯示簡單的占位圖形，不能壞掉。單元測試用測試專用的假資料，不依賴這個資料夾。
- **程式不寫死角色 id。** 角色包的資料夾名稱就是角色 id，可能帶有角色名稱，而角色名稱只能出現在私有 repo；App 要列出 `CharacterPacks.bundle/` 底下有哪些角色，不在程式或測試裡寫死。
- **人設是資料。** 台詞與個性放 JSON，作者不改程式也能調教。填好的角色聖經是權威來源（位置見[範本](characters/bible.md)），JSON 依它產生；內容有出入時，以角色聖經為準。兩隻共有的關係資料放 `duo.json`。
- **聊天內容與共同回憶由 `Memory` 管理，只存手機。** 後端只轉發，原因見 [ADR 0003](adr/0003-on-device-memory.md)。
- **事件紀錄目前只記「主人點了企鵝」**：`Memory/EventLog` 用 SwiftData 存在手機上，明確關閉 CloudKit 同步；換機與備份到 B1 再決定。
  - **在背景寫入**（作者 2026-11-16 決定）：`EventLog` 是 SwiftData 的 `ModelActor`，點擊時企鵝先反應，事件丟給它在背景存檔，不等存完；每件都存，不批次。時間在點的當下取，所以順序正確。外面拿到的是複製出來的 `LoggedEvent`。
  - **一律用 `EventLog.open(_:)` 在背景建立**：從主執行緒直接建立時，寫入會跟著在主執行緒做（2026-11-16 模擬器實測），背景寫入就失效。載入畫面期間先 `warmUp()` 打開資料庫。
  - 每次點擊都記，包含哈囉中被忽略的點擊；記下是哪一隻（角色包 id；灰色剪影用 `placeholder-<第幾隻>`）。事件種類存字串，之後新增種類不用遷移資料庫；舊版本讀到不認得的種類會略過。資料庫打不開時改用暫存，企鵝照樣能用。
- **日誌不寫角色 id 與內容**：錯誤訊息可能含檔案路徑（帶角色 id），用 `privacy: .private` 讓系統日誌預設遮蔽。

## 技術取捨

作者 2026-11-16 決定的原則。遇到「快一點」和「省一點」衝突時照這裡判斷；需要討論的情況，先估算用量再找作者。

1. **用首次載入換遊戲中的順暢。** 能事先做的就在載入時做好，玩的時候只取用。
   - 打開 App 先馬上顯示載入畫面，初始化放到背景，完成後才進入主遊戲（`ContentView`）。原因：iOS 會強制關掉啟動太久的 App（watchdog），Apple 沒有公布確切秒數；WWDC 2019 建議點下圖示後 400 毫秒內畫出第一個畫面（2026-11-16 查證：[WWDC19 Optimizing App Launch](https://nonstrict.eu/wwdcindex/wwdc2019/423)、[Apple：Reducing your app's launch time](https://developer.apple.com/documentation/xcode/reducing-your-app-s-launch-time)）。
   - 新增的初始化工作放進 `ContentView.load()`，不要放在 App 啟動的同步流程裡。
2. **適度用記憶體換時間。** 預先算好、快取都可以，但：
   - 這類記憶體**合計超過 50MB**，先和作者討論。
   - 用量會**隨內容持續成長**的設計（每多一個動作、一隻角色、一件家具、一個區域就多存一份），即使還沒到 50MB，也要先估算「A1 做完」與「長期」的用量，和作者討論計畫再做。
   - 用量要量得出來：例如 `CharacterFrames.byteCount`。

目前的用量（2026-11-16，Mac M4 Pro 上量）：

| 項目 | 記憶體 | 載入時間 |
|---|---|---|
| 預先算好的格子：一隻、站好＋哈囉 57 張 | 約 0.44MB | 約 6 毫秒 |
| 箱庭背景與家具圖（12×12 屋內） | 約 0.4MB（推估：384×256 像素的背景圖） | 未量 |
| GPU 貼圖：上面兩項再送一份進 GPU（Metal 繪圖） | 約 0.85MB（推估） | 未量 |

## World：像素

角色與箱庭走像素、部件合成自己寫，見 [ADR 0005](adr/0005-pixel-art-swiftui.md)（2026-11-16，取代以真 3D 為前提的 ADR 0001）。箱庭用 Metal 畫，見 [ADR 0006](adr/0006-metal-rendering.md)（2026-11-16，取代 0005 的「畫面用 SwiftUI」）。兩份都已在 iPhone 11 實機確認後定案。

- **部件合成**：企鵝拆成身體、手、頭與五官等部件。每格先在原始像素尺寸的小畫布上合成，再整數倍放大顯示，所以結果和私有素材 repo 的動作預覽 GIF 一致。
- **合成規則**：身體、手、頭的底色與輪廓可以旋轉；帽子、嘴巴、眼睛等小部件只跟著移動、不轉，因為像素圖轉小角度會把小形狀弄碎；外框在每格組好後才統一描。
- **合成是純 Swift**：不依賴繪圖框架，可以寫單元測試；顯示層只負責把合成好的圖放大貼上，放大時不能做平滑處理。
- **為什麼不讓繪圖引擎旋轉部件**：引擎是在螢幕解析度旋轉放大後的貼圖，像素不會重新對齊格子，和調好的預覽不同，帽子與五官錯位的問題可能再出現（推測，未實測）。所以部件在原始像素尺寸合成好，繪圖層只貼圖、不旋轉。當時的查證紀錄已封存（[舊調查](history/research/3d-route.md#像素原型的畫面層查證日期2026-11-11)）。
- **角色包內容**：每隻角色一個 `rig.json`，由私有素材 repo 的 `export_pack.py` 匯出到 `Resources/CharacterPacks.bundle/<角色>/`（作者 2026-11-16 決定）。內容：
  - `canvas`：部件畫布的寬高；以下座標都是這個畫布上的格子座標。
  - `palette`、`outline`、`empty`：調色盤代碼對應的顏色、外框用哪個代碼、哪個字元代表透明。
  - `parts`：每個部件的左上角 `x`、`y` 與每列像素 `rows`（一個字元一格，用調色盤代碼）。會轉的部件有轉軸 `pivot`；只移動不轉的部件標 `follows`（跟著哪個部件）與 `anchor`（跟著轉的那一點）。
  - `drawOrder`、`rig`：疊放順序，以及合成用的參數（脖子高度、手舉多高換成舉手圖）。
  - `front`：定稿正面圖在畫布上的位置與像素，用來檢查「部件都不動時和定稿完全相同」。
  - `oblique`（可以沒有；舊的角色包只能面向鏡頭）：斜向四個方向（沿格線走時用），自己一張畫布。`anchor` 是腳底中心，和正面的身體轉軸對到同一點，換方向時不會跳；`leanBaseY`、`shoulderY`、`hatRow` 是合成用的列。`directions` 的左前、左後帶部件、疊放順序與走法（往前一步的方向、哪隻腳在左、手在哪側、只平移的小部件的錨點、被擋住要露出來的腳）；右前、右後只帶 `mirrorOf` 與另外放的帽子。每個方向都有 `rest`（定稿圖）。
- **部件像素寫在 JSON，不用 PNG**：合成與測試只需要純 Swift，不用解碼圖片；顏色也一定精確，不會被色彩管理改掉（後者是推測，未實測）。要看圖時，看私有素材 repo 的預覽 GIF。
- **為什麼是 `.bundle`**：2026-11-16 用 Xcode 26.6 實測，專案同步的資料夾會把子資料夾的檔案攤平放進 App，兩隻角色的 `rig.json` 會撞名、編譯失敗；資料夾名稱以 `.bundle` 結尾時會整包複製、保留結構。沒有角色包時也能編譯。
- **合成的對照規格**：私有素材 repo 匯出程式裡的 `compose_from_rig()`（正面）與 `compose_oblique_from_rig()`（斜向）只用 `rig.json` 合成，匯出時會和原本的動作程式逐格比對；Swift 版 `World/Pixel/RigCompositor`、`ObliqueCompositor` 照它們實作。
- **斜向的合成與步態**（作者 2026-11-18 決定：App 照 Python 規則重做合成，不直接帶算好的每一格）：斜向只用整格平移，不旋轉、不縮放（身體各列依高度往旁邊移、上半身下沉、近的手肩膀以下往外張並上下晃、兩隻腳各自平移，小部件整塊跟著錨點那一列移）；右邊方向由左邊翻轉，帽子另外畫在頭後面。步態（慢走、小跑）的數字與「第幾格是什麼姿勢」在 `Gait`，兩隻共用，照 `walk.py` 的 `walk_pose()`。
- **箱庭（等角）**：`World/Room/`。`RoomLayout` 是邏輯：地板格子、家具佔用的格子與高度、牆上的東西、擺放檢查，不管畫面。`IsoProjection` 把格子 (i, j) 與高度換算成像素（每格 32×16，2:1 斜率）。`RoomRenderer` 畫背景（牆、地板、窗戶）與每件家具的色塊盒子，並依「最靠近主人的角」排前後。找路與行為只用格子座標，換畫法時不受影響。
- **找路**（`RoomPath`，A1 第 6 項）：企鵝站在格子中心，沿格線（i、j 軸）一格一格走，家具佔的格子不能走。先找最短的路，一樣短時挑轉彎最少的（看起來有目標地走），再一樣時照固定順序挑，同樣的起訖每次走同一條。路徑拆成一段段直線，每段的方向對到斜向的一張圖：i 往前是右前、j 往前是左前、i 往後是左後、j 往後是右後。格子只有 144 格，用簡單的 Dijkstra（狀態含上一步的方向，才算得出轉彎）。
- **鏡頭與縮放**：`RoomCamera` 記畫面中央對著箱庭的哪一點（箱庭像素），限制在範圍內；`RoomZoom` 決定每個像素幾 pt（最大 3pt，最小房間左右塞滿畫面），兩者都是純數學、有單元測試。畫面左上角對齊螢幕實體像素（依 `displayScale`），畫面跟著手指走又不糊；所有東西放在同一個像素格子上，彼此仍對齊。捏合時連續縮放，放開後吸附到整數個實體像素，讓每個像素一樣大。
- **箱庭的即時狀態**：`RoomStage` 持有鏡頭、縮放，以及每隻企鵝的位置與正在播的動作；決定每一格要畫哪些圖（依「最靠近主人」排前後）、點到哪一隻（觸控範圍是整張企鵝圖，重疊時前面那隻優先）、要不要重畫。閒置後鏡頭回到所有企鵝的中點。純邏輯，時間由外面傳入，所以「閒置 5 秒後鏡頭回去」「哈囉播到第幾格」都能在測試裡用假時間驗證。手勢與意圖由 `RoomView`（SwiftUI）交給它。
- **Metal 繪圖**（`World/Render/`，[ADR 0006](adr/0006-metal-rendering.md)）：
  - `SpriteRenderer`：載入時把所有圖（背景、家具、企鵝每一格）送進 GPU，之後每一格照 `RoomStage` 的清單貼圖。貼圖存原始 RGBA，畫面標成 sRGB，顏色和調色盤一致；取最近的像素、不平滑。shader 在 `Sprites.metal`。
  - `GameLoop`（在 `MetalRoomView`）：用 `CADisplayLink` 跟著螢幕更新，最高到手機支援的更新率（120Hz 要 Info.plist 的 `CADisableMinimumFrameDurationOnPhone`，放在 `ios/Config/PenguinFamily-Info.plist`）。每一格問 `RoomStage` 有沒有變化，有才畫；沒東西在動時暫停省電，需要時（例如 5 秒後鏡頭回去）再醒來。
  - 畫面本身不會移動，鏡頭與縮放都在繪圖時處理，所以手勢座標就是畫面上的位置。
  - 建置需要 Metal Toolchain（Xcode 26 起另外下載，見 ADR 0006）。
  - **量測點**（`PerfSignposts`，常駐）：每一格、`RoomStage` 計算、畫、等畫布、送出指令、點擊處理都有 signpost，在 Instruments 的 Points of Interest 看。2026-11-16 iPhone 11 正式版 40 秒、1,069 格：一格中位 1.37 毫秒、最慢 5.84 毫秒（預算 16.7 毫秒）；最慢的是暫停後醒來的第一格，慢在等畫布（4 毫秒），所以閒置暫停值得保留。
- **播放**：哈囉以每秒 20 格播放，時間軸 `HelloMotion` 照私有素材 repo 的 `hello_pose()`，兩隻共用。`RoomStage` 照 `Behavior` 的意圖選動作，播完經 `GameLoop` 回報給 `Behavior`。
- **動作與預先算好的格子**（作者 2026-11-16 決定）：動作是資料（`Motion`：每秒幾格、共幾格、第幾格的姿勢），`Motion.all` 列出所有動作。載入角色時，`CharacterFrames` 把站好與每個動作的每一格都先合成好；播放時只取出來貼，拖曳重畫時也不重新合成。2026-11-16 在 Mac（M4 Pro）上量，一格合成約 0.09 毫秒、44×45 像素約 7.9KB；哈囉 56 格約 0.44MB。A1 全部動作都存起來的推估約 10MB 以內（假設兩隻、各約 10 個動作、每個約 60 格）。動作多到打開 App 明顯變慢時，再改成背景算或第一次播才算。跟著互動即時變化的姿勢（例如抱抱時壓扁）不預先算，直接用 `RigCompositor` 合成。`CharacterPackLibrary` 依資料夾名稱載入一家（兩隻）；角色包不夠或壞掉時，缺的那隻顯示灰色占位剪影。
- **取整要和 Python 相同**：Python 3 的 `round()` 遇到 .5 取最近的偶數，Swift 的 `rounded()` 預設遠離 0，所以 Swift 版明確用 `.toNearestOrEven`（2026-11-16 查證：[SE-0113](https://github.com/swiftlang/swift-evolution/blob/main/proposals/0113-rounding-functions-on-floatingpoint.md)、[Apple `rounded(_:)`](https://developer.apple.com/documentation/swift/double/rounded(_:))、[Python 文件討論](https://www.python.org/pipermail/docs/2013-February/012898.html)）。

## 測試

單元測試涵蓋行為狀態轉換、部件合成規則、事件紀錄、箱庭的邏輯與即時狀態；之後加入台詞選擇規則和 AI 失敗回退。

部件合成分兩層測（作者 2026-11-16 決定）：

- **合成規則**（`RigCompositorTests`）：用測試裡手寫的 10x10 假角色，永遠會跑。測靜止時和手算結果相同、跟著頭的部件只移動不轉、手超過角度換成舉手圖、.5 取偶數、格式錯誤會被拒絕。
- **和 Python 逐格相同**（`CharacterPackParityTests`）：私有素材 repo 的匯出程式把 `rig.json` 和每個動作的對照檔 `<動作>.golden.json` 寫到 `PenguinFamilyTests/CharacterPacks.bundle/<角色>/`（不進 git；跑測試時會跟著測試 bundle 放進 App 的 `PlugIns/`，一般建置的 App 不含，2026-11-16 實測 Release 建置）。測靜止時和定稿正面圖相同、動作每一格和 Python 相同，App 用的哈囉時間軸每一格的姿勢也和 Python 相同。斜向另有對照檔 `oblique.parity.json`：四個方向不動時和定稿圖相同，慢走、小跑在四個方向每一格的姿勢（Swift 的 `Gait` 算出來的）與畫面都和 `walk.py` 相同。沒有角色包時自動跳過。
- **斜向合成規則**（`ObliqueCompositorTests`）：用手寫的 8×10 假角色，永遠會跑。測傾斜、下沉、腳、張手與上下晃、翻轉與帽子只填空格、格式錯誤會被拒絕，以及步態的格數、速度與起始姿勢。
- **事件紀錄**（`EventLogTests`）：每個測試用自己的記憶體資料庫，不碰手機上的資料；也確認寫入不在主執行緒上做。
- **程式地圖**（`CodeMapTests`）：[程式地圖](code-map.md)列的檔案和實際的 `.swift` 檔一致（作者 2026-11-16 決定）。只檢查有沒有列，內容對不對靠人。測試在模擬器上讀 Mac 上的 repo，實機上跑不了。
- **顯示需要的部分**（`PenguinDisplayTests`）：哈囉時間軸頭尾都是站好、顏色轉換精確、找角色包（沒有、壞掉、只有部分能用）。
- **箱庭的即時狀態**（`RoomStageTests`）：要畫什麼與順序、點擊、拖曳、捏合、動作播放、閒置後鏡頭回去、有變化才重畫，都用假時間測。Metal 實際畫出來的樣子與手感不在單元測試裡，以模擬器截圖與實機確認。
