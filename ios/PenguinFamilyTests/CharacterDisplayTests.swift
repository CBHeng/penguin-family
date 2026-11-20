import Foundation
import Testing
@testable import PenguinFamily

/// 載入角色需要的部分：每隻自己的動作與閒晃、顏色、找角色包與名單（ADR 0009）、灰色剪影。只用假資料。
struct CharacterDisplayTests {
    // MARK: - 每隻自己的動作與閒晃（作者 2026-11-19 決定：每隻各一份）

    @Test func packBringsItsOwnMotionsAndWander() throws {
        let fake = VectorRigTests.walkingJSON
        let root = try Self.makeRoot(["a": fake, "b": fake, "c": fake, "d": VectorRigTests.json])
        let wander = #"{ "version": 1, "pace": { "walk": 1, "trot": 0 }, "activities": [{ "id": "z", "kind": "zoneOut", "weight": 1, "cooldown": 0, "seconds": [1, 2] }] }"#
        try Data(MotionClipTests.json.utf8).write(to: root.appending(path: "a/motion.json"))
        try Data(wander.utf8).write(to: root.appending(path: "a/wander.json"))
        try Data("{ not json".utf8).write(to: root.appending(path: "b/motion.json"))
        try Data("{ not json".utf8).write(to: root.appending(path: "b/wander.json"))
        try Data(MotionClipTests.json.utf8).write(to: root.appending(path: "d/motion.json"))
        let a = try CharacterPackLibrary.load(root.appending(path: "a"))
        #expect(a.motions == (try MotionClipTests.motions()))
        #expect(a.wander?.activities.map(\.id) == ["z"] && a.wander?.pace == .init(slow: 1, fast: 0))   // 第 1 版的閒晃也讀得懂
        // 壞掉或沒帶：那一份是 nil，牠照樣上台
        for name in ["b", "c"] {
            let other = try CharacterPackLibrary.load(root.appending(path: name))
            #expect(other.motions == nil && other.wander == nil, "\(name)")
        }
        // 動作的片段對不上造型（只有正面的造型，片段卻有斜向）：當作沒帶
        #expect(try CharacterPackLibrary.load(root.appending(path: "d")).motions == nil)
    }

    // MARK: - 顏色

    @Test func parsesHexColors() {
        #expect(RGBColor(hex: "#DE382E") == RGBColor(hex: "#de382e"))
        #expect(RGBColor(hex: "#DE382E")?.red == 0xDE)
        #expect(RGBColor(hex: "#DE382E")?.green == 0x38)
        #expect(RGBColor(hex: "#DE382E")?.blue == 0x2E)
        #expect(RGBColor(hex: "DE382E") == nil)
        #expect(RGBColor(hex: "#DE38") == nil)
        #expect(RGBColor(hex: "#GG0000") == nil)
    }

    // MARK: - 找角色包

