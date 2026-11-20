import os

/// 量效能用的標記（signpost）：在 Instruments 的 Points of Interest 看每一步花多久。
///
/// 為了追實機上偶發的主執行緒變慢（2026-11-16，見 TASKS）。標記只寫步驟名稱與時間長短，不含主人的資料。
/// 沒在錄的時候系統幾乎不做事（推論）；正式版也保留，之後量效能都用得到。
///
/// 標記的步驟：
/// - 主執行緒：`frame` 是遊戲迴圈的一格；`wake` 從暫停醒來（附暫停了幾毫秒）；`pause` 暫停；
///   `prepare` 畫面準備（內插、姿勢、排序）；`draw` 畫一格，其中 `acquireDrawable` 是等系統給畫布，`encode` 是送出貼圖指令；
///   `tap` 點擊的判斷與處理。
/// - 模擬的執行緒：`simulate` 是一次推進（跑到現在的節拍數）。和主執行緒的標記同時發生、互不等待（ADR 0008）。
nonisolated enum PerfSignposts {
    static let signposter = OSSignposter(subsystem: "PenguinFamily", category: .pointsOfInterest)

    /// 包住一段工作，記下它花多久。
    @inline(__always)
    static func measure<T>(_ name: StaticString, _ work: () throws -> T) rethrows -> T {
        let state = signposter.beginInterval(name)
        defer { signposter.endInterval(name, state) }
        return try work()
    }
}
