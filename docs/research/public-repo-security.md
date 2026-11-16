# 公開 iOS repo 的資安檢查

查證日期：2026-11-13。重點是會被拿來攻擊或竊取的資訊：金鑰與憑證、簽署檔、本機資訊。這次只讀到搜尋結果的摘要，沒有逐頁讀原文；可信度標示沿用其他研究文件的定義。

**可信度**：高＝官方文件；中＝官方內容的二手整理、資安媒體、開發者討論；低＝廠商部落格或來源不明的數字。

## 結論

1. 金鑰、權杖、密碼、`.p12`、`.p8` 一旦進入公開 repo，要當作已經被拿走：**先作廢並換新**，再清理歷史。只刪檔案或改寫歷史都不夠。
2. App 裡的金鑰會被人從安裝檔挖出來，就算 repo 是私有的也一樣。需要權限的金鑰只放後端。
3. Xcode 會在你沒注意時把本機資訊寫進會被 commit 的檔案：使用者名稱、Team ID、Scheme 的環境變數。commit 前要看過暫存內容。

## 金鑰與憑證

| 發現 | 來源 | 可信度 |
|---|---|---|
| 外流的是密碼、權杖、憑證時，第一步是作廢或更換，之後才清除歷史；能用更換金鑰解決的，GitHub Support 不協助移除 | [GitHub Docs：Removing sensitive data](https://docs.github.com/en/authentication/keeping-your-account-and-data-secure/removing-sensitive-data-from-a-repository) | 高 |
| 改寫歷史後，別人手上的舊 clone 仍保有舊資料 | 同上 | 高 |
| GitHub 2024 年在平台上偵測到超過 3,900 萬筆外流的機密；公開 repo 預設開啟 push protection，但使用者可以關掉 | [GitHub Blog](https://github.blog/security/application-security/next-evolution-github-advanced-security/) | 高 |
| 有掃描發現，約 51.8% 有效的外流憑證屬於 push protection 預設不擋的類型（例如資料庫連線字串、Google API key），不能只靠 GitHub 把關 | [InfoQ](https://www.infoq.com/news/2025/09/github-leaked-secrets) | 中 |
| 外流的機密常在幾分鐘內被自動收集並利用；「平均五分鐘內」的數字找不到 GitHub 原始報告 | [SecurityWeek](https://www.securityweek.com/500000-active-credentials-left-exposed-on-github/) | 中，具體數字未證實 |

## 寫在 App 裡的金鑰

| 發現 | 來源 | 可信度 |
|---|---|---|
| 攻擊者能用免費工具反組譯 App，取出寫死的 API key；寫死的金鑰外流後也很難全面更換 | [OWASP Mobile Top 10：M7](https://owasp.org/www-project-mobile-top-10/2023-risks/m7-insufficient-binary-protection.html) | 高 |
| OWASP 把「API key 寫死在 App 套件裡」列為弱點 MASWE-0005；`.xcconfig`、`Info.plist`、資源檔裡的金鑰都算 | [OWASP MAS](https://mas.owasp.org/) | 高，只讀到摘要 |
| 混淆（obfuscation）不能算保護 | [Security Champions：MASVS](https://security-champions.pages.dev/module-9-mobile-security/part-b-masvs-pitfalls.html) | 中 |
| 從 `.xcconfig` 注入金鑰只能讓金鑰不進 git，編譯後一樣會在 App 裡 | 由上面 M7 推論；延伸閱讀 [NSHipster：Secret Management on iOS](https://nshipster.com/secrets/) | 推論 |

本專案的對應規則：App 內不放任何金鑰，AI 金鑰只放後端（見[安全與隱私底線](../../.claude/rules/safety-privacy.md)）。

## 簽署相關

| 檔案或資訊 | 風險 | 來源 | 可信度 |
|---|---|---|---|
| `.p12`（簽署憑證＋私鑰）、`.p8`（App Store Connect API 金鑰） | 機密，能拿來冒名簽署或操作你的開發者帳號 | [程式碼簽署交接指南](https://codenote.net/en/posts/mac-code-signing-handover-product-team-sre-team-split/) | 中 |
| Team ID（`DEVELOPMENT_TEAM`） | 一般認為是公開資訊，每個簽署過的 App 裡都有；沒找到 Apple 官方說法 | [arduino-lint PR #995](https://github.com/arduino/arduino-lint/pull/995)、[Apple 開發者論壇](https://developer.apple.com/forums/thread/92602) | 中 |
| Team ID 寫進 `project.pbxproj` | 不算機密，但 fork 的人得自己改；常見做法是放進不進 git 的 `.xcconfig`，pbxproj 裡留空 | [Apple 開發者論壇](https://developer.apple.com/forums/thread/672833) | 中 |
| `.mobileprovision` | 內含 Team ID、憑證、權限，開發用的還列出已註冊裝置的 UDID | [Apple 開發者論壇：What is a provisioning profile](https://developer.apple.com/forums/thread/685723) | 高 |

## Xcode 會寫進檔案的本機資訊

| 位置 | 會寫什麼 | 處理 | 來源 | 可信度 |
|---|---|---|---|---|
| `xcuserdata/` | 個人的中斷點、視窗狀態、非共享 Scheme | 放進 `.gitignore` | [Cocoacasts](https://cocoacasts.com/a-gitignore-for-swift-projects) | 中 |
| `xcshareddata/xcschemes/*.xcscheme` | Scheme 的環境變數與啟動參數。**共享 Scheme 會被 commit**，在這裡填金鑰就會外流 | 金鑰不要填在 Scheme 的環境變數 | [Swift Forums](https://forums.swift.org/t/setting-up-environment-variables-or-other-way-to-configure-secrets-for-tests-in-a-swift-package/49811) | 中 |
| 新檔案的檔頭註解 | `Created by <Mac 使用者名稱>` | commit 前刪掉 | 本機觀察（Xcode 26.6） | — |
| `project.pbxproj` | 加入專案資料夾外的檔案時，可能寫進含使用者名稱的絕對路徑 | commit 前搜尋 `/Users/` | 推論，未查到來源 | — |
| `.DS_Store` | 列出資料夾裡的檔名，連已刪除的檔名都可能留著 | 放進 `.gitignore` | [Cybernews](https://cybernews.com/security/microsoft-vancouver-leaking-website-credentials-via-overlooked-ds-store-file/) | 中 |
| commit 的作者資訊 | 名字與 email，任何能讀 repo 的人都看得到；改成 noreply 信箱只影響之後的 commit | 看個人取捨 | [GitHub Docs：封鎖會暴露 email 的 push](https://docs.github.com/en/github/setting-up-and-managing-your-github-user-account/managing-email-preferences/blocking-command-line-pushes-that-expose-your-personal-email-address) | 高 |

本 repo 的 `.gitignore` 已經排除 `xcuserdata/`、`.DS_Store`、`.env`、`Secrets.xcconfig`、`*.p8`、`*.p12`、`*.pem`、`*.key`、`*.mobileprovision`。

## commit 前的檢查

```sh
# 看暫存了哪些檔案
git status --short
# 搜尋暫存內容裡的本機路徑、使用者名稱、金鑰線索
git diff --cached | grep -n -i -E '/Users/|Created by|DEVELOPMENT_TEAM|api[_-]?key|secret|token|password|BEGIN .*PRIVATE'
```

搜尋有結果不一定是問題（例如文件裡的「tokens」計價），但每一筆都要看過。
