# 法規、依賴研究與 AI 費用

查證日期：2026-11-04。這不是法律意見；法規內容多來自律所摘要與新聞，正式上架前要核對原文。實際要遵守的底線見 [safety-privacy](../../.claude/rules/safety-privacy.md)。

**可信度**：高＝官方文件或套件頁；中＝官方內容的二手整理、律所摘要、開發者討論；低＝廠商行銷或第三方部落格。

## Apple 規定

| 發現 | 來源 | 可信度 |
|---|---|---|
| 指引 5.1.2(i) 要求：個資傳給第三方 AI 前，須揭露並取得同意（2025 年 11 月更新） | [TechCrunch](https://techcrunch.com/2025/11/13/apples-new-app-review-guidelines-clamp-down-on-apps-sharing-personal-data-with-third-party-ai) | 中，以 Apple 現行指引為準 |
| 有開發者回報：審查員要求說明傳什麼、傳給誰，並在分享前徵求同意；同意畫面沒被看到也會被退審 | [Apple 開發者論壇](https://developer.apple.com/forums/thread/820209) | 中 |

## 陪伴型 AI 法規

| 發現 | 來源 | 可信度 |
|---|---|---|
| 加州 SB 243 於 2026-01-01 生效，對加州用戶提供陪伴聊天機器人即適用，沒有規模門檻 | [Perkins Coie](https://perkinscoie.com/insights/update/california-companion-chatbot-law-now-effect) | 中 |
| SB 243 內容包括揭露非人類、自傷危機處理、未成年人保護，用戶可提告 | 同上 | 中 |
| 台灣 AI 基本法已於 2026 年 1 月生效，目前偏原則性，風險框架仍在發展 | [Baker McKenzie](https://www.bakermckenzie.com/en/insight/publications/2026/01/taiwan-ai-basic-act) | 中 |

## 依賴與健康界線

| 發現 | 來源 | 可信度 |
|---|---|---|
| OpenAI 與 MIT 的研究發現，重度使用與較高的孤獨感、依賴感相關，但因果尚未確定；研究對象是 ChatGPT，不是專門的陪伴產品 | [AI Frontiers](https://ai-frontiers.org/articles/ai-friends-openai-study) | 中，未讀原始論文 |

## 同類產品

| 發現 | 來源 | 可信度 |
|---|---|---|
| Finch 缺席不懲罰，寵物不會死也不會難過 | [Headway](https://makeheadway.com/blog/finch-app-review/) | 低 |
| 有分析認為小工具是 Finch 回訪的關鍵之一，但數據未經驗證 | [Deconstructor of Fun](https://www.deconstructoroffun.com/blog/x0hd2ssr80y5n7gv0w967pg7hwd7tl) | 低 |

## AI 費用試算

- **單價來源**：Claude Code 內建的 Claude API 參考資料（2026-10-06 快取），2026-11-04 沒有另外查官網，實際以官方定價為準。
- **範圍**：只試算 Claude，還沒比較其他供應商。
- **假設**：每則輸入 1,500 tokens、輸出 100 tokens，每月 900 則，不計快取與思考用量。這些是假設，不是量測值。

| 模型 | 輸入／輸出（每百萬 tokens） | 每位主人每月 |
|---|---|---|
| Haiku 5.5 | $0.10／$0.50 | 約 $0.18 |
| Sonnet 5.5 | $2／$10 | 約 $3.6 |
| Opus 5.5 | $4／$20 | 約 $7.2 |

模型選擇等 B1 盲測後由作者決定，便宜的模型不一定演得出這種個性。
