# 狀態與繪圖的分工：模擬、畫面準備、繪圖

2026-11-20 評估。作者問：之後角色會變多，每隻的狀態機各自非同步地變化（隨機事件、日夜、AI 回覆、不在時補算）。狀態與繪圖要怎麼分工，才不會一直擠在同一格裡？趁程式還小，先定下長期的做法，不拿目前量到的數字當延後的理由（[issue #9](https://github.com/CBHeng/penguin-family/issues/9)）。

**結果**：作者 2026-11-20 選了方向：兩隻企鵝的狀態機在資料上、時間上都不參與 render，所以模擬一開始就放在自己的執行緒；模擬用固定節拍每秒 30 次，畫面內插。寫成 [ADR 0008](../adr/0008-simulation-frame-render-layers.md)；v0.0.8 照這個方向改完，作者同日實機驗收後定案。

## 現在每一格發生什麼（v0.0.7）

- **全部在主執行緒**：專案設定 `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`，遊戲迴圈的 `CADisplayLink` 也掛在主執行緒，手勢、SwiftUI、遊戲迴圈輪流執行，不會同時改同一份資料。
- **一格的順序**（`GameLoop.tick`，跟著螢幕更新）：
  1. `RoomStage.update(now:)` 照經過的時間推進姿勢、走路、讓路與鏡頭。
  2. 把「播完」「走到」回報給 `GameView`。
  3. 有變化才讓 `SpriteRenderer` 畫，它直接讀 `RoomStage.sprites()`。
  4. 沒有東西在動就暫停。
- **GPU 拿到的是副本**：CPU 準備畫圖時把數字複製給 GPU，`commit` 之後 GPU 自己畫，不會回頭讀舞台。
- **狀態散在三個地方**：
  - 狀態機與閒晃放在 `GameView` 的 SwiftUI `@State`。舞台回報的事件要經過 SwiftUI 重算 `body`，再由 `RoomView` 的 `onChange` 交回舞台，通常下一格才生效。意圖的編號（`serial`）就是為了 SwiftUI 合併更新才加的。
  - `RoomStage` 同時做遊戲邏輯（走路、讓路、站滿）與畫面的事（鏡頭、縮放、前後排序、點擊判斷）。
  - 繪圖直接讀 `RoomStage`。
- **邏輯的成本跟著螢幕更新率走**：120Hz 的手機每秒推進 120 次。

## 業界做法

### 固定時間步與內插

- 模擬照固定的時間步前進，和畫面的更新率分開。這樣模擬每次執行的結果都相同，也是重播、同步多台裝置的基礎（[Gaffer：Fix Your Timestep!](https://gafferongames.com/post/fix_your_timestep/)）。
- Godot 的做法是把遊戲邏輯放在固定 tick 的 `_physics_process`，不放在每畫一格就跑一次的 `_process`。開了內插後，畫面和邏輯脫鉤，tick 數可以照遊戲需要選；文件把 10～30 歸為低、30～60 為中。tick 數低時，畫面高 FPS 也比較省 CPU，因為 AI 不用每一格都跑。在 tick 以外直接設定位置會造成抖動（[Godot：Using physics interpolation](https://docs.godotengine.org/en/stable/tutorials/physics/interpolation/using_physics_interpolation.html)）。
- 代價：畫面顯示的是「上一個 tick 到這一個 tick 之間」，所以會比模擬落後一個 tick。

### 模擬與繪圖的資料分開

- Unreal 的繪圖跑在自己的執行緒，落後遊戲執行緒一到兩格。繪圖執行緒不能直接碰遊戲物件的記憶體，因為遊戲執行緒隨時可能在寫；繪圖用的是自己的代理物件（`FPrimitiveSceneProxy`），兩邊用指令佇列溝通（[Unreal：Threaded Rendering](https://dev.epicgames.com/documentation/en-us/unreal-engine/threaded-rendering-in-unreal-engine)）。
- Nystrom 的 Double Buffer：讓一連串的修改看起來是一次完成的，讀的人不會看到改到一半的狀態（[Game Programming Patterns：Double Buffer](https://www.gameprogrammingpatterns.com/double-buffer.html)）。
- 分執行緒的前提是兩邊**不共用會變動的資料**：各自持有自己的一份，只透過佇列或交接點傳值。

### 事件佇列

- Event Queue 把「送出」和「處理」在時間上分開：送的人在方便的時候送，處理的一方照自己的節奏處理（[Game Programming Patterns：Event Queue](https://gameprogrammingpatterns.com/event-queue.html)）。
- 套到我們的情況：主人點擊、AI 回覆、計時器都排進佇列，在模擬的節拍開頭依序處理，多個非同步的來源不會互相干擾。

### 重的工作放到背景

- Unity 的 Job System：從主執行緒排工作，在背景執行緒執行，每個工作拿到一份自己的資料副本，避免同時讀寫（[Unity：Job system overview](https://docs.unity3d.com/Manual/JobSystemOverview.html)）。
- Godot 的場景樹不是 thread-safe，背景做好的東西要用 `call_deferred` 交回主執行緒（[Godot：Thread-safe APIs](https://docs.godotengine.org/en/stable/tutorials/performance/thread_safe_apis.html)）。
- 共同點：遊戲狀態只在一個地方改；背景只算副本，結果再交回來。

### CPU 與 GPU 已經是平行的

Apple 建議 CPU 至少比 GPU 早一格準備，兩邊才能同時工作，並用 semaphore 限制同時在跑的格數（[Apple：Metal Best Practices：Triple Buffering](https://developer.apple.com/library/archive/documentation/3DDrawing/Conceptual/MTLBestPracticesGuide/TripleBuffering.html)）。我們現在的 Metal 指令也是 `commit` 後就交給 GPU，CPU 不等它畫完。

### 狀態怎麼組織

- Component 模式：讓一個實體同時涉及多個領域（例如畫面、行為、聲音），但這些領域彼此不耦合（[Game Programming Patterns：Component](https://gameprogrammingpatterns.com/component.html)）。
- ECS（Entity-Component-System）的好處主要在實體很多時；規模小時，抽象的成本比較高（[Wayline：ECS for indie game devs](https://www.wayline.io/blog/ecs-for-indie-game-devs)，個人意見，不是量測）。
- Apple 的 GameplayKit 有 `GKEntity`、`GKComponent`、`GKStateMachine`，文件沒有標示 deprecated（[Apple：GKStateMachine](https://developer.apple.com/documentation/gameplaykit/gkstatemachine)），但它們是以 class 為主的舊式 API。RealityKit 的 ECS 綁著 RealityKit 自己的繪圖，和 [ADR 0006](../adr/0006-metal-rendering.md) 選的 Metal 衝突。

### Swift 的工具

- `Mutex`（Synchronization 框架）iOS 18 起可以用，剛好是我們的最低版本。之後如果模擬或繪圖搬到別的執行緒，可以用它交接快照（[Apple：Mutex](https://developer.apple.com/documentation/synchronization/mutex)）。

## 選項

| 選項 | 好處 | 代價 |
|---|---|---|
| **三層，模擬在自己的執行緒；固定節拍＋內插**（作者選的） | 狀態機在資料上、時間上都不參與 render；邏輯成本和螢幕更新率脫鉤；結果每次相同；非同步的事件依序進入 | 重構 `RoomStage` 與 `GameView`；事件與快照要跨執行緒交接；畫面落後一個節拍 |
| 三層都在主執行緒；固定節拍＋內插 | 資料上分開，同步最少 | 狀態機跑的時間仍和畫圖共用主執行緒 |
| 分層，但用變動時間步（現在的推進方式） | 不用內插，沒有延遲 | 成本跟著螢幕更新率走；結果會隨每一格的時間點有些微不同 |

點擊判斷用畫面準備交出的繪製清單（也就是畫面上看到的樣子），所以模擬搬到別的執行緒後，點擊判斷仍然留在主執行緒，不用跨執行緒。
| ECS 存狀態 | 實體很多時最有利 | 我們的規模下，抽象成本大於好處 |

## 參考量測（Mac，只看量級）

2026-11-20 在 Mac（M4 Pro）上照 `GameView` 的流程（每隻有自己的狀態機與閒晃，不經過 SwiftUI、不畫 Metal）模擬 120 秒。Mac 比 iPhone 快，數字只能看趨勢，實機要另外量。

- 每一格的舞台邏輯：2 隻約 0.006 毫秒；32 隻全部不停走，平均約 0.12 毫秒。`update` 會隨隻數平方成長，因為每一步都要算別隻佔住哪些格。
- 找路 `RoomPath.find` 一次平均 0.7 毫秒，最慢 3.5 毫秒，是目前唯一的尖峰；同樣走過整個房間的 `stepCounts` 只要約 0.02 毫秒。原因是 Dijkstra 每一步都線性掃過待處理清單。這證實「重的工作要能變成請求、在背景算」這條路是需要的，也可以先改演算法。

## 來源

查證日期都是 2026-11-20。

- [Gaffer On Games：Fix Your Timestep!](https://gafferongames.com/post/fix_your_timestep/)
- [Godot：Using physics interpolation](https://docs.godotengine.org/en/stable/tutorials/physics/interpolation/using_physics_interpolation.html)、[Thread-safe APIs](https://docs.godotengine.org/en/stable/tutorials/performance/thread_safe_apis.html)
- [Unreal Engine：Threaded Rendering](https://dev.epicgames.com/documentation/en-us/unreal-engine/threaded-rendering-in-unreal-engine)
- [Unity：Job system overview](https://docs.unity3d.com/Manual/JobSystemOverview.html)
- Robert Nystrom，Game Programming Patterns：[Event Queue](https://gameprogrammingpatterns.com/event-queue.html)、[Double Buffer](https://www.gameprogrammingpatterns.com/double-buffer.html)、[Component](https://gameprogrammingpatterns.com/component.html)、[Update Method](https://www.gameprogrammingpatterns.com/update-method.html)
- Apple：[Metal Best Practices：Triple Buffering](https://developer.apple.com/library/archive/documentation/3DDrawing/Conceptual/MTLBestPracticesGuide/TripleBuffering.html)、[Mutex](https://developer.apple.com/documentation/synchronization/mutex)、[GKStateMachine](https://developer.apple.com/documentation/gameplaykit/gkstatemachine)
- [Wayline：ECS for indie game devs](https://www.wayline.io/blog/ecs-for-indie-game-devs)（個人意見）
