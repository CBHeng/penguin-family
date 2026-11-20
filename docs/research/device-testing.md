# 實機測試：帳號與簽署

查證日期：2026-11-16。這次只讀到搜尋結果的摘要，沒有逐頁讀原文。可信度定義同其他研究文件：高＝官方文件；中＝官方內容的二手整理、開發者討論；低＝來源不明。

## 結論

- **自己的 iPhone 用免費 Apple ID 就能測**：Xcode 會建立「Personal Team」幫 App 簽署，不用付費。
- **免費簽署的 App 7 天後打不開**，要接上 Mac 從 Xcode 再執行一次；能裝的裝置與 App 數量也有上限。
- **給親友裝（A2）需要付費的 Apple Developer Program**（每年 99 美元），才能用 TestFlight。這是費用決定，到 A2 前再由作者決定。

## 免費與付費

| 發現 | 來源 | 可信度 |
|---|---|---|
| 任何 Apple ID 都能在自己的裝置上測試，Xcode 裡顯示為 Personal Team | [Apple 開發者論壇](https://developer.apple.com/forums/thread/761325) | 中 |
| 免費（Personal Team）的描述檔 7 天後過期，付費的最長一年 | [Apple：會員資格比較](https://developer.apple.com/support/compare-memberships/) | 高，只讀到摘要 |
| 過期後 App 點了打不開，重新從 Xcode 建置安裝就會再延長 7 天 | 同上、[開發者部落格](https://mybyways.com/blog/new-limitations-imposed-on-free-apple-developer-account) | 中 |
| 免費帳號：最多約 3 台裝置、每 7 天最多 10 個 App ID；不能用 App 內購買、Sign in with Apple 等付費功能 | [開發者部落格](https://mybyways.com/blog/new-limitations-imposed-on-free-apple-developer-account)、[Expo](https://expo.dev/blog/apple-developer-program-explained-free-vs-paid) | 中，以 Apple 現行條款為準 |
| TestFlight 與上架需要付費會員（每年 99 美元） | [Expo](https://expo.dev/blog/apple-developer-program-explained-free-vs-paid)、[Apple 開發者論壇](https://developer.apple.com/forums/thread/28897) | 中 |

## iPhone 上要做的設定

| 發現 | 來源 | 可信度 |
|---|---|---|
| 要開「開發者模式」：設定 → 隱私權與安全性 → 開發者模式，開啟後重新開機，再確認一次並輸入密碼 | [Apple：Enabling Developer Mode on a device](https://developer.apple.com/documentation/xcode/enabling-developer-mode-on-a-device) | 高 |
| 開發者模式的開關要先和 Xcode 配對過才會出現 | 同上 | 高 |
| 第一次打開免費簽署的 App，要到 設定 → 一般 → VPN 與裝置管理，信任自己的開發者帳號 | [Apple 開發者論壇](https://developer.apple.com/forums/thread/761325)、[Apple 支援（企業 App 的同一個選單）](https://support.apple.com/118254) | 中 |

## 不接線（無線執行）

| 發現 | 來源 | 可信度 |
|---|---|---|
| 第一次要用線接上，在 Devices and Simulators 勾選「Connect via network」；之後同一個網路就能無線執行 | [Apple 開發者論壇](https://developer.apple.com/forums/thread/89040)、[Xcode 9 說明](https://help.apple.com/xcode/mac/9.0/en.lproj/dev2809b6cff.html) | 中，來源較舊，Xcode 26 能否第一次就無線配對未證實 |
| Mac 和 iPhone 要在同一個網路，iPhone 要有設密碼 | [開發者部落格](https://prateepgedupudi.github.io/2018/02/23/cut-the-cord-to-install-run-and-debug-ios-apps-in-the-xcode-9-x) | 中 |
| 手動輸入 IP 連線的舊方法已經不適用 | [Apple 開發者論壇（DTS 工程師回覆）](https://developer.apple.com/forums/thread/805833) | 高 |

## 本專案要注意的

- **Team ID 放在不進 git 的 `ios/Config/Signing.local.xcconfig`**（作者 2026-11-16 決定）：專案層級的設定讀 `ios/Config/Base.xcconfig`，它用 `#include?` 載入本機檔，三個 target 都會繼承。沒有本機檔時照樣能在模擬器編譯（2026-11-16 實測）。在 Xcode 的 Team 選單重選會把 Team ID 寫回 `project.pbxproj`，commit 前要檢查（見[資安檢查](public-repo-security.md)）。2026-11-18 作者沒有動 Team 選單，從 Xcode 按 Run 裝到手機後，`project.pbxproj` 的 Debug、Release 也各多了一行 `DEVELOPMENT_TEAM`，已還原；所以用 Xcode 裝過之後一律先看 `git status`。
- **在 Xcode 把 Run 改成 Release**（Product → Scheme → Edit Scheme… → Run → Build Configuration）會建共用的 scheme 檔 `xcshareddata/xcschemes/`，已放進 `.gitignore`（作者 2026-11-18 決定，是個人偏好）。判斷手感要用 Release：Debug 沒有最佳化，慢很多（例如建一次舞台，模擬器 Debug 約 107 毫秒、最佳化約 2.8 毫秒）。
- **角色包會跟著裝到手機**：只限作者自己的裝置，符合 [ADR 0004](../adr/0004-plush-likeness-private-use.md) 的自用範圍。
- **`CharacterPacks.bundle` 沒有 Info.plist**：2026-11-16 實機簽署、安裝、執行都正常。

## 本專案實際的安裝與量測步驟（2026-11-16，iPhone 11、iOS 18.7.8）

iPhone 已配對、開發者模式已開時，可以不開 Xcode 介面，用指令完成（Claude 也是這樣做的）：

```sh
# 找手機：CoreDevice 的代號（裝 App、啟動用）
xcrun devicectl list devices
# 編譯並自動簽署（量效能要用 -configuration Release）
xcodebuild -project ios/PenguinFamily.xcodeproj -scheme PenguinFamily -configuration Debug \
  -destination 'id=<CoreDevice 代號>' -allowProvisioningUpdates build
# 安裝、啟動
xcrun devicectl device install app --device <CoreDevice 代號> <建置出的 PenguinFamily.app>
xcrun devicectl device process launch --device <CoreDevice 代號> com.cbheng.PenguinFamily
# 量卡頓：Instruments 用的是另一個代號（UDID），用 xctrace 列出
xcrun xctrace list devices
xcrun xctrace record --template 'Animation Hitches' --device <UDID> --time-limit 40s --launch -- com.cbheng.PenguinFamily
```

- 第一次啟動會失敗（簽署未被信任）：在手機的 設定 → 一般 → VPN 與裝置管理 信任自己的開發者帳號，之後就能啟動。
- Animation Hitches 範本以「卡頓」與「主執行緒延遲」為主，不含函式呼叫的取樣。
- **要找慢在哪一步**，加上我們自己的量測點一起錄（App 內建 `PerfSignposts`）：

```sh
xcrun xctrace record --template 'Time Profiler' --instrument 'Hangs' --instrument 'Points of Interest' \
  --device <UDID> --time-limit 40s --launch -- com.cbheng.PenguinFamily
```

  匯出 `os-signpost` 表就能看到每一步的時間；Time Profiler 的函式取樣匯出後只有記憶體位址，要另外符號化，通常看量測點就夠了。
  主執行緒的量測點是 `frame`、`prepare`、`draw`、`tap`；模擬在自己的執行緒，量測點是 `simulate`（ADR 0008）。

## 驗收狀態與繪圖的分工（ADR 0008）

ADR 0008 的定案條件：手感不比 v0.0.7 差，而且狀態機變慢時畫面照樣順。

1. 用 Release 裝到手機（`-configuration Release`，或 Xcode 的 scheme 用 Release 執行）。點企鵝、看牠走路，和 v0.0.7 比手感。有東西在動時，點下去到開始畫哈囉多 0～33 毫秒（平均約 17），全部站著時約 0（見 ADR 0008）。
2. 讓模擬故意變慢：在 Xcode 的 Product → Scheme → Edit Scheme… → Run → Arguments 的「Arguments Passed On Launch」加一行 `-SimulationExtraTickMilliseconds 50`（選單名稱以畫面為準），再執行一次。每個節拍多花 50 毫秒，模擬跟不上真實時間，企鵝會走得慢一點；拖曳、捏合鏡頭時畫面應該照樣順。看完把這一行刪掉或取消勾選。
   - 原理：啟動參數 `-名稱 值` 會成為 App 的 `UserDefaults`，`SimulationRunner` 啟動時讀它，預設是 0。2026-11-20 在模擬器用 `xcrun simctl launch <裝置> com.cbheng.PenguinFamily -SimulationExtraTickMilliseconds 50` 啟動過，App 正常執行；實機的效果還沒看過。
3. 想看數字時，照上一節加上 Points of Interest 錄一次：`simulate` 變長時，主執行緒的 `frame` 不應該跟著變長。

2026-11-20 作者在 iPhone 11 上照 1、2 驗收：手感感覺不出差別，模擬變慢時畫面一樣順，ADR 0008 定案。數字沒有錄。
