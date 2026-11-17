# 渲染效能：現在的做法與其他選擇

2026-11-16 評估。作者問：不以開發便利為主，有沒有渲染效能更好、更順的做法。

**結果**：作者看過評估後選 Metal，同一天改完（[ADR 0006](../adr/0006-metal-rendering.md)）。換完後模擬器截圖和 SwiftUI 版逐像素相同；實機效能還沒量。這份是 ADR 0006 的依據，下面第一節描述的是換之前的 SwiftUI 版。

## 換之前的做法（SwiftUI），每一格發生什麼

箱庭與企鵝都是 SwiftUI 的 view：一張背景圖、四件家具圖、一隻企鵝，用 `ZStack` 疊起來、`offset` 位移（見[程式地圖](../code-map.md)）。

- **拖曳、捏合時**：每次手指移動都改一次鏡頭狀態，SwiftUI 重新執行 `RoomView` 的 `body`、重新排前後、比對差異、排版，再交給系統去畫。這些都在主執行緒上。
- **播哈囉時**：`TimelineView` 每秒更新 20 次，換一張預先算好的圖。
- **GPU 的工作很少**：只是把幾張小圖貼上去。

Apple 把卡頓（hitch）分成兩種：App 自己來不及在期限內把畫面交出去（commit hitch），和系統的繪圖服務來不及畫（render hitch）。前者通常是主執行緒工作太多；view 的層級越深，打包交出去的時間越長（2026-11-16 查證：[Apple Tech Talk 10855](https://developer.apple.com/videos/play/tech-talks/10855)、[Tech Talk 10856](https://developer.apple.com/videos/play/tech-talks/10856)、[Understanding user interface responsiveness](https://developer.apple.com/documentation/xcode/understanding-user-interface-responsiveness)）。

**推論**：我們的風險在主執行緒（SwiftUI 每格比對與排版），不在 GPU。現在只有 6 個東西，問題應該不大；A1 後面會加第二隻、對話泡泡、發現的東西、日夜光線，數量還是幾十個以內。沒有實機數據，不能確定會不會卡。

## 其他做法

依「每一格主執行緒要做的事」由少到多排：

| 做法 | 每一格怎麼更新 | 優點 | 缺點與風險 |
|---|---|---|---|
| **Metal**（`MTKView`） | 自己寫繪圖：整個箱庭先畫在原始像素大小的小畫布上，再一次整數倍放大到螢幕 | 效能上限最高；所有東西保證對在同一個像素格子上（縮放中也是）；日夜光線、特效用 shader 做 | 工作量最大：要自己寫貼圖批次、點擊判斷、文字；Metal 是 Apple 的底層，長期最穩 |
| **SpriteKit**（`SpriteView`） | 改節點的位置與貼圖，引擎跟著螢幕更新的節奏跑遊戲迴圈 | 內建遊戲迴圈、鏡頭節點、動作、粒子；貼圖可設成不平滑（`filteringMode = .nearest`）| **前景不確定**：Apple 2026 年 5 月說「目前沒有 deprecated」，但不談未來；SceneKit 已在 2025 年軟性 deprecated。**iOS 26 有 SpriteKit 掉幀的回報**，Apple 2026 年 5 月說 bug 仍未解決 |
| **Core Animation**（`CALayer`） | 每個東西一個 layer；鏡頭只改一個父 layer 的位置；用 `CADisplayLink` 跟著螢幕更新 | 不用每格比對 view；Apple 長期支援的成熟技術；放大可設不平滑（`magnificationFilter = .nearest`）| 要自己處理點擊、關掉內建的隱式動畫；比 SwiftUI 囉嗦 |
| **SwiftUI `Canvas`** | 一個 view 自己畫全部 | 少了很多 view 的比對；仍在 SwiftUI 裡 | 每次有變化就整張重畫；個別東西不能掛手勢；社群回報 `drawingGroup()` 不一定有幫助 |
| **換之前：SwiftUI view** | 改狀態，SwiftUI 比對差異 | 寫起來最快；手勢、無障礙都內建 | 東西越多，每格比對越多 |

先前不選 SpriteKit 的理由是「在螢幕解析度旋轉部件，像素會錯位」（見[架構](../architecture.md)）。改成預先算好每一格之後，部件旋轉已經在原始像素大小上完成，SpriteKit 只負責貼圖，這個理由已經不成立（推論，未實測）。

## 換的話要改哪些

只有畫面那一層：`RoomView`、`PenguinView`、`LoadingView` 的畫法。下面這些都是純 Swift，可以原封不動沿用：`RoomLayout`、`IsoProjection`、`RoomCamera`、`RoomZoom`、`RoomRenderer`（產生的圖）、`Motion`、`CharacterFrames`、`Behavior`、`Memory`。

## SpriteKit 與自寫 Metal 怎麼選（2026-11-16 補充）

作者問：效能優先的前提下，SpriteKit 和自寫 Metal 哪個適合。

- **效能本身分不出高下（推論）。** 幾十張小圖，兩者的 GPU 工作都很少；真正的風險是 SwiftUI 每格比對，兩者都消掉了。比的是風險與適配度。
- **SpriteKit 的掉幀正好落在我們的核心互動。** iOS 26.0 的掉幀，Apple 說 26.2 修好了，但開發者回報 26.3 又出現、26.4 beta 還在；另有回報「最簡單的場景，摸著螢幕時 FPS 明顯下降」。拖曳、捏合、點企鵝都是摸著螢幕。
- **SpriteKit 內建的東西我們大多已自己做好，也寫了測試**：鏡頭、縮放、點擊判斷、前後排序、逐格動作、有變化才畫的遊戲迴圈，全在純 Swift 的 `RoomStage`。改用 SpriteKit 的話，這些不是重複，就是改用 `SKCameraNode`、`SKAction`，變得不好單獨測試。
- **Metal 的缺口是文字。** 對話泡泡（A1 第 16 項）要自己處理：用像素字型點陣圖，或把泡泡用 SwiftUI 疊在 Metal 上。SpriteKit 的 `SKLabelNode` 畫的是平滑的系統字型，也不像像素，所以兩邊都要另外決定。
- **iPhone 11 能不能升 iOS 27，二手來源互相矛盾**：2026 年 4～6 月的傳聞說會停止支援，之後又有報導說 iOS 26 能用的 iPhone 都能升。我沒有找到 Apple 的官方清單，要以作者手機上看到的版本為準。

來源：[Apple 論壇 800952](https://developer.apple.com/forums/thread/800952)（26.2 修正）、[815783](https://developer.apple.com/forums/thread/815783)（26.3 又出現）、[816719](https://developer.apple.com/forums/thread/816719)（26.4）、[821590](https://developer.apple.com/forums/thread/821590)（摸著螢幕時掉幀）；iPhone 11 與 iOS 27：[MacRumors 2026-06-04](https://macrumors.com/2026/06/04/ios-27-compatible-iphones-rumor/)（傳聞會停止支援）、[iGeeksBlog](https://www.igeeksblog.com/ios-27-supported-devices/)（說沒有停止支援）。

## 怎麼量

用 Instruments 的 Animation Hitches 範本在 iPhone 11 上量卡頓，Time Profiler 看主執行緒時間（[Tech Talk 10855](https://developer.apple.com/videos/play/tech-talks/10855)）。模擬器用的是 Mac 的 CPU 與 GPU，數字不能代表手機。

## 來源（2026-11-16 查證）

- SpriteKit 不平滑貼圖：[Apple：SKTexture.filteringMode](https://developer.apple.com/documentation/spritekit/sktexture/filteringmode)
- SpriteKit 的支援狀態：[Apple 論壇：SpriteKit's Continued Support](https://developer.apple.com/forums/thread/826562)（2026 年 5 月 DTS 回覆「SpriteKit is not deprecated at this time」，不談未來）
- SpriteKit 在 iOS 26 掉幀：[Apple 論壇 800952](https://developer.apple.com/forums/thread/800952)、[815783](https://developer.apple.com/forums/thread/815783)、[816719](https://developer.apple.com/forums/thread/816719)（2026 年 5 月 DTS 說 bug 仍開著；10 月只請大家在 iOS 27.2 beta 測）、[821590](https://developer.apple.com/forums/thread/821590)、[804973](https://developer.apple.com/forums/thread/804973)（SwiftUI 疊在 SpriteKit 上也會掉幀）
- SceneKit 軟性 deprecated：[Apple：Bringing your SceneKit projects to RealityKit](https://developer.apple.com/documentation/realitykit/bringing-your-scenekit-projects-to-realitykit)、[WWDC25 session 288](https://developer.apple.com/videos/play/wwdc2025/288/)
- Core Animation 不平滑放大：[Apple：CALayer.magnificationFilter](https://developer.apple.com/documentation/quartzcore/calayer/magnificationfilter)
- SwiftUI Canvas 的取捨：[WWDC21 Add rich graphics to your SwiftUI app 筆記](https://mackuba.eu/notes/wwdc21/add-rich-graphics-to-swiftui-app)、[Apple 論壇 663188](https://developer.apple.com/forums/thread/663188)
