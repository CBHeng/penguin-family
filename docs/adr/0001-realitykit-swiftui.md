---
status: proposed
date: 2026-11-04
---

# 用 RealityKit＋SwiftUI 開發，而不是 Flutter 或 Unity

作者有 Flutter 經驗，但 2.5D 箱庭若走真 3D，Flutter 的選項較弱：查到 Flame 只支援 2D（來源可信度低），flutter_scene 仍在 1.0 前。這款場景小、角色少，又有聊天介面、觸覺回饋和小工具，因此選用原生的 RealityKit＋SwiftUI，好處是不用跨語言橋接。Flutter 也有觸覺套件，小工具則要另寫原生設定，所以差距主要來自真 3D。SceneKit 已棄用，不採用。

這個決定是暫定的，目前有部分是排除法，因為 RealityKit 做遊戲的成熟度還沒驗證。S2 通過後改為 accepted；S2 卡住時，由作者決定是否改用 Unity（工具成熟、C# 接近 Java，但 App 較重，聊天介面和小工具也較麻煩）。S1 若改走紙片 2.5D，真 3D 的前提就變了，要重新檢視這個決定。

依據見 [asset-and-engine](../research/asset-and-engine.md)。
