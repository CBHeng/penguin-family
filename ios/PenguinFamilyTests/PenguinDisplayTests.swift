import Foundation
import Testing
@testable import PenguinFamily

/// 顯示企鵝需要的部分：哈囉時間軸、轉成圖片、找角色包。只用假資料。
struct PenguinDisplayTests {
    // MARK: - 哈囉時間軸

    @Test func helloStartsAndEndsAtRest() {
        #expect(HelloMotion.frameCount == 56)
        #expect(HelloMotion.pose(frame: 0) == .rest)
        #expect(HelloMotion.pose(at: HelloMotion.duration) == .rest)
        #expect(HelloMotion.pose(frame: HelloMotion.frameCount + 10) == .rest)
    }

    @Test func helloRaisesArmAndTiltsHeadWhileWaving() {
        let pose = HelloMotion.pose(at: 1.0)
        #expect(pose.headDegrees == HelloMotion.headTilt)
        #expect(pose.squash == HelloMotion.squash)
        #expect(abs(pose.armDegrees - HelloMotion.armUp) <= HelloMotion.waveDegrees)
    }

    // MARK: - 轉成圖片

    @Test func parsesHexColors() {
        #expect(PixelColor(hex: "#DE382E") == PixelColor(hex: "#de382e"))
        #expect(PixelColor(hex: "#DE382E")?.red == 0xDE)
        #expect(PixelColor(hex: "#DE382E")?.green == 0x38)
        #expect(PixelColor(hex: "#DE382E")?.blue == 0x2E)
        #expect(PixelColor(hex: "DE382E") == nil)
        #expect(PixelColor(hex: "#DE38") == nil)
        #expect(PixelColor(hex: "#GG0000") == nil)
    }

    @Test func rgbaKeepsExactColorsAndTransparency() throws {
        let grid = PixelGrid(rows: ["R.", ".O"], empty: ".")
        let colors: [Character: PixelColor] = [
            "R": try #require(PixelColor(hex: "#FF0102")),
            "O": try #require(PixelColor(hex: "#030405")),
        ]
        #expect(PixelImage.rgba(grid, colors: colors) == [
            255, 1, 2, 255, 0, 0, 0, 0,
            0, 0, 0, 0, 3, 4, 5, 255,
        ])
    }

    @Test func rejectsInvalidPaletteColor() throws {
        let json = RigCompositorTests.fakeJSON.replacingOccurrences(of: "\"#FF0000\"", with: "\"red\"")
        let rig = try RigCompositorTests.decode(json)
        #expect(throws: CharacterRigError.invalidColor("red")) { try RigCompositor(rig: rig) }
    }

    // MARK: - 找角色包

    /// 在暫存資料夾建立假的 CharacterPacks.bundle；內容是 [資料夾名稱: rig.json 內容]，nil 表示沒有 rig.json。
    static func makeRoot(_ packs: [String: String?]) throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "PenguinDisplayTests-\(UUID().uuidString)")
            .appending(path: "CharacterPacks.bundle")
        for (name, rig) in packs {
            let dir = root.appending(path: name)
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            if let rig {
                try Data(rig.utf8).write(to: dir.appending(path: "rig.json"))
            }
        }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    @Test func noPacksMeansPlaceholder() throws {
        #expect(CharacterPackLibrary.loadFirst(in: nil) == nil)
        #expect(CharacterPackLibrary.loadFirst(in: try Self.makeRoot([:])) == nil)
    }

    @Test func listsOnlyFoldersWithRigSorted() throws {
        let root = try Self.makeRoot(["b": RigCompositorTests.fakeJSON, "a": RigCompositorTests.fakeJSON, "c": nil])
        #expect(CharacterPackLibrary.packs(in: root).map(\.lastPathComponent) == ["a", "b"])
    }

    @Test func skipsBrokenPackAndLoadsNext() throws {
        let root = try Self.makeRoot(["a": "{ not json", "b": RigCompositorTests.fakeJSON])
        let loaded = try #require(CharacterPackLibrary.loadFirst(in: root))
        #expect(loaded.id == "b")
        #expect(loaded.compositor.rig.canvas.width == 10)
    }

    @Test func allBrokenMeansPlaceholder() throws {
        let root = try Self.makeRoot(["a": "{ not json"])
        #expect(CharacterPackLibrary.loadFirst(in: root) == nil)
    }
}
