---
name: ship
description: 作者同意 commit、push 或開 PR 時（「commit」「push」「開 PR」「送出」「commit push」等），照這裡的步驟把目前分支的改動送進 GitHub。作者沒同意時不使用。
---

# ship：commit、push、開 PR

作者說要 commit、push 或開 PR（或用其他說法同意），就是同意這一輪的那幾步。**做到作者說的範圍為止**：

| 作者說 | 做到 |
|---|---|
| commit | 第 1～3 步 |
| push、commit push | 第 1～4 步 |
| 開 PR、送出、commit push 開 PR | 第 1～5 步 |

每一輪都以第 6 步回報結束。**合併 PR 與打 tag 不在這裡**，那兩步每次另外問作者。分支規則見 [CLAUDE.md](../../../CLAUDE.md) 的「分支、合併與版本」。

作者有給 PR 標題或摘要時，照著用。

## 1. 認分支

```sh
git branch --show-current
```

- `main`：停下，問作者要開哪一種分支、叫什麼名字；不在 main 上 commit。
- `release/vX.Y.Z`：**版本分支**。
- 其他（`feat/`、`fix/`、`perf/`、`docs/`、`chore/`）：**快速分支**。

完成：知道是哪一種分支，而且不在 main 上。

## 2. 合併前的檢查

- **測試**：`ios/` 底下有改動時，跑一次全部測試，全過才往下（數字記下來，寫進 PR）：
  ```sh
  cd ios && xcodebuild -project PenguinFamily.xcodeproj -scheme PenguinFamily \
    -destination 'platform=iOS Simulator,name=iPhone 17' test
  ```
- **文件**：[TASKS.md](../../../TASKS.md) 的勾選與進度、[程式地圖](../../../docs/code-map.md)（新增、刪除、改名程式檔時）、架構與[時間線](../../../docs/history/timeline.md)跟改動一致。
- **要開 PR 時（做到第 5 步）才檢查版本號**：版本分支的 `ios/Config/Base.xcconfig` `MARKETING_VERSION` 與 TASKS 的版本都等於分支名的 X.Y.Z；快速分支的 `MARKETING_VERSION` 沒有動。版本分支中途只 commit 或 push 時，不必先升版。

完成：測試全過（或沒有改 `ios/`），文件與版本號都對。有一項不對就先修好，或停下問作者。

## 3. 逐檔加入、掃描、commit

```sh
git status --short
git add <檔案>          # 一個一個指定，看過每個檔案是什麼才加
sh .claude/skills/ship/scan.sh --staged
```

- 掃描命中（回傳 1）：停下，告訴作者命中什麼、在哪裡，修好再掃。找不到私人字詞清單（回傳 2）：停下，不 commit。
- 掃描通過才 commit。訊息第一行 `類型: 中文摘要`，類型照這次改動的內容（`feat`、`fix`、`perf`、`docs`、`chore`）；`release` 只用在版本分支的 PR 標題。結尾一行：
  ```
  Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
  ```
- 沒有改動要 commit（之前已經 commit 好）就跳過這步。

完成：`git status --short` 是空的（或只剩作者說不要放的檔案），commit 已建立。

## 4. push

```sh
sh .claude/skills/ship/scan.sh --unpushed
git push -u origin <分支>
```

完成：掃描通過，分支推上去了。

## 5. 開 PR

PR 標題就是 squash 合併後 main 上的那一個 commit 訊息：
- 快速分支：`類型: 中文摘要`。
- 版本分支：`release: vX.Y.Z，<這一批的摘要>`。

內文寫進 scratchpad 的檔案，格式：

```markdown
## 做了什麼

（每項一句；版本分支列出這一批的每件事）

## 怎麼驗證

（測試數、模擬器截圖、實機；沒驗證的寫明沒驗證）

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>

🤖 Generated with [Claude Code](https://claude.com/claude-code)
```

```sh
sh .claude/skills/ship/scan.sh --file <內文檔案>
gh pr create --base main --head <分支> --title "<標題>" --body-file <內文檔案>
```

這個分支已經有開著的 PR（`gh pr view <分支>` 查得到）：不重開，回報那個 PR，說明這次推上去的 commit 已經加進去。

完成：PR 的網址拿到了。

## 6. 回報

用繁體中文告訴作者：
- 做到第幾步；有開 PR 時給網址與標題、分支種類。
- commit 了哪些檔案、測試數、掃描結果。
- 下一步要作者決定的：合併（squash）；版本分支合併後要在 main 打 `vX.Y.Z`。
