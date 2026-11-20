# 程式地圖

寫給作者與 Claude：快速看懂 App 目前長什麼樣子。只列**已經存在**的程式；規劃中的架構與模組在最後兩節。

- **為什麼這樣切**（模組邊界、設計原則、向量做法）看[架構](architecture.md)；這份只回答「有什麼、在哪裡、怎麼串起來」。
- **每個檔案的細節**寫在檔案開頭的 `///` 註解，這裡一個檔案只寫一句，避免兩邊寫同樣的事、改了一邊忘了另一邊。
- **保持同步**：`CodeMapTests` 會檢查每個 `.swift` 檔都列在這份文件裡、這裡列的檔案都存在；新增、刪除或改名檔案時，測試失敗就是提醒你回來更新。內容寫得對不對，還是靠人（作者 2026-11-16 決定）。
- 圖用 [Mermaid](https://docs.github.com/en/get-started/writing-on-github/working-with-advanced-formatting/creating-diagrams)：在 GitHub 上會畫成圖；在終端機裡看到的是原始文字。

最後更新：2026-11-20（新增規劃中的三層架構：模擬、畫面準備、繪圖，ADR 0008 提案中）。

## 一句話看懂

App 分三層，像 Vue 的「props 往下、events 往上」：

- **`Behavior`** 決定企鵝「想做什麼」，輸出意圖（待機、哈囉、走去某一格、站著幾秒）；沒人碰時由閒晃照資料挑下一步。純 Swift，不碰畫面。
- **`World`** 把意圖畫出來，並把主人的手勢往上回報。只有這層碰畫面（SwiftUI 與 Metal）。
  - 畫面用 Metal 畫：`RoomStage` 決定每一格要畫什麼（純邏輯），`SpriteRenderer` 照清單把貼圖畫出來，`GameLoop` 跟著螢幕的節奏、有變化才畫。
- **`Memory`** 記下發生過的事，只存在手機上。
- **`GameView`** 是接線員：把三層接起來，本身幾乎沒有邏輯，像 Vue 的頁面元件。
- **`ContentView`** 先顯示載入畫面，在背景把角色準備好，再切到 `GameView`（見[架構的技術取捨](architecture.md#技術取捨)）。

## 檔案

### App 外殼

| 檔案 | 職責 |
|---|---|
| [PenguinFamilyApp.swift](../ios/PenguinFamily/PenguinFamilyApp.swift) | App 進入點：開事件紀錄的資料庫（打不開就改用暫存，企鵝照樣能用），放上 `ContentView`。 |
| [ContentView.swift](../ios/PenguinFamily/ContentView.swift) | 先顯示載入畫面，在背景做初始化（載入角色、打開事件紀錄、讀閒晃的資料），完成後淡入主遊戲。新增的初始化放在這裡的 `load()`。 |
| [LoadingView.swift](../ios/PenguinFamily/LoadingView.swift) | 載入畫面：和箱庭外面同一個底色，三個小方塊輪流亮。暫時的樣子。 |
| [GameView.swift](../ios/PenguinFamily/GameView.swift) | 主遊戲的接線員：一家每一隻各有身分、狀態機、閒晃與位置，決定誰在台上（一家兩隻）；主人點了哪一隻就交給那一隻，再把事件丟給事件紀錄在背景寫入；走到時記下新位置；台上的企鵝一回到待機，就問牠的閒晃下一步，並告訴閒晃別隻在哪一格。 |

### World：畫面

| 檔案 | 職責 |
|---|---|
| [CharacterPackLibrary.swift](../ios/PenguinFamily/World/CharacterPackLibrary.swift) | 列出 App 裡的角色包（有 `vector.json` 的資料夾），照 `family.json` 的順序載入一家兩隻（最前面的是第一隻；沒有清單或沒列到的依名稱排）；每隻另外讀自己的 `motion.json`、`wander.json`（沒帶或壞掉就用預設）。造型壞掉的跳過，不夠的位置留給替身或灰色剪影。不寫死角色 id。 |
| [PenguinID.swift](../ios/PenguinFamily/World/PenguinID.swift) | 一隻企鵝的身分：角色包 id，沒有角色包的是 `placeholder-<第幾隻>`。舞台、點擊、動作播完、事件紀錄都用它認是哪一隻。 |
| [RGBColor.swift](../ios/PenguinFamily/World/RGBColor.swift) | 不透明的 sRGB 顏色，解析 `#RRGGBB`；角色包的顏色層、箱庭的色塊都用它。 |

**`World/Motion/`：企鵝怎麼動（算式兩隻共用，數字每隻各一份）**

| 檔案 | 職責 |
|---|---|
| [Motion.swift](../ios/PenguinFamily/World/Motion/Motion.swift) | 正面的姿勢 `RigPose`（頭、手幾度、身體壓扁多少），與正面動作的格式：播多久、第幾秒是什麼姿勢。 |
| [PenguinMotions.swift](../ios/PenguinFamily/World/Motion/PenguinMotions.swift) | 一隻企鵝各狀態的動作細節（角色包的 `motion.json`）：哈囉、慢走、小跑的數字，讀檔與檢查；作者定案的那一份（`standard`）給沒有角色包的那隻；意圖要播哪個動作、走路用哪個步態。 |
| [HelloMotion.swift](../ios/PenguinFamily/World/Motion/HelloMotion.swift) | 哈囉的數字與時間軸：舉手、揮、放下、站好各幾秒，第幾秒時頭、手各轉幾度、身體壓扁多少。 |
| [Gait.swift](../ios/PenguinFamily/World/Motion/Gait.swift) | 面向（正面與斜向四個方向）；一種步態的數字、速度，與第幾秒的斜向姿勢 `VectorWalkPose`；作者定案的慢走、小跑。 |

**`World/Vector/`：企鵝的造型（ADR 0007）**

| 檔案 | 職責 |
|---|---|
| [VectorRig.swift](../ios/PenguinFamily/World/Vector/VectorRig.swift) | `vector.json` 的資料格式與檢查（部件的形狀、轉軸、顏色層、外框；斜向的走法；右邊翻轉左邊）；`Affine2D` 矩陣；某一格的樣子 `VectorPose`（正面的姿勢，或斜向的方向與走路的姿勢）換成每個部件的矩陣。算式和私有素材 repo 的 `vector.js` 逐格相同。 |
| [VectorRasterizer.swift](../ios/PenguinFamily/World/Vector/VectorRasterizer.swift) | 載入時用 Core Graphics 把每個畫好的方向的每個部件畫成兩張貼圖（外框、顏色），解析度照抱抱近景的倍率準備（螢幕倍率最多算到 2）；裁切每一組取聯集、組與組取交集；不用畫就能算出貼圖佔多少記憶體。 |
| [PlaceholderRig.swift](../ios/PenguinFamily/World/Vector/PlaceholderRig.swift) | 沒有角色包時的造型：替身（`graySilhouette()`，借別隻的形狀整隻塗灰，會斜著走）；一家都沒有角色包時的灰色剪影（`VectorRig.placeholder`：只有正面，手藏在身體裡，哈囉時轉出來揮）。 |

**`World/Room/`：箱庭怎麼畫**

| 檔案 | 職責 |
|---|---|
| [RoomPath.swift](../ios/PenguinFamily/World/Room/RoomPath.swift) | 找路：哪些格子站得上去、沿格線一格一格走、繞過家具（需要時也避開別隻站的格子）；先挑最短、再挑轉彎最少，拆成一段段直線（每段對到斜向的一張圖）。閒晃用的：走到每一格要幾步、家具與窗戶旁邊站哪一格、某一格（別隻）四周站哪一格、面向哪裡（`RoomSpot`）。 |
| [RoomLayout.swift](../ios/PenguinFamily/World/Room/RoomLayout.swift) | 房間的邏輯：幾格大、家具佔哪些格與多高、牆上有什麼、擺放檢查。也包含 `IsoProjection`：格子座標換算成等角的位置（單位，不取整數）。 |
| [RoomRenderer.swift](../ios/PenguinFamily/World/Room/RoomRenderer.swift) | 把牆、地板、窗戶與家具的色塊盒子做成凸多邊形（家具外面一圈外框）；決定誰畫在前面。 |
| [RoomCamera.swift](../ios/PenguinFamily/World/Room/RoomCamera.swift) | 鏡頭的數學：畫面中央對著哪一點、不超出房間、慢慢靠近目標。 |
| [RoomZoom.swift](../ios/PenguinFamily/World/Room/RoomZoom.swift) | 縮放的數學：最大 3pt、最小房間左右塞滿畫面、放開後停在那個倍率、手指下那一點不動。 |
| [RoomStage.swift](../ios/PenguinFamily/World/Room/RoomStage.swift) | 箱庭的即時狀態：後台名單與台上的企鵝（`add`、`remove`）、鏡頭、縮放、每隻的位置、面向與動作；走路（找路、照步態速度沿路走、位置每一格都前進、走到回報）；站著（轉向、站滿回報；畫面不動時讓遊戲迴圈暫停，站滿再醒來）；同樣的意圖再要一次時看編號重新開始；走路被打斷時停在兩格之間，再走時從那裡沿格線接著走；企鵝每一格照當下的方向與姿勢；兩隻互相讓路（下一格被佔住就停下來等，等不到再繞路，繞不過去就放棄）；沒有角色包的那隻換成替身；每一格要畫哪些東西（箱庭的多邊形、企鵝）（企鵝在家具旁邊時依格子關係排前後）、點到哪一隻、要不要重畫、閒置後鏡頭回到第一隻。純邏輯。 |
| [RoomView.swift](../ios/PenguinFamily/World/Room/RoomView.swift) | 放上 Metal 畫面，把點擊、拖曳、捏合、意圖（含編號）與「誰在台上」交給 `RoomStage`；舞台在第一次出現時才建，之後沿用。 |

**`World/Render/`：用 Metal 畫出來**

| 檔案 | 職責 |
|---|---|
| [MetalRoomView.swift](../ios/PenguinFamily/World/Render/MetalRoomView.swift) | 把 Metal 畫面放進 SwiftUI；`GameLoop` 跟著螢幕更新（最高到手機支援的更新率），有變化才畫，沒事時暫停；把動作播完、走到回報出去。 |
| [SpriteRenderer.swift](../ios/PenguinFamily/World/Render/SpriteRenderer.swift) | 載入時把箱庭的多邊形切成三角形、企鵝的部件畫成貼圖（含 mipmap）；每一格照 `RoomStage` 的清單畫：多邊形、企鵝（先畫整隻的外框再畫顏色，部件依姿勢轉動；右前、右後翻轉左邊的貼圖）。4 倍多重取樣抗鋸齒。shader 在同資料夾的 `Sprites.metal`。 |
| [PerfSignposts.swift](../ios/PenguinFamily/World/Render/PerfSignposts.swift) | 量效能用的標記（signpost）：遊戲迴圈每一格、算、畫、等畫布、點擊各花多久，在 Instruments 的 Points of Interest 看。 |

### Behavior：企鵝想做什麼

| 檔案 | 職責 |
|---|---|
| [PenguinBehavior.swift](../ios/PenguinFamily/Behavior/PenguinBehavior.swift) | 狀態機：待機 →（被點）→ 哈囉 →（播完）→ 待機；待機 →（要牠走去某一格）→ 走路 →（走到）→ 待機；待機 →（要牠站幾秒）→ 站著 →（站滿）→ 待機，站著時被點就哈囉；走路中被點當場停下哈囉，記下那段路，播完接著走。哈囉中再點會被忽略。意圖每換一次編號加一。只輸出意圖，不管動畫播多久、怎麼走過去。 |
| [WanderConfig.swift](../ios/PenguinFamily/Behavior/WanderConfig.swift) | 閒晃的資料格式與檢查（每種活動的權重、冷卻、待多久；慢走與小跑的比例；走幾步停一下；東張西望看哪些方向），讀 App 裡的預設 `wander.json`（每隻自己的在角色包裡）。 |
| [WanderRoutine.swift](../ios/PenguinFamily/Behavior/WanderRoutine.swift) | 閒晃：依權重挑活動、冷卻中的先不挑，拆成「走去某一格」「站著幾秒」一步步交給狀態機（走到家具旁邊面向它、隨便走走、發呆、東張西望、走去黏著另一隻，路長時走幾步停一下）；別隻的格子不當目的地。亂數、時間與別隻在哪由外面給。 |

### Memory：發生過什麼

| 檔案 | 職責 |
|---|---|
| [EventRecord.swift](../ios/PenguinFamily/Memory/EventRecord.swift) | 一筆事件的資料格式：什麼時候、什麼事、哪一隻。事件種類存字串，之後新增種類不用搬資料。 |
| [EventLog.swift](../ios/PenguinFamily/Memory/EventLog.swift) | 在背景寫入的事件紀錄（`ModelActor`）：開資料庫（關閉 iCloud 同步）、預熱、寫入事件、讀最近幾筆。一律用 `open(_:)` 在背景建立。 |

### 資源

- `Resources/wander.json`（進 git）：預設的閒晃資料，給沒有角色包、或角色包沒帶自己閒晃資料的那隻；格式寫在 `WanderConfig` 的開頭。
- `Resources/CharacterPacks.bundle/`（不進 git，由私有素材 repo 匯出）：`family.json`（一家的順序）與每隻一個資料夾 `<角色>/`，裡面是 `vector.json`（造型）、`motion.json`（動作細節）、`wander.json`（閒晃）。乾淨 clone 下來沒有，App 會顯示灰色剪影、用預設的動作與閒晃。

### 測試

| 檔案 | 測什麼 |
|---|---|
| [VectorPackParityTests.swift](../ios/PenguinFamilyTests/VectorPackParityTests.swift) | 拿真實角色包比對：照那隻自己的 `motion.json`，哈囉每一格、斜向四個方向每個步態抽樣的姿勢與每個部件的矩陣和 `vector.js` 相同；沒有角色包時自動跳過。 |
| [PenguinDisplayTests.swift](../ios/PenguinFamilyTests/PenguinDisplayTests.swift) | 哈囉時間軸、動作細節的讀檔與檢查、顏色、找角色包、載入一家（照 `family.json` 的順序；每隻帶自己的動作細節與閒晃，沒帶或壞掉用預設）、灰色剪影（只有正面、手藏在身體裡）。 |
| [PenguinBehaviorTests.swift](../ios/PenguinFamilyTests/PenguinBehaviorTests.swift) | 狀態機的轉換（含走路中被點：哈囉完接著走）、意圖的編號。 |
| [WanderTests.swift](../ios/PenguinFamilyTests/WanderTests.swift) | 閒晃：預設與每個角色包的 `wander.json` 讀得進來、不合理的數字擋下來；依權重挑、冷卻、走去家具旁邊面向它、隨便走走的距離、走幾步停一下、東張西望不連續看同一邊、發呆的方向、走去黏著另一隻、別隻的格子不當目的地也不在那裡停。用固定種子的亂數。 |
| [EventLogTests.swift](../ios/PenguinFamilyTests/EventLogTests.swift) | 事件紀錄，每個測試用自己的記憶體資料庫；寫入不在主執行緒。 |
| [RoomTests.swift](../ios/PenguinFamilyTests/RoomTests.swift) | 房間擺放檢查、等角換算、背景與家具的多邊形（凸的、外框往外推）、前後順序、灰色剪影站在腳底上。 |
| [VectorRigTests.swift](../ios/PenguinFamilyTests/VectorRigTests.swift) | 向量角色包的讀檔與檢查、正面的姿勢連動（轉軸不動、壓扁時腳底不動）、斜向（站著不動、上半身以腳底傾斜、手往外張、翻轉以腳底為軸、步態每一格只差一點點）、部件畫成貼圖的顏色、外框與裁切、替身（形狀不變、整隻塗灰）、角色包一起載入，用手寫的 20×20 假角色，永遠會跑。 |
| [VectorMemoryBudgetTests.swift](../ios/PenguinFamilyTests/VectorMemoryBudgetTests.swift) | 記憶體預算：一家的向量貼圖（缺角色包的話，那隻算替身）在螢幕 3 倍的手機上（含 mipmap）不能超過 50MB，用真實角色包算；超過就失敗，先和作者討論怎麼省。沒有角色包時自動跳過。貼圖最多照 2 倍準備。 |
| [RoomPathTests.swift](../ios/PenguinFamilyTests/RoomPathTests.swift) | 站得上去的格子、每一段的方向、直線、轉彎最少、繞過沙發、每次同一條路、到不了的情況、屋內每塊地板都走得到、避開別隻的格子；幾步遠和找路相同、家具與窗戶旁邊站哪裡、別隻四周站哪裡。 |
| [RoomCameraTests.swift](../ios/PenguinFamilyTests/RoomCameraTests.swift) | 鏡頭範圍、左上角不對齊像素、慢慢靠近。 |
| [RoomZoomTests.swift](../ios/PenguinFamilyTests/RoomZoomTests.swift) | 縮放範圍、不吸附、手指下那一點不動。 |
| [RoomStageTests.swift](../ios/PenguinFamilyTests/RoomStageTests.swift) | 要畫什麼與順序、點到哪一隻（重疊時前面優先）、拖曳、捏合、各自的動作、閒置後鏡頭回到第一隻、有變化才重畫、上台與下台、一開始兩隻都在台上、每隻照自己的動作細節動（哈囉長短、走路快慢）、缺角色包的那隻用替身、兩隻互相讓路（繞開、先等再繞路、放棄、迎面走過、照 `GameView` 的接線一起閒晃 5 分鐘不疊在一起）、重新建立 `RoomView` 不會重建舞台、走路（姿勢每一格照時間算）、站著（轉向、站滿回報、不讓遊戲迴圈一直跑、被哈囉打斷、同樣的意圖看編號重新開始）、走路被打斷（停在原地、接著走不跳、回頭比較近時回頭、到不了停在比較近的一格）、企鵝在家具旁邊時的前後、正面的動作每一格照時間轉、沒有斜向的造型（灰色剪影）走路時面向鏡頭。 |
| [CodeMapTests.swift](../ios/PenguinFamilyTests/CodeMapTests.swift) | 這份文件和實際檔案一致。 |

Metal 實際畫出來的樣子與手感不在單元測試裡，用模擬器截圖與實機確認。

## 誰用誰

箭頭是「用到」。`Behavior` 與 `Memory` 不用到任何畫面的東西，所以可以單獨測試。

```mermaid
flowchart TD
    App["PenguinFamilyApp"] --> Content["ContentView（載入 → 主遊戲）"]
    Content --> Loading["LoadingView"]
    Content --> Library["CharacterPackLibrary"]
    Content --> Game["GameView（接線員）"]
    Content --> WConfig
    Game --> Room["RoomView"]
    Game --> Behavior["PenguinBehavior"]
    Game --> Wander["WanderRoutine"]
    Game --> Log["EventLog"]
    Game --> ID

    subgraph World["World：畫面"]
        Library --> VRig["VectorRig"]
        Room --> Metal["MetalRoomView（GameLoop）"]
        Room --> Stage["RoomStage"]
        Metal --> Renderer["SpriteRenderer"]
        Metal --> Stage
        Renderer --> Stage
        Renderer --> Raster["VectorRasterizer"]
        Renderer --> VRig
        Raster --> VRig
        Stage --> VRig
        Stage --> Placeholder["VectorRig.placeholder"]
        Stage --> Motions["PenguinMotions（每隻一份）"]
        Motions --> Motion["Motion"]
        Motions --> Gait["Gait"]
        Stage --> RoomRenderer["RoomRenderer"]
        Stage --> Camera["RoomCamera"]
        Stage --> Zoom["RoomZoom"]
        Stage --> Layout["RoomLayout"]
        Stage --> Path["RoomPath"]
        Path --> Layout
        Stage --> ID["PenguinID"]
        RoomRenderer --> Layout
        RoomRenderer --> Color["RGBColor"]
        VRig --> Color
        VRig --> Gait
        Placeholder --> VRig
        Motions --> Hello["HelloMotion"]
    end

    subgraph BehaviorLayer["Behavior：想做什麼"]
        Wander --> WConfig["WanderConfig（每隻的 wander.json）"]
        Wander --> Behavior
    end

    subgraph Memory["Memory：只存手機"]
        Log --> Record["EventRecord"]
    end

    Room -. "只讀意圖的型別" .-> Behavior
    Stage -. "只讀意圖的型別" .-> Behavior
    Wander -. "幾步遠、家具旁邊站哪裡" .-> Path
```

## 執行流程

只挑幾個代表情境；新增的功能如果走的是同一條路，就不另外畫。

### 打開 App

```mermaid
sequenceDiagram
    participant App as PenguinFamilyApp
    participant Log as EventLog
    participant CV as ContentView
    participant LV as LoadingView
    participant Lib as CharacterPackLibrary
    participant GV as GameView
    participant RV as RoomView

    App->>Log: 開資料庫
    Note over App,Log: 打不開就改用暫存，這次的事件不會留下
    App->>CV: 顯示
    CV->>LV: 馬上顯示載入畫面
    CV->>Lib: 在背景載入一家（兩隻）
    Note over Lib: 照 family.json 排順序，讀每一隻的 vector.json、motion.json、wander.json 並檢查內容
    Lib-->>CV: 每一隻的角色，缺的是 nil（舞台換成替身或灰色剪影）
    CV->>CV: 讀預設的閒晃資料 wander.json（給沒帶自己閒晃資料的那隻；讀不到就只站著）
    CV->>GV: 淡入主遊戲
    GV->>RV: 房間、後台名單（一家每一隻的造型與動作細節）、台上的企鵝（位置、意圖）
    Note over RV: 第一次出現時建立 RoomStage（之後沿用）、讓台上的企鵝上台；Metal 畫面出現時把後台每一隻的部件畫成貼圖送進 GPU
    RV->>RV: 鏡頭對準第一隻，每個單位 3pt
    Note over GV: 台上的企鵝開始閒晃（見「沒人碰時：閒晃」）
```

### 主人點一下企鵝

```mermaid
sequenceDiagram
    actor Owner as 主人
    participant RV as RoomView
    participant St as RoomStage
    participant GV as GameView
    participant Log as EventLog
    participant B as PenguinBehavior
    participant Loop as GameLoop

    Owner->>RV: 點一下
    RV->>St: 點到哪一隻？
    St-->>RV: 這一隻的 PenguinID（並重設閒置計時）
    RV->>GV: 這一隻被點了
    GV->>Log: 記下「主人點了這隻」
    GV->>B: 這一隻的狀態機收到「被點」
    B-->>GV: 意圖變成「哈囉」
    GV->>RV: 意圖：哈囉
    RV->>St: 開始播哈囉
    St->>Loop: 有變化，醒來
    loop 每一格（跟著螢幕更新）
        Loop->>St: 現在第幾秒？要重畫嗎？
        Loop->>Loop: 有變才畫（哈囉播放中每一格照時間轉動部件）
    end
    St-->>Loop: 播完了
    Loop->>GV: 播完了（經過 RoomView）
    GV->>B: 收到「播完」
    B-->>GV: 意圖回到「待機」（走路被打斷的話，接著走那段路）
    Note over GV: 回到待機就問閒晃下一步（見下一節）
```

### 沒人碰時：閒晃

企鵝一回到待機（打開 App、走到、站滿、哈囉播完），`GameView` 就問牠的閒晃下一步。站著時畫面不動，遊戲迴圈暫停到站滿再醒來。

```mermaid
sequenceDiagram
    participant GV as GameView
    participant W as WanderRoutine
    participant B as PenguinBehavior
    participant St as RoomStage
    participant Loop as GameLoop

    GV->>W: 下一步？（站在哪一格、別隻在哪一格、現在幾秒）
    Note over W: 這次活動的步驟用完了：依權重挑一種（冷卻中的先不挑），<br/>例如「走去窗邊」：走過去（路長時走幾步停一下）→ 面向窗戶站 8～15 秒
    W-->>GV: 走去 (7, 0)，慢走
    GV->>B: 要牠走去 (7, 0)
    B-->>GV: 意圖：走路（編號加一）
    GV->>St: 意圖：走路（經過 RoomView）
    loop 每一格
        Loop->>St: 沿路走
    end
    St-->>GV: 走到了（經過 GameLoop、RoomView）
    GV->>B: 走到 → 待機
    GV->>W: 下一步？
    W-->>GV: 面向右後（窗戶）站 10 秒
    GV->>B: 要牠站 10 秒
    GV->>St: 意圖：站著
    St->>St: 轉向右後
    Note over Loop: 畫面不動，暫停，約定 10 秒後醒來
    St-->>GV: 站滿了
    GV->>B: 播完 → 待機
    GV->>W: 下一步？（這次活動做完了，挑新的）
```

主人在牠站著時點牠，狀態機改成哈囉；哈囉播完回到待機，閒晃接著做剩下的步驟。走路中點牠，舞台停在當下的位置（可能在兩格之間）、轉正面哈囉；播完狀態機接回同一段路，舞台從停的地方接著走，走到後閒晃再接著做。

### 拖曳與捏合

都在 `RoomStage` 裡處理，不經過 `Behavior` 與 `Memory`。

```mermaid
sequenceDiagram
    actor Owner as 主人
    participant RV as RoomView
    participant St as RoomStage
    participant Loop as GameLoop

    Owner->>RV: 拖曳空地或雙指捏合
    RV->>St: 這一下移了多少、放大多少
    St->>St: 用 RoomCamera、RoomZoom 算新的鏡頭與縮放
    St->>Loop: 有變化，醒來重畫
    Owner->>RV: 放開
    RV->>St: 放開（縮放停在那個倍率）
    Note over Loop: 沒有東西在動，暫停，約定 5 秒後醒來
    loop 5 秒沒碰之後，每一格
        Loop->>St: 往第一隻靠近一步
    end
```

## 遊戲設計對到哪些程式

| [遊戲設計](product/game-design.md)的章節 | 程式 | 已做 | 還沒做 |
|---|---|---|---|
| 呈現（平面向量、等角） | `World/Vector`、`World/Motion`、`World/Room`、`World/Render` | 正面與哈囉、斜向四個方向、慢走與小跑、屋內箱庭、縮放、Metal 繪圖 | 其他動作（打瞌睡、被拎著等） |
| 箱庭 | `World/Room` | 四件色塊家具、鏡頭、找路（沿格線、繞過家具） | 庭院 |
| 手勢 | `RoomView`、`RoomStage` | 點一下（站著、走路中都會哈囉）、拖曳空地、捏合 | 拎起來、抱抱 |
| 行為與一天的節奏 | `Behavior` | 待機、哈囉、閒晃（走向家具與窗邊、隨便走走、發呆、東張西望、走去黏著另一隻、走幾步停一下；權重與冷卻在每隻的 `wander.json`） | 睡覺、依權重反應、日夜 |
| 兩隻 | `RoomStage`、`GameView` | 一家兩隻各有身分、狀態機與事件紀錄，都在台上閒晃；互相讓路；第二隻的角色包先沿用第一隻的形狀（缺角色包時是借另一隻形狀塗灰的替身）；鏡頭優先看第一隻（`family.json` 排第一的） | 第二隻照牠的樣子改造型、第二隻的個性、看向對方、一起行動、鬥嘴 |
| 不在時的痕跡 | `Memory` | 記下點擊 | 補算小事、回來看得到 |
| 台詞 | `Soul`（未建立） | － | 全部 |
| 觸覺 | `Feel`（未建立） | － | 全部 |

## 規劃中：模擬、畫面準備、繪圖三層（ADR 0008，提案中）

**提案中，程式還沒改。** 決定與理由見 [ADR 0008](adr/0008-simulation-frame-render-layers.md)，業界做法與來源見[調查](research/simulation-architecture.md)。定案並重構後，這一區取代上面的「誰用誰」與「執行流程」。

### 核心規則

- **世界狀態（world state）只有模擬執行緒（simulation thread）能讀寫。** 狀態機、閒晃、位置、讓路都在這裡。
- **模擬以固定節拍（fixed tick）推進，每秒 30 次。** 模擬的時間等於節拍數；不讀系統時鐘，也不知道螢幕更新率。
- **跨執行緒只傳不可變的值。** 事件（event）進模擬；快照（snapshot）與輸出事件（output event）出模擬。交接點用 `Mutex`。
- **主執行緒每次螢幕更新只做兩件事：** 畫面準備（frame preparation）與 render。它從不等模擬。
- **render 只照繪製清單（draw list）下 GPU 指令。** 不算姿勢、不排序、不碰狀態機。

### 現在與提案：每次螢幕更新時誰在跑

```mermaid
flowchart LR
    subgraph Now["現在（v0.0.7）：全部在主執行緒的同一次呼叫"]
        direction TB
        N1["CADisplayLink<br/>每次螢幕更新"] --> N2["RoomStage.update<br/>走路、讓路、姿勢"]
        N2 -- "播完、走到" --> N3["GameView<br/>狀態機、閒晃挑下一步"]
        N3 -- "跑完才畫" --> N4["SpriteRenderer.draw"]
        N4 -. "畫的時候直接讀" .-> N2
    end
    subgraph Next["提案：模擬有自己的執行緒"]
        direction TB
        S1["模擬執行緒<br/>每 33 ms 一個節拍<br/>狀態機、閒晃、找路"] -- "每個節拍發布" --> B[("快照緩衝<br/>最近兩份")]
        M1["主執行緒 CADisplayLink<br/>每次螢幕更新"] -- "讀取，不等待" --> B
        M1 --> M2["畫面準備<br/>內插、姿勢、鏡頭、排序"]
        M2 -- "繪製清單" --> M3["render<br/>只下 GPU 指令"]
    end
```

- **現在**：狀態機轉換、閒晃的決定都在畫圖之前跑完；它們花多久，這一格就晚多久。render 也直接讀存著狀態的 `RoomStage`。
- **提案**：狀態機在另一條執行緒，主執行緒只讀最新的快照。模擬一時變慢，畫面照最新快照照常畫，不會掉格。

### 資料怎麼流

```mermaid
flowchart LR
    Ext["AI 回覆、計時器、步數"]
    subgraph Main["主執行緒"]
        direction TB
        Gesture["手勢（SwiftUI）"]
        Hit["點擊判斷<br/>用上一份繪製清單"]
        Camera["鏡頭、縮放<br/>呈現狀態"]
        Prep["畫面準備<br/>內插、姿勢、排序"]
        Render["render（Metal）"]
        UI["SwiftUI 介面<br/>對話泡泡、選單"]
    end
    subgraph Sim["模擬執行緒"]
        direction TB
        Queue[["事件佇列"]]
        Tick["節拍（每秒 30 次）"]
        World[("世界狀態<br/>狀態機、閒晃、位置、讓路")]
    end
    Snap[("快照 ×2<br/>Mutex 交接")]
    Log["事件紀錄<br/>背景寫入"]

    Gesture -- "點一下" --> Hit
    Gesture -- "拖曳、捏合" --> Camera
    Hit -- "被點事件" --> Queue
    Ext -- "事件" --> Queue
    Queue -- "節拍開頭依序取出" --> Tick
    Tick -- "讀寫" --> World
    Tick -- "每個節拍發布" --> Snap
    Snap -- "讀最近兩份" --> Prep
    Camera --> Prep
    Prep -- "繪製清單" --> Render
    Prep -. "保留上一份" .-> Hit
    Tick -- "輸出事件" --> Log
    Tick -- "輸出事件，轉回主執行緒" --> UI
```

| 資料 | 誰寫 | 誰讀 | 在哪裡 |
|---|---|---|---|
| 世界狀態 | 模擬 | 模擬 | 模擬執行緒 |
| 事件佇列 | 主執行緒（手勢）、背景工作（AI、計時器） | 模擬 | 交接點（`Mutex`） |
| 快照（最近兩份） | 模擬 | 畫面準備 | 交接點（`Mutex`） |
| 輸出事件 | 模擬 | 事件紀錄、SwiftUI 介面 | 轉回主執行緒；事件紀錄照舊在背景寫入 |
| 呈現狀態（鏡頭、縮放、進行中的手勢） | 畫面準備 | 畫面準備、點擊判斷 | 主執行緒 |
| 繪製清單 | 畫面準備 | render、點擊判斷 | 主執行緒 |

### 時間軸：主人點一下

```mermaid
sequenceDiagram
    actor Owner as 主人
    participant Main as 主執行緒（畫面準備與 render）
    participant Q as 事件佇列
    participant Sim as 模擬執行緒
    participant Snap as 快照緩衝

    Owner->>Main: 點一下
    Main->>Main: 點擊判斷（上一份繪製清單）
    Main->>Q: 被點（PenguinID）
    Note over Sim: 最多等 1 個節拍（33 ms）
    Sim->>Q: 節拍開頭取出事件
    Sim->>Sim: 狀態機：待機 → 哈囉
    Sim->>Snap: 發布快照 N（哈囉從節拍 N 開始）
    loop 每次螢幕更新（8.3～16.7 ms）
        Main->>Snap: 讀快照 N-1 與 N
        Main->>Main: 內插、算姿勢 → 繪製清單 → render
    end
    Note over Main: 畫面落後模擬 1 個節拍<br/>點下去到看到哈囉約 33～67 ms
```

**內插（interpolation）**：主執行緒畫的時間點，是「現在減一個節拍」，落在快照 N-1 與 N 之間，依比例算位置與姿勢。所以模擬每秒只跑 30 次，120Hz 的螢幕仍然每格都有新畫面。代價是畫面固定落後一個節拍。

### 沒事時誰在睡

| 情況 | 模擬執行緒 | 主執行緒 |
|---|---|---|
| 有企鵝在走、在播動作 | 每 33 ms 跑一個節拍 | 每次螢幕更新都準備、都畫 |
| 都站著、沒人碰 | 睡到下一個排定的時間（例如站滿）或有事件進來 | `CADisplayLink` 暫停（ADR 0006） |
| 拖曳、捏合 | 不受影響 | 每次螢幕更新都畫（只有鏡頭在動） |
| 模擬變慢 | 追節拍，每次追的數量有上限 | 照最新快照照常畫，不等 |

### 現在的程式會放到哪一層

| 現在 | 提案後 |
|---|---|
| `PenguinBehavior`、`WanderRoutine`、`WanderConfig` | 模擬（照用） |
| `RoomPath`、`RoomLayout` | 模擬（找路、格子）；畫面準備也會讀 `RoomLayout` |
| `RoomStage` 裡的走路、讓路、站滿、走到 | 模擬 |
| `RoomStage` 裡的鏡頭、縮放、前後排序、點擊判斷；`RoomCamera`、`RoomZoom`、`RoomRenderer` 的前後順序 | 畫面準備 |
| `Motion`、`HelloMotion`、`Gait`、`PenguinMotions` | 動作多長給模擬（判斷播完）；第幾秒是什麼姿勢給畫面準備 |
| `VectorRig.frame(_:)`（姿勢換成每個部件的矩陣） | 畫面準備（現在是 render 在畫的時候算） |
| `VectorRasterizer`、多邊形切三角形 | 不變：載入時準備好的 GPU 資源 |
| `SpriteRenderer` | render：只吃繪製清單 |
| `GameLoop`（在 `MetalRoomView` 裡） | 主執行緒的驅動：畫面準備加 render，有變化才畫 |
| `GameView` | 只剩外殼：放畫面、接 SwiftUI 介面 |
| `EventLog` | 接模擬的輸出事件 |
| 還沒有 | 模擬執行緒的驅動、事件佇列、快照交接（名稱與計時方式在重構時定） |

## 規劃中、還沒建立

位置與分工見[架構](architecture.md)的目錄圖。

- `Soul/`：角色聖經、台詞選擇、`DialogueEngine`（A1 第 19 項）。
- `Feel/`：觸覺與音效（A1 第 16 項）。
- `Activity/`、`PenguinFamilyWidget/`：步數與小工具（A3）。
- `backend/`：聊天的薄後端（B1）。
