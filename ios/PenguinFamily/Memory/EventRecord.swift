import Foundation
import SwiftData

/// 事件紀錄裡的一種事。
///
/// 存進資料庫的是 `rawValue`，改名會讓舊紀錄讀不到，所以只新增、不改既有的值。
nonisolated enum EventKind: String, Sendable, CaseIterable {
    /// 主人點了角色一下（不論牠當下有沒有回應）。
    case ownerTapped
}

/// 事件紀錄（Event Log）的一筆：箱庭裡發生過的一件事。只存在手機上（ADR 0003）。
@Model
nonisolated final class EventRecord {
    var occurredAt: Date
    /// `EventKind` 的 rawValue；存字串，之後新增種類不用遷移資料庫。
    var kindRawValue: String
    /// 和哪一隻角色有關（`CharacterID`，不分物種）；與特定角色無關時是 nil。
    /// 欄位名稱是 v0.0.8 以前留下來的，不改名：SwiftData 改名要遷移資料庫（ADR 0009）。
    var penguinID: String?

    init(kind: EventKind, characterID: String?, occurredAt: Date) {
        self.kindRawValue = kind.rawValue
        self.penguinID = characterID
        self.occurredAt = occurredAt
    }

    /// 這個版本不認得的種類（例如之後的版本寫入的）會是 nil。
    var kind: EventKind? { EventKind(rawValue: kindRawValue) }
}
