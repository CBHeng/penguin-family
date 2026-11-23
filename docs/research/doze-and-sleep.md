# 打瞌睡與睡覺：睏意與換表情

2026-11-20 為 A1 第 13 項整理。作者決定的玩法寫在[遊戲設計的睏意](../product/game-design.md#睏意打瞌睡與睡覺)，分版與進度在 [TASKS](../../TASKS.md)。

## 睏意：需求驅動的行為

作者提出打瞌睡與睡覺共用一個睏意：醒著時增加，超過門檻時有機率觸發，睡覺降得多又快，打瞌睡降得慢。

- 這是 The Sims 的做法。每個角色有一組需求（Maxis 叫 motive，其中一個是 Energy），數值隨時間變化。角色看當下能做的事，挑最能滿足需求的那件。這種做法一般叫 needs-based AI 或 utility AI。The Sims 不一定挑分數最高的，而是從前幾名裡隨機挑，所以角色不會每次都做同一件事。
- 套到我們：閒晃已經是依權重隨機挑（`wander.json`）。睏意只是讓「打瞌睡」「睡覺」這兩種活動在睏意超過門檻後才進入候選，機率也寫成資料。
- **假設，這次不做**：之後如果加入其他需求（例如無聊、想黏著），可以沿用同一套。要不要做由作者決定。

## 換表情：閉眼、泡泡破掉

現在眼睛畫在頭的部件裡面。動作的片段只能轉動、縮放、移動部件（[ADR 0009](../adr/0009-characters-species-motion-data.md)），沒辦法把睜眼換成閉眼。

其他工具的做法：

- **Spine**：每個插槽（slot）同一時間只顯示一張圖。動畫用關鍵影格決定這一刻顯示哪一張，例如睜眼換成閉眼。官方建議用這種方式隱藏，不要用透明度 0；想要淡出時，先把顏色淡到透明再換。
- **Live2D**：閉眼用參數表示，0 是閉、1 是睜。整個部件的切換靠部件的不透明度。

我們的兩個選項：

| 選項 | 做法 | 代價 |
|---|---|---|
| 換部件 | 學 Spine：片段的關鍵影格決定某個部件顯示或隱藏。睜眼、閉眼是兩個部件 | 動作格式升版，App 的播放器與繪圖、私有素材 repo 的匯出都要改；要補 ADR |
| 翻面 | 眼睛拆成部件，笑眼上下翻過來（縱向縮放 -1）就是閉眼 | 格式不用改，但只能做閉眼；驚訝眼、暈眼、張嘴還是要換部件 |

**結果**：作者 2026-11-23 看過私有素材 repo 的原型（坐著打瞌睡、閉眼、鼻涕泡泡、Z、驚醒時用一隻手揉眼睛）後，選了「換部件」。另外決定 Z 與泡泡是共用的特效：形狀放在公開 repo，怎麼飄照樣由私有素材 repo 算好、匯出成片段。寫成 [ADR 0010](../adr/0010-motion-visibility-loops-effects.md)。睏意的數字放在每隻的 `wander.json`。

## 來源

查證日期都是 2026-11-20。

- The Sims 的需求與 AI：[Game Maker's Toolkit：The Genius AI Behind The Sims（逐字稿）](https://amara.org/subtitles/cVoJS4OdmVql/en/1/download/The%20Genius%20AI%20Behind%20The%20Sims.en.txt)、[the-decoder：Beyond the virtual dollhouse](https://the-decoder.com/beyond-the-virtual-dollhouse-simulating-life-in-games/)（二手整理）
- Spine 使用手冊：[Keys](http://en.esotericsoftware.com/spine-keys)、[Slots](http://en.esotericsoftware.com/spine-slots)、[Attachments](http://esotericsoftware.com/spine-attachments)
- Live2D：[Standard Parameter List](https://docs.live2d.com/en/cubism-editor-manual/standard-parameter-list/)、[About Pose](https://docs.live2d.com/en/cubism-sdk-manual/pose/)
