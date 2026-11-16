import Foundation
import SwiftData
import Testing
@testable import PenguinFamily

/// 事件紀錄：每個測試用自己的記憶體資料庫，不碰手機上的資料。
@MainActor
struct EventLogTests {
    let container: ModelContainer
    let log: EventLog

    init() throws {
        container = try EventLog.makeContainer(inMemory: true)
        log = EventLog(context: container.mainContext)
    }

    @Test func startsEmpty() throws {
        #expect(try log.recent(limit: 10).isEmpty)
    }

    @Test func recordsTapWithPenguinAndTime() throws {
        let when = Date(timeIntervalSince1970: 1_000)
        try log.record(.ownerTapped, penguinID: "penguin-a", at: when)
        let records = try log.recent(limit: 10)
        #expect(records.count == 1)
        #expect(records[0].kind == .ownerTapped)
        #expect(records[0].penguinID == "penguin-a")
        #expect(records[0].occurredAt == when)
    }

    @Test func recentIsNewestFirstAndLimited() throws {
        for second in [3.0, 1.0, 2.0] {
            try log.record(.ownerTapped, penguinID: nil, at: Date(timeIntervalSince1970: second))
        }
        let times = try log.recent(limit: 2).map(\.occurredAt.timeIntervalSince1970)
        #expect(times == [3, 2])
    }

    @Test func survivesNewContext() throws {
        try log.record(.ownerTapped, penguinID: "penguin-a")
        // 已存檔：另開一個 context 也讀得到
        let other = EventLog(context: ModelContext(container))
        #expect(try other.recent(limit: 10).count == 1)
    }

    @Test func unknownKindReadsAsNil() {
        let record = EventRecord(kind: .ownerTapped, penguinID: nil, occurredAt: .now)
        record.kindRawValue = "somethingFromFutureVersion"
        #expect(record.kind == nil)
    }
}
