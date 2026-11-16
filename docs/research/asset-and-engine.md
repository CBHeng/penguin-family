# 素材工具與引擎調查

現行做法：角色與箱庭走像素、維持原生 Swift（[ADR 0005](../adr/0005-pixel-art-swiftui.md)），繪圖用 Metal（[ADR 0006](../adr/0006-metal-rendering.md)，評估見[渲染效能](rendering-performance.md)）。這份留下仍有參考價值的調查；3D 路線（AI 生成 3D、RealityKit、紙片 2.5D、Rive、Live2D）的舊調查封存在[歷史](../history/research/3d-route.md)。

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
