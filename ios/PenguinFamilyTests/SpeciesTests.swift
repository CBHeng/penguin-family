import CoreGraphics
import Foundation
import Testing
@testable import PenguinFamily

/// 不分物種（ADR 0009）：一個只在測試裡用的假物種（鯊魚：沒有手腳，部件是尾巴、身體、鰭），
/// 從讀名單與角色包、替身、上台、被點哈囉、移動，到產生繪製清單，App 不改程式就能跑完。
@MainActor
struct SpeciesTests {
    /// 假鯊魚的一個方向：比假企鵝高、瘦（14×30），腳底在 (7, 29)。
    static func facing() -> String {
        func part(_ name: String, _ e: [Double], pivot: (Double, Double)) -> String {
            let shape = "{\"ellipse\": [\(e.map { "\($0)" }.joined(separator: ", "))]}"
            return "\"\(name)\": {\"pivot\": {\"x\": \(pivot.0), \"y\": \(pivot.1)}, \"silhouette\": [\(shape)], "
                + "\"layers\": [{\"fill\": \"#7d93ad\", \"shapes\": [\(shape)]}]}"
        }
        let parts = [
            part("tail", [7, 25, 3, 4], pivot: (7, 22)),
            part("body", [7, 15, 5, 12], pivot: (7, 29)),
            part("fin", [9, 8, 2, 3], pivot: (8, 10)),
        ].joined(separator: ", ")
        return """
        {"canvas": {"width": 14, "height": 30}, "feet": {"x": 7, "y": 29}, "drawOrder": ["tail", "body", "fin"], "parts": {\(parts)}}
        """
    }

    /// 假鯊魚的造型：畫好正面與左前，右前由左前翻轉。
    static let sharkJSON = """
    {"format": 1, "outline": {"color": "#40506a", "width": 0.75},
     "facings": {"front": \(facing()), "frontLeft": \(facing())},
     "mirrors": {"frontRight": {"of": "frontLeft", "drawOrder": ["tail", "body", "fin"], "shift": {}}}}
    """

    /// 假鯊魚的動作：哈囉是擺尾巴 1 秒（轉向正面）；慢的時候一秒 0.4 格、尾巴左右擺、鰭上下動；快的只有速度。
    static let sharkMotionJSON = """
    { "version": 2,
      "motions": { "hello": { "duration": 1, "facing": "front", "clips": { "front": {
          "tail": [[0, 0, 1, 1, 0, 0], [0.5, 25, 1, 1, 0, 0], [1, 0, 1, 1, 0, 0]] } } } },
      "gaits": {
        "slow": { "tilesPerSecond": 0.4, "cycle": 1, "clips": { "frontLeft": {
            "tail": [[0, -10, 1, 1, 0, 0], [0.5, 10, 1, 1, 0, 0]], "fin": [[0, 0, 1, 1, 0, 0], [0.5, 0, 1, 1, 0, -0.5]] } } },
        "fast": { "tilesPerSecond": 0.8, "cycle": 0.5 } } }
    """

    /// 名單：一隻企鵝、兩隻鯊魚（第二隻鯊魚還沒有角色包）。
    static let familyJSON = """
    { "version": 2, "members": [{ "id": "a", "species": "penguin" }, { "id": "s", "species": "shark" },
                                { "id": "t", "species": "shark" }] }
    """

    static func family() throws -> [FamilyMember] {
        let root = try CharacterDisplayTests.makeRoot(["a": VectorRigTests.walkingJSON, "s": sharkJSON], family: familyJSON)
        try Data(MotionClipTests.json.utf8).write(to: root.appending(path: "a/motion.json"))
        try Data(sharkMotionJSON.utf8).write(to: root.appending(path: "s/motion.json"))
        return CharacterPackLibrary.loadFamily(in: root)
    }

    /// 繪製清單裡某一隻用哪個方向的圖、每個部件的矩陣。
    static func drawn(_ list: DrawList, _ id: CharacterID) -> (look: String, parts: [DrawList.Part])? {
        for case .character(id, let look, let parts) in list.items { return (look, parts) }
        return nil
    }

