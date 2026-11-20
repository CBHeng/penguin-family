import Foundation
import SwiftData
import os

/// 事件紀錄：箱庭寫入發生的事，之後聊天讀取，才能提到剛發生的事。
///
/// - 只存在手機上，不同步到雲端（ADR 0003）；換機與備份到 B1 再決定。
/// - **在背景寫入**（作者 2026-11-16 決定）：點擊反應與遊戲迴圈永遠不等磁碟。每件事都在背景存一次，不批次，所以不會少記。
/// - 用 `open(_:)` 在背景建立；載入畫面期間呼叫 `warmUp()` 先把資料庫打開（用首次載入換順暢）。
/// - 外面拿到的是 `LoggedEvent` 這種複製出來的值；資料庫的物件不能離開這個 actor。
@ModelActor
actor EventLog {
    private static let log = Logger(subsystem: "PenguinFamily", category: "Memory")

    /// App 用的資料庫設定：存在手機上，明確關閉 CloudKit 同步。
    static func makeContainer(inMemory: Bool = false) throws -> ModelContainer {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: inMemory, cloudKitDatabase: .none)
        return try ModelContainer(for: EventRecord.self, configurations: configuration)
    }

    /// 在背景建立。從主執行緒直接用 `EventLog(modelContainer:)` 建立時，它的工作會跟著在主執行緒做
    /// （2026-11-16 在模擬器實測），背景寫入就失效了，所以一律從這裡建立。
    static func open(_ container: ModelContainer) async -> EventLog {
        await Task.detached(priority: .userInitiated) { EventLog(modelContainer: container) }.value
    }

    /// 先讀一次，讓資料庫真正打開；在載入畫面期間呼叫。
    func warmUp() {
        do {
            _ = try modelContext.fetchCount(FetchDescriptor<EventRecord>())
        } catch {
            Self.log.error("事件紀錄預熱失敗：\(String(describing: error), privacy: .private)")
        }
    }

    /// 記下一件事並存檔。失敗只寫日誌，不影響角色；回傳是否成功。
    @discardableResult
    func record(_ kind: EventKind, characterID: String?, at date: Date = .now) -> Bool {
        modelContext.insert(EventRecord(kind: kind, characterID: characterID, occurredAt: date))
        do {
            try modelContext.save()
            return true
        } catch {
            // 錯誤內容可能含角色 id，系統日誌預設遮蔽
            Self.log.error("事件紀錄寫入失敗：\(String(describing: error), privacy: .private)")
            return false
        }
    }

    /// 最近發生的事，新的在前。
    func recent(limit: Int) throws -> [LoggedEvent] {
        var descriptor = FetchDescriptor<EventRecord>(sortBy: [SortDescriptor(\.occurredAt, order: .reverse)])
        descriptor.fetchLimit = limit
        return try modelContext.fetch(descriptor).map {
            LoggedEvent(occurredAt: $0.occurredAt, kind: $0.kind, characterID: $0.penguinID)
        }
    }

    /// 測試用：確認寫入不在主執行緒上做。
    func isRunningOnMainThread() -> Bool { Thread.isMainThread }
}

/// 從事件紀錄讀出來的一件事（複製出來的值，可以在任何地方使用）。
nonisolated struct LoggedEvent: Equatable, Sendable {
    let occurredAt: Date
    /// 這個版本不認得的種類是 nil。
    let kind: EventKind?
    let characterID: String?
}
