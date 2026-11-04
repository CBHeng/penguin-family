# 專案概要

- 專案名稱：penguin-family（企鵝陪伴 App）
- 專案描述：iOS 2.5D 養成陪伴遊戲。把作者兩隻企鵝玩偶的**靈魂**做進 App：平常裝可愛、偶爾小腹黑，主人難過時可以抱抱或聊天。
- 使用對象：作者與親友。目前不公開上架。
- 目前進度與下一步：見 [TASKS.md](TASKS.md)。

## 協作方式

- 問答、文件、計畫都用繁體中文；程式識別字用英文，領域用語依 [GLOSSARY.md](GLOSSARY.md)。
- 作者是資深 Java／Vue 開發者，做過 Flutter，不熟 iOS 與遊戲開發；不熟的地方作者會再追問。
- 優先驗證「靈魂」：判斷取捨時，先問這會不會讓企鵝更像作者家的那兩隻。
- 外部工具、法規、價格會變動：引用前先查證，並把來源與查證日期記進 `docs/research/`。
- 手感、效能、觸覺回饋以 iPhone 實機為準。

## 執行前必須確認的操作

以下操作先告知作者，等確認後才執行：

- 把玩偶照片、聊天內容或其他個資傳到第三方服務
- 選定或更換 AI 供應商與模型，以及任何會產生費用的操作
- 新增第三方套件，或新增系統權限（健康、定位、通知等）
- 更動 [docs/adr/](docs/adr/) 已定案的決定
- 刪除檔案、`git commit`、`git push`、把 repo 設為公開

## 文件地圖

| 什麼時候 | 讀什麼 |
|---|---|
| 回答下一步、回報進度、完成任務後更新 | [TASKS.md](TASKS.md) |
| 開工、確認階段內容與驗收標準 | [docs/product/roadmap.md](docs/product/roadmap.md) |
| 設計玩法、判斷某功能是否在範圍內 | [docs/product/vision.md](docs/product/vision.md) |
| 新增模組、調整程式結構 | [docs/architecture.md](docs/architecture.md) |
| 寫台詞、行為、人設提示 | [docs/characters/bible.md](docs/characters/bible.md)、[語氣底線](.claude/rules/character-voice.md) |
| 碰聊天、AI、記憶、後端、權限 | [安全與隱私底線](.claude/rules/safety-privacy.md) |
| 想質疑或推翻技術、資料、造型的決定 | [docs/adr/](docs/adr/) |
| 重新評估素材工具或引擎 | [docs/research/asset-and-engine.md](docs/research/asset-and-engine.md) |
| 碰 AI 費用、法規、上架議題 | [docs/research/compliance-and-ai.md](docs/research/compliance-and-ai.md) |
