import Foundation
import Testing
@testable import PenguinFamily

/// 顯示企鵝需要的部分：哈囉時間軸、顏色、找角色包、灰色剪影。只用假資料。
struct PenguinDisplayTests {
    // MARK: - 哈囉時間軸

    @Test func helloStartsAndEndsAtRest() {
        #expect(HelloMotion.pose(at: 0) == .rest)
        #expect(HelloMotion.pose(at: HelloMotion.duration) == .rest)
        #expect(HelloMotion.pose(at: HelloMotion.duration + 10) == .rest)
        #expect(Motion.hello.duration == HelloMotion.duration)
    }

    @Test func helloRaisesArmAndTiltsHeadWhileWaving() {
        let pose = HelloMotion.pose(at: 1.0)
        #expect(pose.headDegrees == HelloMotion.headTilt)
        #expect(pose.squash == HelloMotion.squash)
        #expect(abs(pose.armDegrees - HelloMotion.armUp) <= HelloMotion.waveDegrees)
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
    static func makeRoot(_ packs: [String: String?]) throws -> URL {
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
        let raised = try #require(front.frontTransforms(HelloMotion.pose(at: 1))["arm"])
        let hand = raised.apply(arm.minX + (arm.maxX - arm.minX) / 2, arm.maxY)
        guard case let .ellipse(cx, cy, rx, ry) = front.parts["body"]?.silhouette.first else {
            Issue.record("身體應該是一個橢圓")
            return
        }
        let dx = (hand.x - cx) / rx, dy = (hand.y - cy) / ry
        #expect(dx * dx + dy * dy > 1)                            // 手尖在身體外面
    }
}