    /// 在暫存資料夾建立假的 CharacterPacks.bundle；內容是 [資料夾名稱: vector.json 內容]，nil 表示沒有 vector.json。
    /// `family` 是根目錄的 `family.json` 內容（一家的順序），nil 表示沒有這個檔。
    static func makeRoot(_ packs: [String: String?], family: String? = nil) throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "CharacterDisplayTests-\(UUID().uuidString)")
            .appending(path: "CharacterPacks.bundle")
        for (name, vector) in packs {
            let dir = root.appending(path: name)
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            if let vector {
                try Data(vector.utf8).write(to: dir.appending(path: "vector.json"))
            }
        }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        if let family {
            try Data(family.utf8).write(to: root.appending(path: CharacterPackLibrary.familyFile))
        }
        return root
    }

    static func ids(_ family: [FamilyMember]) -> [String] { family.map(\.id.rawValue) }
    static func loaded(_ family: [FamilyMember]) -> [String?] { family.map { $0.character?.id } }

    @Test func noPacksMeansTheDefaultFamilyOfPlaceholders() throws {
        // 沒有名單：預設的一家（兩隻企鵝的位置），填不滿的是灰色剪影
        for family in [CharacterPackLibrary.loadFamily(in: nil), CharacterPackLibrary.loadFamily(in: try Self.makeRoot([:]))] {
            #expect(Self.ids(family) == ["placeholder-1", "placeholder-2"])
            #expect(Self.loaded(family) == [nil, nil] && family.allSatisfy { $0.species == .penguin })
        }
    }

    @Test func listsOnlyFoldersWithVectorSorted() throws {
        let root = try Self.makeRoot(["b": VectorRigTests.json, "a": VectorRigTests.json, "c": nil])
        #expect(CharacterPackLibrary.packs(in: root).map(\.lastPathComponent) == ["a", "b"])
    }

    @Test func withoutAListPacksFillTheDefaultFamilyByName() throws {
        let fake = VectorRigTests.json
        let root = try Self.makeRoot(["c": fake, "a": fake, "b": "{ not json", "d": fake])
        let family = CharacterPackLibrary.loadFamily(in: root)
        #expect(Self.loaded(family) == ["a", "c"])      // 依名稱排序、跳過壞的 b、多的 d 不用
        #expect(Self.ids(family) == ["a", "c"])
    }

    @Test func theListDecidesWhoIsInTheFamilyAndWhatTheyAre() throws {
        // ADR 0009：名單決定幾隻、順序與物種；名單上有、角色包沒有或壞掉的照樣在（替身），沒列的不用
        let fake = VectorRigTests.json
        let packs: [String: String?] = ["a": fake, "b": fake, "c": fake, "e": "{ not json"]
        let list = #"{ "version": 2, "members": [{ "id": "c", "species": "penguin" }, { "id": "x", "species": "shark" }, { "id": "a", "species": "penguin" }, { "id": "e", "species": "penguin" }] }"#
        let root = try Self.makeRoot(packs, family: list)
        let family = CharacterPackLibrary.loadFamily(in: root)
        #expect(Self.ids(family) == ["c", "x", "a", "e"])
        #expect(Self.loaded(family) == ["c", nil, "a", nil])
        #expect(family.map(\.species.rawValue) == ["penguin", "shark", "penguin", "penguin"])
        #expect(CharacterPackLibrary.packs(in: root).map(\.lastPathComponent) == ["c", "a", "e", "b"])   // 名單的先、其餘依名稱
        // 第 1 版（只有順序）也讀得懂，每隻是企鵝
        let old = try Self.makeRoot(packs, family: #"{ "version": 1, "order": ["c", "a"] }"#)
        #expect(Self.ids(CharacterPackLibrary.loadFamily(in: old)) == ["c", "a"])
        #expect(CharacterPackLibrary.loadFamily(in: old).allSatisfy { $0.species == .penguin })
        // 名單有三隻就是三隻：程式裡沒有隻數
        let three = try Self.makeRoot(packs, family: #"{ "version": 2, "members": [{ "id": "a", "species": "penguin" }, { "id": "b", "species": "penguin" }, { "id": "c", "species": "penguin" }] }"#)
        #expect(Self.loaded(CharacterPackLibrary.loadFamily(in: three)) == ["a", "b", "c"])
    }

    @Test func brokenListMeansNoList() throws {
        let fake = VectorRigTests.json
        let packs: [String: String?] = ["a": fake, "b": fake, "c": fake]
        for broken in ["{ not json", #"{ "version": 3, "order": ["c"] }"#, #"{ "version": 1, "order": ["c", "c"] }"#,
                       #"{ "version": 2, "members": [] }"#, #"{ "version": 2, "order": ["c"] }"#,
                       #"{ "version": 2, "members": [{ "id": "../a", "species": "penguin" }] }"#] {
            let root = try Self.makeRoot(packs, family: broken)
            #expect(CharacterPackLibrary.roster(in: root) == nil, "\(broken)")
            #expect(CharacterPackLibrary.packs(in: root).map(\.lastPathComponent) == ["a", "b", "c"], "\(broken)")
            #expect(Self.loaded(CharacterPackLibrary.loadFamily(in: root)) == ["a", "b"], "\(broken)")
        }
    }

    @Test func familyLoadsInBackground() async throws {
        let root = try Self.makeRoot(["a": VectorRigTests.json])
        let family = await CharacterPackLibrary.loadFamilyInBackground(in: root)
        // 只有一個角色包：第一隻是它，第二隻是灰色剪影
        #expect(Self.ids(family) == ["a", "placeholder-2"])
        #expect(family[0].character?.vector.front.canvas == VectorRig.Size(width: 20, height: 20))
    }

    // MARK: - 灰色剪影

    @Test func placeholderIsAFrontOnlySilhouette() {
        let rig = VectorRig.placeholder
        #expect(Array(rig.facings.keys) == ["front"] && rig.mirrors.isEmpty)
        #expect(rig.look("frontLeft") == nil)                     // 沒有斜向：走路時面向鏡頭
    }
}
