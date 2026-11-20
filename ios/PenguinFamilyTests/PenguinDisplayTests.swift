import Foundation
import Testing
@testable import PenguinFamily

/// 顯示企鵝需要的部分：哈囉時間軸、顏色、找角色包、灰色剪影。只用假資料。
struct PenguinDisplayTests {
    // MARK: - 哈囉時間軸

    @Test func helloStartsAndEndsAtRest() {
        let hello = HelloMotion.standard
        #expect(hello.pose(at: 0) == .rest)
        #expect(hello.pose(at: hello.duration) == .rest)
        #expect(hello.pose(at: hello.duration + 10) == .rest)
        #expect(hello.motion.duration == hello.duration)
        #expect(abs(hello.duration - 2.8) < 1e-9)                    // 作者定案的哈囉播 2.8 秒
    }

    @Test func helloRaisesArmAndTiltsHeadWhileWaving() {
        let hello = HelloMotion.standard
        let pose = hello.pose(at: 1.0)
        #expect(pose.headDegrees == hello.headTilt)
        #expect(pose.squash == hello.squash)
        #expect(abs(pose.armDegrees - hello.armUp) <= hello.waveDegrees)
    }

    // MARK: - 動作細節（作者 2026-11-19 決定：每隻各一份）

    /// 作者定案的那一份，寫成私有素材 repo 匯出的 `motion.json` 格式。
    static let motionJSON = """
        { "version": 1,
          "hello": { "raise": 0.35, "wave": 1.4, "lower": 0.35, "settle": 0.7,
                     "armUp": -140, "headTilt": -9, "waveDegrees": 8, "waveHz": 4, "squash": 0.94 },
          "walk": { "cycle": 1, "sway": 3, "lean": 0, "dip": 1, "armOpen": 12, "flap": 0,
                    "armBob": 1, "armBobSteps": 1, "stride": 2, "lift": 1 },
          "trot": { "cycle": 0.5, "sway": 2, "lean": 5, "dip": 1, "armOpen": 20, "flap": 8,
                    "armBob": 1, "armBobSteps": 2, "stride": 2, "lift": 1 } }
        """

    @Test func motionFileReadsAndRejectsNumbersThatMakeNoSense() throws {
        #expect(try PenguinMotions.decode(Data(Self.motionJSON.utf8)) == .standard)
        func problem(_ old: String, _ new: String) -> PenguinMotionsError? {
            let json = Self.motionJSON.replacingOccurrences(of: old, with: new)
            do {
                _ = try PenguinMotions.decode(Data(json.utf8))
                return nil
            } catch {
                return error as? PenguinMotionsError
            }
        }
        #expect(problem(#""version": 1"#, #""version": 2"#) == .unsupportedVersion(2))
        #expect(problem(#""raise": 0.35"#, #""raise": 0"#) == .invalid("hello.raise"))
        #expect(problem(#""squash": 0.94"#, #""squash": 0"#) == .invalid("hello.squash"))
        #expect(problem(#""cycle": 1,"#, #""cycle": 0,"#) == .invalid("walk.cycle"))
        #expect(problem(#""armBobSteps": 2"#, #""armBobSteps": 3"#) == .invalid("trot.armBobSteps"))
        #expect((try? PenguinMotions.decode(Data(#"{ "version": 1 }"#.utf8))) == nil)   // 少了欄位
    }

