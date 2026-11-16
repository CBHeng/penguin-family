import Foundation
import Testing

/// `docs/code-map.md` 要和實際的程式檔一致：每個 `.swift` 檔都有列出，列出的檔案都存在。
///
/// 只檢查「有沒有列」，一句話的職責寫得對不對還是靠人（作者 2026-11-16 決定）。
/// 測試在模擬器上跑，模擬器讀得到 Mac 上的 repo；用這個測試檔的位置往上找到 repo 根目錄。
struct CodeMapTests {
    /// 這個檔案在 `<repo>/ios/PenguinFamilyTests/`，往上三層是 repo 根目錄。
    static let repoRoot = URL(filePath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    static let sourceFolders = ["ios/PenguinFamily", "ios/PenguinFamilyTests"]

    /// 實際存在的 `.swift` 檔名。
    static func swiftFiles() -> Set<String> {
        var names = Set<String>()
        for folder in sourceFolders {
            let enumerator = FileManager.default.enumerator(at: repoRoot.appending(path: folder),
                                                            includingPropertiesForKeys: nil)
            while let url = enumerator?.nextObject() as? URL {
                if url.pathExtension == "swift" { names.insert(url.lastPathComponent) }
            }
        }
        return names
    }

    /// 程式地圖裡提到的 `.swift` 檔名。
    static func listedFiles() throws -> Set<String> {
        let text = try String(contentsOf: repoRoot.appending(path: "docs/code-map.md"), encoding: .utf8)
        let pattern = try Regex("[A-Za-z0-9_]+\\.swift")
        return Set(text.matches(of: pattern).map { String(text[$0.range]) })
    }

    @Test func foundTheSourceFolders() {
        // 找不到程式檔代表路徑算錯了，下面兩個測試會變成什麼都沒檢查
        #expect(Self.swiftFiles().contains("CodeMapTests.swift"))
    }

    @Test func everySwiftFileIsListed() throws {
        let missing = Self.swiftFiles().subtracting(try Self.listedFiles()).sorted()
        #expect(missing.isEmpty, "這些檔案還沒列進 docs/code-map.md：\(missing)")
    }

    @Test func everyListedFileExists() throws {
        let gone = try Self.listedFiles().subtracting(Self.swiftFiles()).sorted()
        #expect(gone.isEmpty, "docs/code-map.md 列了已經不存在的檔案：\(gone)")
    }
}
