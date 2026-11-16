import Foundation
import SwiftData

/// 事件紀錄：箱庭寫入發生的事，之後聊天讀取，才能提到剛發生的事。
///
/// 只存在手機上，不同步到雲端（ADR 0003）；換機與備份到 B1 再決定。
struct EventLog {
    let context: ModelContext

    /// App 用的資料庫設定：存在手機上，明確關閉 CloudKit 同步。
    static func makeContainer(inMemory: Bool = false) throws -> ModelContainer {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: inMemory, cloudKitDatabase: .none)
        return try ModelContainer(for: EventRecord.self, configurations: configuration)
    }

    func record(_ kind: EventKind, penguinID: String?, at date: Date = .now) throws {
        context.insert(EventRecord(kind: kind, penguinID: penguinID, occurredAt: date))
        try context.save()
    }

    /// 最近發生的事，新的在前。
    func recent(limit: Int) throws -> [EventRecord] {
        var descriptor = FetchDescriptor<EventRecord>(sortBy: [SortDescriptor(\.occurredAt, order: .reverse)])
        descriptor.fetchLimit = limit
        return try context.fetch(descriptor)
    }
}
