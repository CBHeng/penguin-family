# 專案概要

- 專案名稱：penguin-family（企鵝陪伴 App）
- 專案描述：iOS 2.5D 養成陪伴遊戲。把作者兩隻企鵝玩偶的**靈魂**做進 App：平常裝可愛、偶爾小腹黑，主人難過時可以抱抱或聊天。
- 使用對象：作者與親友。目前不公開上架。
- 目前進度與下一步：見 [TASKS.md](TASKS.md)。

## 協作方式

- 問答、文件、計畫都用繁體中文；程式識別字用英文，領域用語依 [GLOSSARY.md](GLOSSARY.md)。
- **每一則回覆都用繁體中文**，包含總結與進度回報。
- 作者是資深 Java／Vue 開發者，做過 Flutter，不熟 iOS 與遊戲開發；不熟的地方作者會再追問。
- 優先驗證「靈魂」：判斷取捨時，先問這會不會讓企鵝更像作者家的那兩隻。
- 外部工具、法規、價格會變動：引用前先查證，並把來源與查證日期記進 `docs/research/`。
- **現行文件只寫現況**：「原本是…後來改成…」、舊的粗估、已不採用的做法，寫進 [docs/history/timeline.md](docs/history/timeline.md)；不再適用的調查搬到 `docs/history/research/`。決定的理由留在 ADR。
- 手感、效能、觸覺回饋以 iPhone 實機為準。

## 機密資訊

API 金鑰、權杖、密碼、憑證與私鑰只留在本機被 `.gitignore` 排除的檔案或後端的環境變數，不寫進程式碼、文件或 commit，也不傳到第三方服務。

- `git add` 逐檔指定，commit 前檢查暫存內容。
- 發現機密已進入 git 或外流時，立刻停下並告知作者：刪除檔案不夠，要作廢並更換該金鑰。

## 分支、合併與版本

作者 2026-11-16 決定。GitHub 的規則集「main: squash PR only」強制執行，沒有例外，作者與 Claude 都不能直推 main。

- **commit、push、開 PR 一律照 [ship skill](.claude/skills/ship/SKILL.md) 的步驟**：逐檔加入、掃描、測試與文件檢查都在裡面。
- **main 不直接 push**：一律從最新的 main 開分支，經由 PR **squash 合併**（repo 只允許 squash，合併後自動刪分支）。分支上可以放心多次 commit，合併後在 main 只留一個 commit。
- **兩種分支**（作者 2026-11-16 決定）：

  | | 快速分支 | 版本分支 |
  |---|---|---|
  | 名稱 | `<類型>/<英文短名>`，類型用 `feat`、`fix`、`perf`、`docs`、`chore`，例如 `feat/second-penguin` | `release/vX.Y.Z`，例如 `release/v0.0.3`（不直接叫 `vX.Y.Z`，免得和 tag 同名） |
  | 內容 | 一件事，做完就進 | 一批事，整理完才進 |
  | 版本號 | 不動 | 升到 X.Y.Z（`ios/Config/Base.xcconfig` 的 `MARKETING_VERSION`） |
  | 合併後 | 不打 tag | 在 main 的那個 commit 打 `vX.Y.Z` 並推上去 |

- **分支名會公開**，不放角色名稱或其他私人字詞。
- **合併前在分支上做完**：測試通過、[TASKS.md](TASKS.md) 與文件更新；版本分支另外要升版。
- **PR 標題就是 main 上的 commit 訊息**：沿用 `類型: 中文摘要`。內文寫做了什麼、怎麼驗證（測試數、模擬器或實機），結尾附 attribution。開 PR 前一樣掃描私人字詞。升 0.x.0 或 1.0.0 由作者決定。

## 公開 repo

這個 repo 是公開的，只放程式與文件。玩偶照片與模型、填好的角色聖經、作者寫的台詞都留在本機，不進 git（清單與位置見 [ADR 0004](docs/adr/0004-plush-likeness-private-use.md)）。

## 執行前必須確認的操作

以下操作先告知作者，等確認後才執行：

- 把玩偶照片、聊天內容或其他個資傳到第三方服務
- 選定或更換 AI 供應商與模型，以及任何會產生費用的操作
- 新增第三方套件，或新增系統權限（健康、定位、通知等）
- 更動 [docs/adr/](docs/adr/) 已定案的決定
- 刪除檔案、`git commit`、`git push`、開 PR、合併 PR、打 tag
- 用記憶體換時間的設計：合計可能超過 50MB，或用量會隨內容持續成長（見[架構的技術取捨](docs/architecture.md#技術取捨)）

## 文件地圖

| 什麼時候 | 讀什麼 |
|---|---|
| 回答下一步、回報進度、完成任務後更新 | [TASKS.md](TASKS.md) |
| 開工、確認階段內容與驗收標準 | [docs/product/roadmap.md](docs/product/roadmap.md) |
| 設計玩法、判斷某功能是否在範圍內 | [docs/product/vision.md](docs/product/vision.md)、[docs/product/game-design.md](docs/product/game-design.md) |
| 新增模組、調整程式結構 | [docs/architecture.md](docs/architecture.md) |
| 找某件事在哪個檔案；新增、刪除、改名程式檔後更新 | [docs/code-map.md](docs/code-map.md) |
| 寫台詞、行為、人設提示 | [docs/characters/bible.md](docs/characters/bible.md)、[語氣底線](.claude/rules/character-voice.md) |
| 碰聊天、AI、記憶、後端、權限 | [安全與隱私底線](.claude/rules/safety-privacy.md) |
| 想質疑或推翻技術、資料、造型的決定 | [docs/adr/README.md](docs/adr/README.md)（索引，只看「現行」） |
| 想知道某個做法是怎麼演變來的、為什麼放棄舊做法 | [docs/history/timeline.md](docs/history/timeline.md) |
| 重新評估素材工具、引擎或繪圖方式 | [docs/research/asset-and-engine.md](docs/research/asset-and-engine.md)、[docs/research/rendering-performance.md](docs/research/rendering-performance.md) |
| 碰 AI 費用、法規、上架議題 | [docs/research/compliance-and-ai.md](docs/research/compliance-and-ai.md) |
| commit 前、碰簽署或金鑰 | [docs/research/public-repo-security.md](docs/research/public-repo-security.md) |
| 裝到實機、Apple 帳號與簽署 | [docs/research/device-testing.md](docs/research/device-testing.md) |
