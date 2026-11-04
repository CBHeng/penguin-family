# 架構

目前還沒有程式碼，這裡是規劃中的結構。實作後，以程式碼為準並更新這份文件。

```
penguin-family/
├─ Penguin.xcodeproj
├─ Penguin/
│  ├─ App/        SwiftUI 外殼、抱抱介面、Chat/ 聊天介面
│  ├─ World/      RealityKit 場景、鏡頭、企鵝實體
│  ├─ Behavior/   行為狀態機與隨機事件（純 Swift）
│  ├─ Soul/       角色聖經、台詞選擇、DialogueEngine
│  ├─ Memory/     本機關係狀態、事件紀錄、聊天內容與共同回憶（SwiftData）
│  ├─ Activity/   A3 才加入的步數連動
│  ├─ Feel/       觸覺與音效
│  └─ Resources/  CharacterPacks/<角色>/{bible.json, lines.json, model.usdz}、CharacterPacks/duo.json
├─ PenguinTests/  Behavior 與 Soul 的單元測試
├─ PenguinWidget/ A3 才加入
└─ backend/       B1 才加入的薄後端
```

## 模組邊界

- **`Behavior` 只輸出意圖，`World` 負責呈現。** `Behavior` 不匯入 RealityKit，所以可以單獨測試。日後改成紙片 2.5D，程式可以沿用；改用 Unity 要用 C# 重寫，但設計可以沿用。
- **`DialogueEngine` 是台詞來源的 protocol。** 路線一用 `ScriptedEngine`，路線二加 `CloudEngine`。決策原因見 [ADR 0002](adr/0002-hybrid-soul-engine.md)。
- **箱庭與聊天透過事件紀錄連接。** 箱庭寫入發生的事，聊天讀取後才能提到；聊天再把主人的心情和共同回憶寫回，影響箱庭。路線一就要記下事件，避免之後重工。
- **`CharacterPack` 把造型與個性資料化。** 換造型不用改程式，原因見 [ADR 0004](adr/0004-plush-likeness-private-use.md)。
- **`CharacterPacks/` 不進 git。** repo 是公開的，所以乾淨 clone 下來沒有角色包。單元測試用測試專用的假資料，不依賴這個資料夾。原因見 [ADR 0004](adr/0004-plush-likeness-private-use.md)。
- **人設是資料。** 台詞與個性放 JSON，作者不改程式也能調教。填好的角色聖經是權威來源（位置見[範本](characters/bible.md)），JSON 依它產生；內容有出入時，以角色聖經為準。兩隻共有的關係資料放 `duo.json`。
- **聊天內容與共同回憶由 `Memory` 管理，只存手機。** 後端只轉發，原因見 [ADR 0003](adr/0003-on-device-memory.md)。

## 測試

單元測試涵蓋行為狀態轉換、台詞選擇規則和 AI 失敗回退。