    @Test func rosterBringsBothSpeciesAndTheStandInBorrowsTheSameSpecies() throws {
        let family = try Self.family()
        #expect(family.map(\.id.rawValue) == ["a", "s", "t"])
        #expect(family.map(\.species.rawValue) == ["penguin", "shark", "shark"])
        #expect(family[1].character?.motions != nil)                                  // 鯊魚的片段對得上牠的造型
        #expect(family[2].character == nil)
        let cast = RoomScene.Member.cast(family, defaultWander: nil)
        // 第二隻鯊魚沒有角色包：借第一隻鯊魚（不是企鵝）的形狀塗灰，動作也用牠的
        #expect(cast[2].vector.outline.color == VectorRig.placeholderOutline)
        #expect(cast[2].vector.front.drawOrder == ["tail", "body", "fin"])
        #expect(cast[2].motions == cast[1].motions)
        #expect(cast[1].vector.bodyCenterAboveFeet == 14)                             // 鏡頭看牠的身體中央：比企鵝高
    }

    @Test func aSpeciesWithoutArmsOrFeetRunsEndToEnd() throws {
        let family = try Self.family()
        let ids = family.map(\.id)
        let scene = RoomScene(room: .indoor, cast: RoomScene.Member.cast(family, defaultWander: nil),
                              start: GameView.startPositions(ids, in: .indoor), seed: 1, now: 0)
        scene.builder.resize(viewport: CGSize(width: 402, height: 874), displayScale: 3)
        let runner = scene.runner
        func list(at now: Double) throws -> DrawList {
            try #require(scene.builder.build(previous: runner.previous, current: runner.current,
                                             at: runner.renderTime(at: now), now: now).drawList)
        }
        runner.advance(to: 0.05)
        #expect(runner.current.characters.map(\.id) == ids)                          // 三隻都上台，不疊在一起
        #expect(Set(runner.current.characters.map { Tile(containing: $0.position) }).count == 3)

        // 主人點鯊魚：照牠自己的動作資料哈囉（擺尾巴），播 1 秒。閒著的時候，點擊在現在的時間生效
        let shark = ids[1]
        runner.send(.ownerTapped(shark, at: .distantPast))
        RoomSceneTests.play(runner, from: 0.05, until: 0.1)
        guard case .motion(.hello, let since)? = runner.current.character(shark)?.activity else {
            Issue.record("鯊魚沒有哈囉")
            return
        }
        RoomSceneTests.play(runner, from: 0.1, until: since + 0.6)       // 像遊戲迴圈一樣每秒 60 次推進
        let waving = try #require(Self.drawn(try list(at: since + 0.6), shark))
        #expect(waving.look == "front" && waving.parts.map(\.name) == ["tail", "body", "fin"])
        let body = try #require(waving.parts.first { $0.name == "body" }).transform
        let tail = try #require(waving.parts.first { $0.name == "tail" }).transform
        #expect(tail.a != body.a)                                                     // 尾巴轉了，身體在原位
        #expect(RoomSceneTests.play(runner, from: since + 0.6, until: since + 1.2).contains(.finished(shark)))

        // 要牠慢慢往左前走：一秒 0.4 格（牠自己的速度），用左前的圖，尾巴與鰭照片段動
        let start = try #require(runner.current.character(shark)).position
        runner.send(.input(shark, .moveRequested(to: Tile(i: 5, j: 6), pace: .slow)))
        let walkingAt = since + 2.2
        RoomSceneTests.play(runner, from: since + 1.2, until: walkingAt)
        let now = try #require(runner.current.character(shark))
        guard case .moving(.slow, let elapsed) = now.activity else {
            Issue.record("鯊魚沒有在移動：\(now.activity)")
            return
        }
        #expect(now.facing == .frontLeft && abs(now.position.j - (start.j + 0.4 * elapsed)) < 1e-9)
        let walking = try #require(Self.drawn(try list(at: walkingAt), shark))
        #expect(walking.look == "frontLeft")
        #expect(Set(walking.parts.map(\.name)) == ["tail", "body", "fin"])
        // 還沒有角色包的第二隻鯊魚（替身）也畫得出來，用借來的圖
        #expect(Self.drawn(try list(at: walkingAt), ids[2])?.look == "front")
    }
}