    @Test func packBringsItsOwnMotionsAndWander() throws {
        let fake = VectorRigTests.json
        let root = try Self.makeRoot(["a": fake, "b": fake, "c": fake])
        let wander = #"{ "version": 1, "pace": { "walk": 1, "trot": 0 }, "activities": [{ "id": "z", "kind": "zoneOut", "weight": 1, "cooldown": 0, "seconds": [1, 2] }] }"#
        let quick = Self.motionJSON.replacingOccurrences(of: #""wave": 1.4"#, with: #""wave": 0.4"#)
        try Data(quick.utf8).write(to: root.appending(path: "a/motion.json"))
        try Data(wander.utf8).write(to: root.appending(path: "a/wander.json"))
        try Data("{ not json".utf8).write(to: root.appending(path: "b/motion.json"))
        try Data("{ not json".utf8).write(to: root.appending(path: "b/wander.json"))
        let a = try CharacterPackLibrary.load(root.appending(path: "a"))
        #expect(a.motions.hello.wave == 0.4 && a.motions.walk == .standardWalk && a.motions.trot == .standardTrot)
        #expect(a.wander?.activities.map(\.id) == ["z"])
        // 壞掉或沒帶：改用預設，牠照樣上台
        for name in ["b", "c"] {
            let other = try CharacterPackLibrary.load(root.appending(path: name))
            #expect(other.motions == .standard && other.wander == nil, "\(name)")
        }
        #expect(CharacterPackLibrary.loadFamily(in: root).map { $0?.id } == ["a", "b"])
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
            .appending(path: "PenguinDisplayTests-\(UUID().uuidString)")
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

    @Test func noPacksMeansPlaceholders() throws {
        #expect(CharacterPackLibrary.loadFamily(in: nil).map { $0?.id } == [nil, nil])
        #expect(CharacterPackLibrary.loadFamily(in: try Self.makeRoot([:])).map { $0?.id } == [nil, nil])
    }

    @Test func listsOnlyFoldersWithVectorSorted() throws {
        let root = try Self.makeRoot(["b": VectorRigTests.json, "a": VectorRigTests.json, "c": nil])
        #expect(CharacterPackLibrary.packs(in: root).map(\.lastPathComponent) == ["a", "b"])
    }

    @Test func familyIsInPackOrderSkipsBrokenAndIgnoresExtra() throws {
        let fake = VectorRigTests.json
        let root = try Self.makeRoot(["c": fake, "a": fake, "b": "{ not json", "d": fake])
        let ids = CharacterPackLibrary.loadFamily(in: root).map { $0?.id }
        #expect(ids == ["a", "c"])      // 依名稱排序、跳過壞的 b、多的 d 不用
    }

    @Test func familyListDecidesWhoIsFirst() throws {
        let fake = VectorRigTests.json
        let packs = ["a": fake, "b": fake, "c": fake]
        // 清單列到的排前面、照清單的順序；沒列到的接在後面依名稱排；列了但沒有的資料夾不算
        let listed = try Self.makeRoot(packs, family: #"{ "version": 1, "order": ["c", "x", "a"] }"#)
        #expect(CharacterPackLibrary.packs(in: listed).map(\.lastPathComponent) == ["c", "a", "b"])
        #expect(CharacterPackLibrary.loadFamily(in: listed).map { $0?.id } == ["c", "a"])
        // 清單壞掉或版本不認得：當作沒有清單，依名稱排
        for broken in ["{ not json", #"{ "version": 2, "order": ["c"] }"#, #"{ "version": 1, "order": ["c", "c"] }"#] {
            let root = try Self.makeRoot(packs, family: broken)
            #expect(CharacterPackLibrary.packs(in: root).map(\.lastPathComponent) == ["a", "b", "c"], "\(broken)")
        }
    }

    @Test func familyLoadsInBackground() async throws {
        let root = try Self.makeRoot(["a": VectorRigTests.json])
        let family = await CharacterPackLibrary.loadFamilyInBackground(in: root)
        // 只有一個角色包：第一隻是它，第二隻是灰色剪影
        #expect(family.map { $0?.id } == ["a", nil])
        #expect(family[0]?.vector.front.canvas == VectorRig.Size(width: 20, height: 20))
    }

    // MARK: - 灰色剪影

    @Test func placeholderIsAFrontOnlySilhouetteThatCanWave() throws {
        let rig = VectorRig.placeholder
        #expect(Array(rig.facings.keys) == ["front"] && rig.mirrors.isEmpty)
        #expect(rig.walk("frontLeft") == nil)                     // 沒有斜向：走路時面向鏡頭
        // 站著時手藏在身體裡；哈囉時手轉出身體外
        let front = rig.front
        let body = try #require(front.parts["body"]?.silhouette.first?.bounds)
        let arm = try #require(front.parts["arm"]?.silhouette.first?.bounds)
        #expect(arm.minX > body.minX && arm.maxX < body.maxX && arm.minY > body.minY && arm.maxY < body.maxY)
        let raised = try #require(front.frontTransforms(HelloMotion.standard.pose(at: 1))["arm"])
        let hand = raised.apply(arm.minX + (arm.maxX - arm.minX) / 2, arm.maxY)
        guard case let .ellipse(cx, cy, rx, ry) = front.parts["body"]?.silhouette.first else {
            Issue.record("身體應該是一個橢圓")
            return
        }
        let dx = (hand.x - cx) / rx, dy = (hand.y - cy) / ry
        #expect(dx * dx + dy * dy > 1)                            // 手尖在身體外面
    }
}
