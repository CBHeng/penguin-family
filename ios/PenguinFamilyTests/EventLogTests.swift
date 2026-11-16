import Foundation
import SwiftData
import Testing
@testable import PenguinFamily

/// 事件紀錄：每個測試用自己的記憶體資料庫，不碰手機上的資料。
struct EventLogTests {
    static func open() async throws -> (ModelContainer, EventLog) {
        let container = try EventLog.makeContainer(inMemory: true)
        return (container, await EventLog.open(container))
    }

    @Test func startsEmpty() async throws {
        let (_, log) = try await Self.open()
        await log.warmUp()
        #expect(try await log.recent(limit: 10).isEmpty)
    }

    @Test func recordsTapWithPenguinAndTime() async throws {
        let (_, log) = try await Self.open()
        let when = Date(timeIntervalSince1970: 1_000)
        #expect(await log.record(.ownerTapped, penguinID: "penguin-a", at: when))
        let records = try await log.recent(limit: 10)
        #expect(records == [LoggedEvent(occurredAt: when, kind: .ownerTapped, penguinID: "penguin-a")])
    }

    @Test func recentIsNewestFirstAndLimited() async throws {
        let (_, log) = try await Self.open()
        for second in [3.0, 1.0, 2.0] {
            await log.record(.ownerTapped, penguinID: nil, at: Date(timeIntervalSince1970: second))
        }
        let times = try await log.recent(limit: 2).map(\.occurredAt.timeIntervalSince1970)
        #expect(times == [3, 2])
    }

    @Test func savedRecordsAreVisibleToAnotherLog() async throws {
        let (container, log) = try await Self.open()
        await log.record(.ownerTapped, penguinID: "penguin-a")
        // 已存檔：同一個資料庫另開一個也讀得到
        let other = await EventLog.open(container)
        #expect(try await other.recent(limit: 10).count == 1)
    }

    @Test func writesOffTheMainThread() async throws {
        let (_, log) = try await Self.open()
        #expect(await !log.isRunningOnMainThread())
    }

    @Test func unknownKindReadsAsNil() {
        let record = EventRecord(kind: .ownerTapped, penguinID: nil, occurredAt: .now)
        record.kindRawValue = "somethingFromFutureVersion"
        #expect(record.kind == nil)
    }
}
