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

- **Team ID 放在不進 git 的 `ios/Config/Signing.local.xcconfig`**（作者 2026-11-16 決定）：專案層級的設定讀 `ios/Config/Base.xcconfig`，它用 `#include?` 載入本機檔，三個 target 都會繼承。沒有本機檔時照樣能在模擬器編譯（2026-11-16 實測）。在 Xcode 的 Team 選單重選會把 Team ID 寫回 `project.pbxproj`，commit 前要檢查（見[資安檢查](public-repo-security.md)）。
- **角色包會跟著裝到手機**：只限作者自己的裝置，符合 [ADR 0004](../adr/0004-plush-likeness-private-use.md) 的自用範圍。
- **`CharacterPacks.bundle` 沒有 Info.plist**：模擬器沒問題，實機簽署時會不會出錯還沒驗證。
