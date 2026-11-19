# 素材工具與引擎調查

現行做法：角色與箱庭改走平面向量（[ADR 0007](../adr/0007-flat-vector-art.md)），維持原生 Swift（[ADR 0005](../adr/0005-pixel-art-swiftui.md)），繪圖用 Metal（[ADR 0006](../adr/0006-metal-rendering.md)，評估見[渲染效能](rendering-performance.md)）。這份留下仍有參考價值的調查；3D 路線（AI 生成 3D、RealityKit、紙片 2.5D、Rive、Live2D）的舊調查封存在[歷史](../history/research/3d-route.md)。

## 改走向量的技術評估（查證日期：2026-11-18）

作者覺得像素版動起來像破版，問換成平面向量的技術好處與壞處。結論與決定見 [ADR 0007](../adr/0007-flat-vector-art.md)。

| 發現 | 來源 | 可信度 |
|---|---|---|
| 像素圖不是整數倍放大時，有的像素會比別的大；常見做法是只用整數倍 | [MDN：Crisp pixel art look](https://developer.mozilla.org/en-US/docs/Games/Techniques/Crisp_pixel_art_look)、[Integer scaling](https://tanalin.com/en/articles/integer-scaling/) | 高、中 |
| 剪紙動畫（cutout animation）：角色拆成頭、身體、手等部件，主要靠旋轉部件做動作；有父子關係與轉軸 | [Godot：Cutout animation](https://docs.godotengine.org/en/3.5/tutorials/animation/cutout_animation.html) | 高 |
| Metal 的取樣器預設取最近的像素、不用 mipmap；線性取樣加 mipmap 要自己設定 | [Apple：Adding mipmap filtering to samplers](https://developer.apple.com/documentation/metal/adding-mipmap-filtering-to-samplers) | 高 |
| Metal 的多重取樣抗鋸齒（MSAA）可以在 Apple GPU 的晶片暫存區直接合併，多重取樣的畫布可以不佔記憶體（memoryless） | [Apple：MSAA](https://developer.apple.com/tutorials/data/documentation/metal/improving-edge-rendering-quality-with-multisample-antialiasing-msaa.md)、[Apple：Choosing a resource storage mode for Apple GPUs](https://developer.apple.com/documentation/metal/choosing-a-resource-storage-mode-for-apple-gpus.md) | 高 |
| Xcode 12 起資產目錄可以放 SVG（建置時處理）；沒查到公開的 API 能在執行時讀任意 SVG 檔，通常要自己畫或用第三方套件 | [sarunw：SVG image assets supported in Xcode 12](https://sarunw.com/posts/svg-image-assets-supported-in-xcode12/)、[Apple 論壇：Native SVG support](https://developer.apple.com/forums/thread/113015) | 中（查不到不等於沒有） |

**對這款 App 的推估（推論，實驗時實測）**：

- **記憶體**：像素版的貼圖很小，GPU 放大不另外佔記憶體。向量要照最大倍率準備貼圖，記憶體隨倍率的平方成長。iPhone 11（螢幕 2 倍）抱抱倍率 7pt：企鵝 44×45 單位約 616×630 實體像素，部件重疊與 mipmap 算進去，每個方向約 3MB，兩隻、三個方向約 20MB；螢幕 3 倍的機型約 40MB。箱庭 384×256 單位畫成一張大圖：遠景 3pt 約 14MB，抱抱 7pt 約 77MB。
- **耗電**：平滑移動要每秒畫 60 張；現在鏡頭跟著企鵝時本來就每秒 60 張，增加的不多，需要時可以限制在 30 張。
- **繪圖層**：混合方式已經是向量需要的「預乘 alpha」（`SpriteRenderer`），取樣器要改成線性加 mipmap；要新增每個部件的旋轉縮放，以及外框分兩次畫。

工具與價格變動快，採用前要再查官網。**可信度**：高＝官方文件或套件頁；中＝官方內容的二手整理、開發者討論；低＝廠商行銷或第三方部落格。

## 像素路線重新評估 Flutter（查證日期：2026-11-16）

[ADR 0005](../adr/0005-pixel-art-swiftui.md) 改走像素後，作者要求重新評估 Flutter，最重視互動效能。**沒有找到 Flutter 與原生 iOS 直接比較的獨立量測**，以下多為官方文件與議題回報。

| 發現 | 來源 | 可信度 |
|---|---|---|
| iOS 上 Impeller 預設啟用，以前 Skia 的著色器編譯卡頓已大致解決 | [Flutter：Impeller](https://docs.flutter.dev/perf/impeller) | 高 |
| iOS 上 Flutter 的觸控曾比原生慢一整格（捲動時） | [flutter/flutter#110431](https://github.com/flutter/flutter/issues/110431) | 高 |
| Flutter 3.50 宣稱修好：輸入延遲少一格，60Hz 少 16ms、120Hz 少 8ms；Flutter 自己量的，沒有獨立驗證 | [What's new in Flutter 3.50](https://flutter.dev/blog/whats-new-in-flutter-3-50) | 中，官方自評 |
| 兩邊都要在 Info.plist 加 `CADisableMinimumFrameDurationOnPhone` 才能在 ProMotion 機型超過 60Hz；Flutter 在 iOS 不能自己控制更新率 | [Apple（iClarified 轉述）](https://www.iclarified.com/82663/apple-posts-developer-documentation-for-promotion-on-iphone-13-pro-12-refresh-rates-used)、[refresh_rate 套件](https://pub.dev/packages/refresh_rate) | 中 |
| iOS 觸覺第一次觸發有延遲，原生與 Flutter 都要先呼叫 `prepare()` 預熱；Flutter 要經過套件與平台通道 | [haptic_feedback PR](https://gh.r-mj.com/nohli/haptic_feedback/pull/103)、[haptic_kit](https://pub.dev/documentation/haptic_kit/latest/) | 中 |
| Flutter 畫像素圖要設 `FilterQuality.none` 並對齊整數像素，才不會糊 | [社群整理](https://sharedcontext.ai/agents/external/IponeRacing/flutter-flame-game-specialist)、[Phaser 像素指南](https://cdn.jsdelivr.net/npm/phaser@4.2.0/docs/Phaser%204%20Pixel%20Art%20Guide/Phaser%204%20Pixel%20Art%20Guide.md) | 低～中 |

| Core Haptics 支援 iPhone 8 以後的機型；用 `CHHapticEngine.capabilitiesForHardware().supportsHaptics` 檢查；模擬器不能測 | [Apple 開發者論壇（引 WWDC）](https://developer.apple.com/forums/thread/701938)、[Kodeco](https://www.kodeco.com/10608020-getting-started-with-core-haptics) | 中 |

**對這款 App 的判斷（推論）**：畫面只有幾個小像素角色，兩邊算圖都綽綽有餘；互動效能的差別在「點下去到畫面與觸覺回應」。原生少了 Flutter 引擎與平台通道這兩層，Flutter 的觸控落差官方宣稱最近才修好。沒有證據顯示 Flutter 在互動效能上較好。真正的比較要在實機上做同一個「點一下＋觸覺」來量。作者 2026-11-16 決定維持原生（[ADR 0005](../adr/0005-pixel-art-swiftui.md)）。

## 裝置端 AI

| 發現 | 來源 | 可信度 |
|---|---|---|
| Foundation Models 需支援 Apple Intelligence 的裝置；查到的資料多只列簡體中文，沒有來源確認支援繁中 | [介紹文章](https://www.natashatherobot.com/p/apple-foundation-models) | 低，需查官方文件 |
