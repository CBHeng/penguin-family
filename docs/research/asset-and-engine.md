# 素材工具與引擎調查

查證日期：2026-11-04。工具與價格變動快，採用前要再查官網。

**可信度**：高＝官方文件或套件頁；中＝官方內容的二手整理、開發者討論；低＝廠商行銷或第三方部落格。

## 結論

- **沒有找到適合絨毛企鵝的一鍵工具**：拍照後直接得到可互動角色的工具，目前沒有查到可靠的例子。
- **2026-11-16 起改走像素**，見 [ADR 0005](../adr/0005-pixel-art-swiftui.md)；下面 3D 與 RealityKit 的調查保留作紀錄。
- **素材**：3D 生成可以試，但絨毛效果沒有實測資料，所以由 S1 驗證，紙片 2.5D 當備案。
- **引擎**：原本的決定見 [ADR 0001](../adr/0001-realitykit-swiftui.md)（已被 0005 取代）。RealityKit 做遊戲的成熟度沒有查到具體資料，由 S2 驗證。
- **Godot**：沒有查到可靠的 iOS 3D 資料，尚未比較。

## 照片轉素材

| 發現 | 來源 | 可信度 |
|---|---|---|
| Vision 主體分離不限物體類別，iOS 17 起支援實例遮罩；可能把手和手持物視為同一主體 | [WWDC23 筆記](https://wwdcnotes.com/notes/wwdc23/10176) | 中 |
| Object Capture 建議 20～200 張照片、物體要有足夠紋理；沒有找到絨毛重建或綁骨的實例 | [WWDC21 筆記](https://wwdcnotes.com/documentation/wwdc21-10076-create-3d-models-with-object-capture/) | 中 |
| Meshy 可從圖片生成 3D，匯出格式含 USDZ、GLB | [Meshy](https://meshy.ai/features/image-to-3d) | 低（廠商） |
| 多部件或可動角色通常仍要手動清理 | [AI Tools Atlas](https://aitoolsatlas.ai/compare/meshy-3d-vs-3d-ai-studio) | 低 |
| Meshy、Tripo 免費方案的商用授權說法互相矛盾，要看現行官方條款 | [ScriptByAI](https://www.scriptbyai.com/best-free-ai-image-to-3d-generators/) | 低 |
| 3D AI Studio 宣稱綁骨支援鳥類等生物，未見獨立測試 | [官方文件](https://docs.3daistudio.com/processing/rigging) | 低（廠商） |
| AutoRig.online 主打非人形綁骨，有頁面稱其流程仍屬實驗性 | [Product Hunt](https://www.producthunt.com/products/autorig-online/launches/autorig-online) | 低 |
| Meta Animated Drawings 針對人形塗鴉，關節要手動定義，上傳時會詢問可否用於訓練 | [Engadget](https://www.engadget.com/meta-has-open-sourced-an-ai-project-that-turns-your-doodles-into-animations-183807106.html) | 中 |
| AI-Mascot 宣稱有透明背景輸出，但自述角色一致性仍在成熟中；Kling、Runway 的透明輸出未確認 | [AI-Mascot](https://aitoolscapital.pages.dev/tools/ai-mascot) | 低（廠商） |

## S1 生成工具（查證日期：2026-11-05）

| 發現 | 來源 | 可信度 |
|---|---|---|
| Meshy API 的多圖生成收 1～4 張，格式 JPG、PNG、WebP，單張上限 20 MB，每邊至少 32 像素；可輸出 USDZ。沒提到透明 PNG 怎麼處理 | [Meshy API 文件](https://docs.meshy.ai/en/api/multi-image-to-3d) | 高 |
| Meshy API 免費方案不能建立任務；網頁版免費方案是否可用，文件沒寫 | 同上 | 高 |
| Tripo API 有多視角生成，可輸出 USDZ，1 credit = $0.01，多視角每次 20～30 credits；網頁版方案與規格沒寫 | [Tripo 開發者頁](https://developers.tripo3d.ai/) | 高 |
| Tripo H3.1 多視角收 2～4 張 | [WaveSpeed](https://wavespeed.ai/blog/posts/introducing-tripo3d-v2-5-multiview-to-3d-on-wavespeedai) | 低（第三方） |
| Tripo 免費額度說法不一（200、300、600 credits），要看現行官網 | [Tripo 定價](https://tripo3d.ai/pricing)（搜尋摘要，未讀到全文） | 低 |
| Meshy 免費方案：每月 100 credits、最多 10 個資產，不含多圖生成；可下載格式含 USDZ，但沒單獨寫免費方案是否適用 | [Meshy 定價](https://www.meshy.ai/pricing) | 高 |
| Meshy 模型所有權：免費方案歸 Meshy，以 CC BY 4.0 授權給用戶，須標註來源；付費方案歸用戶 | [Meshy 條款 3.2](https://www.meshy.ai/terms-of-use)（2026-09-19 版） | 高 |
| Meshy 只明寫付費方案可把內容設為私有；沒寫免費方案的內容是否自動進社群頁 | 同上 | 高 |
| Meshy 預設可用非企業客戶的輸入與輸出訓練模型，可寄信到 support@meshy.ai 退出 | [Meshy 條款 2.9](https://www.meshy.ai/terms-of-use) | 高 |
| Meshy 禁止上傳含第三方受著作權保護內容的參考圖，用戶要保證擁有上傳所需的權利 | [Meshy 使用政策第 3 節](https://www.meshy.ai/acceptable-use-policy)（2024-11-11 版）、[條款 2.2](https://www.meshy.ai/terms-of-use) | 高 |

**尚未查證：** Tripo 的條款、隱私權政策與定價。官網對抓取回 403，要由作者貼內容。

## 像素原型的畫面層（查證日期：2026-11-11）

| 發現 | 來源 | 可信度 |
|---|---|---|
| SpriteKit 貼圖可設最近鄰取樣（`filteringMode = .nearest`），放大時保持像素方塊；預設是線性平滑 | [Apple：SKTexture.filteringMode](https://developer.apple.com/documentation/spritekit/sktexture/filteringmode.md) | 高 |
| 沒查到 SwiftUI 的 `SpriteView` 是否沿用上述設定，要實測 | 搜尋結果 | - |
| SwiftUI 可用 `TimelineView` 包 `Canvas` 做每秒 60 格的更新迴圈 | [Kodeco](https://kodeco.com/27594491-using-timelineview-and-canvas-in-swiftui/page/2?page=2)、[Jacob's Tech Tavern](https://blog.jacobstechtavern.com/p/swiftui-game-engine) | 中 |
| SwiftUI 放大圖片時關閉平滑的做法，沒查到可靠來源，要在模擬器實測 | 搜尋結果 | - |
| Xcode 16 起新專案預設用同步資料夾：放進資料夾的檔案自動加入專案，不用改專案檔 | [Apple 論壇](https://developer.apple.com/forums/thread/789705)、[Dimillian](https://dimillian.medium.com/why-you-should-use-xcode-16-buildable-folders-instead-of-groups-6f438611914d)、[pepicrft](https://pepicrft.me/blog/how-synchronized-groups-work-at-the-pbxproj-level/) | 中 |

**採用的做法**：部件合成用純 Swift 在原始像素尺寸完成，顯示層只做整數倍放大（見[架構](../architecture.md)）。

## 2.5D 呈現

| 發現 | 來源 | 可信度 |
|---|---|---|
| 可把 2D billboard 混進 3D 場景 | [80 Level](https://80.lv/articles/mixing-2d-billboards-and-3d-environments-in-a-game/) | 中 |
| Billboard 紙片可能穿進 3D 物件 | [Godot 問答](https://ask.godotengine.org/87021/prevent-clipping-billboard-sprites-into-objects-for-5d-game) | 中 |

## 動畫工具

| 發現 | 來源 | 可信度 |
|---|---|---|
| Rive 有內建狀態機與 SwiftUI API，執行階段無授權費 | [Rive vs Spine](https://rive.app/rive-vs-spine) | 低（廠商） |
| Rive 免費方案限制說法不一，有寫 3 個檔案，也有寫無限；使用前要查官網 | [Rive 定價舊頁](https://rive.app/community/doc/pricing/docuWp6cbOeg) | 中（可能過期） |
| Live2D 年營收低於 1,000 萬日圓通常不需要發行授權，可擴充型應用除外 | [Live2D 說明](https://help.live2d.com/en/?p=2172) | 高 |

## 引擎與框架

| 發現 | 來源 | 可信度 |
|---|---|---|
| RealityView 可直接放進 SwiftUI | [DEV](https://dev.to/arshtechpro/wwdc-2025-scenekit-deprecation-and-realitykit-migration-a-comprehensive-guide-for-ios-developers-o26) | 中 |
| SceneKit 已標記棄用，只修重大錯誤，新專案建議用 RealityKit | [Fatbobman](https://fatbobman.com/en/weekly/issue-090/) | 中 |
| Unity Personal 門檻為過去 12 個月營收與募資低於 $200K | [Unity Personal](https://unity.com/products/unity-personal) | 高 |
| Unity 已取消 Runtime Fee，但授權政策曾有爭議 | [VGChartz](https://www.vgchartz.com/article/462401/unity-cancels-runtime-fee/) | 中 |
| flutter_scene 仍在 1.0 前 | [pub.dev](https://pub.dev/packages/flutter_scene/versions/0.20.0) | 高 |
| Flame 只支援 2D | [DianApps](https://dianapps.com/blog/?p=14475) | 低 |
| Flame 提供遊戲迴圈與精靈圖等功能 | [DEV](https://dev.to/svprdga/flame-engine-the-game-engine-built-on-top-of-flutter-6j9) | 中 |
| Flutter 做主畫面小工具仍要建原生 Extension 與 App Group | [flutter_homescreen_widget](https://pub.dev/packages/flutter_homescreen_widget) | 高 |
| Flutter 有 Core Haptics 套件，支援動態參數與 AHAP | [core_haptics](https://pub.dev/documentation/core_haptics/latest/) | 高 |
| 部分觸覺套件很早期；觸覺不能在模擬器測試 | [custom_haptics_pro](https://pub.dev/packages/custom_haptics_pro) | 高 |
| Rive 有官方 Flutter runtime，舊 API 正在淘汰 | [文件](https://rive.app/docs/runtimes/flutter/flutter.md)、[changelog](https://pub.dev/packages/rive/versions/0.14.0-dev.1/changelog) | 高 |

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
