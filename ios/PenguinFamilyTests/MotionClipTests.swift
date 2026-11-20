import Foundation
import Testing
@testable import PenguinFamily

/// 動作資料與播放器（ADR 0009）：片段的關鍵影格與內插、一次性與循環、`motion.json` 的讀檔與檢查、
/// 片段要對得上造型、灰色剪影的哈囉。只用假資料（`VectorRigTests` 的 20×20 假角色）。
struct MotionClipTests {
    /// 假角色的動作資料（第 2 版）：哈囉舉手、歪頭；慢、快兩種步態在左前、左後各一段循環（身體左右擺、近的腳前後）。
    static let json = """
        { "version": 2,
          "motions": { "hello": { "duration": 2, "facing": "front", "clips": { "front": {
              "arm": [[0, 0, 1, 1, 0, 0], [0.5, -140, 1, 1, 0, 0], [1.5, -140, 1, 1, 0, 0], [2, 0, 1, 1, 0, 0]],
              "head": [[0, 0, 1, 1, 0, 0], [0.5, -9, 1, 1, 0, 0.5], [2, 0, 1, 1, 0, 0]] } } } },
          "gaits": {
            "slow": { "tilesPerSecond": 0.5, "cycle": 1, "clips": {
              "frontLeft": { "body": [[0, -3, 1, 1, 0, 0], [0.5, 3, 1, 1, 0, 1]], "nearFoot": [[0, 0, 1, 1, -1, 0], [0.5, 0, 1, 1, 1, 0]] },
              "backLeft": { "body": [[0, -3, 1, 1, 0, 0], [0.5, 3, 1, 1, 0, 1]] } } },
            "fast": { "tilesPerSecond": 1, "cycle": 0.5, "clips": {
              "frontLeft": { "body": [[0, -2, 1, 1, 0, 0], [0.25, 2, 1, 1, 0, 1]] } } } } }
        """

    static func motions(_ text: String = json) throws -> CharacterMotions {
        try CharacterMotions.decode(Data(text.utf8))
    }

    static func key(_ t: Double, _ rotate: Double, x: Double = 0) -> MotionClip.Key {
        .init(time: t, pose: PartPose(rotate: rotate, x: x))
    }

    // MARK: - 播放器

    @Test func keyTimesGiveTheKeyValuesExactly() {
        let keys = [Self.key(0, 0), Self.key(0.1, 7.3, x: 0.3), Self.key(0.2, -2)]
        for key in keys {
            #expect(MotionClip.pose(of: keys, at: key.time, cycle: nil) == key.pose)
        }
    }

    @Test func interpolatesBetweenKeysTheShortWayAround() {
        let keys = [Self.key(0, 0, x: 0), Self.key(1, 40, x: 2)]
        let half = MotionClip.pose(of: keys, at: 0.25, cycle: nil)
        #expect(abs(half.rotate - 10) < 1e-12 && abs(half.x - 0.5) < 1e-12)
        // 170 度到 -170 度：往近的那邊轉（經過 180），不是倒轉 340 度
        let wrap = [Self.key(0, 170), Self.key(1, -170)]
        #expect(abs(MotionClip.pose(of: wrap, at: 0.5, cycle: nil).rotate - 180) < 1e-9)
    }

    @Test func oneShotHoldsTheEnds() {
        let keys = [Self.key(0.5, 10), Self.key(1, 20)]
        #expect(MotionClip.pose(of: keys, at: 0, cycle: nil).rotate == 10)       // 第一格之前：第一格
        #expect(MotionClip.pose(of: keys, at: 5, cycle: nil).rotate == 20)       // 最後一格之後：最後一格
        #expect(MotionClip.pose(of: [], at: 1, cycle: nil) == .rest)
    }

    @Test func loopWrapsBackToTheFirstKey() {
        let keys = [Self.key(0, 0), Self.key(0.5, 10)]
        #expect(MotionClip.pose(of: keys, at: 1.5, cycle: 1).rotate == 10)                       // 1.5 秒 = 第二圈的 0.5 秒
        #expect(abs(MotionClip.pose(of: keys, at: 0.75, cycle: 1).rotate - 5) < 1e-12)           // 最後一格接回第一格
        #expect(abs(MotionClip.pose(of: keys, at: 2.75, cycle: 1).rotate - 5) < 1e-12)
        // 第一格不在 0 秒：0 秒是上一圈最後一格與這一圈第一格之間
        let late = [Self.key(0.25, 0), Self.key(0.75, 10)]
        #expect(abs(MotionClip.pose(of: late, at: 0, cycle: 1).rotate - 5) < 1e-12)
    }

    // MARK: - motion.json

    @Test func readsTheMotionFile() throws {
        let motions = try Self.motions()
        let hello = try #require(motions.motion(named: "hello"))
        #expect(hello.duration == 2 && hello.facing == .front)
        #expect(hello.clips["front"]?.tracks["arm"]?.count == 4)
        #expect(motions.gait(for: .slow).tilesPerSecond == 0.5 && motions.gait(for: .fast).cycle == 0.5)
        #expect(motions.gait(for: .fast).clips["backLeft"] == nil)                  // 沒有的方向：那個方向不動手腳
        #expect(motions.motion(named: "doze") == nil)
        // 片段播到某一刻
        let arm = try #require(hello.clips["front"]?.poses(at: 1)["arm"])
        #expect(arm.rotate == -140)
    }

    @Test func rejectsMotionFilesThatMakeNoSense() throws {
        func problem(_ old: String, _ new: String) -> CharacterMotionsError? {
            do {
                _ = try Self.motions(Self.json.replacingOccurrences(of: old, with: new))
                return nil
            } catch {
                return error as? CharacterMotionsError
            }
        }
        #expect(problem(#""version": 2"#, #""version": 1"#) == .unsupportedVersion(1))
        #expect(problem(#""duration": 2"#, #""duration": 0"#) == .invalid("hello.duration"))
        // 關鍵影格的時間要由小到大、在動作的長度裡
        #expect(problem("[0.5, -140, 1, 1, 0, 0]", "[0, -140, 1, 1, 0, 0]") == .invalid("hello.front.arm"))
        #expect(problem("[2, 0, 1, 1, 0, 0]]", "[2.5, 0, 1, 1, 0, 0]]") == .invalid("hello.front.arm"))
        // 循環的關鍵影格不能在循環的結尾（那一刻就是第一格）
        #expect(problem("[0.25, 2, 1, 1, 0, 1]", "[0.5, 2, 1, 1, 0, 1]") == .invalid("fast.frontLeft.body"))
        #expect(problem("[0.5, -9, 1, 1, 0, 0.5]", "[0.5, -9, 0, 1, 0, 0.5]") == .invalid("hello.front.head"))   // 縮放要大於 0
        #expect(problem(#""tilesPerSecond": 1"#, #""tilesPerSecond": 0"#) == .invalid("fast.tilesPerSecond"))
        // 關鍵影格少了數字、少了步態：讀不懂
        #expect((try? Self.motions(Self.json.replacingOccurrences(of: "[0.5, -9, 1, 1, 0, 0.5]", with: "[0.5, -9, 1, 1, 0]"))) == nil)
        #expect((try? Self.motions(#"{ "version": 2, "gaits": { "slow": { "tilesPerSecond": 1, "cycle": 1 } } }"#)) == nil)
        // 只有速度、沒有片段也可以
        #expect((try? Self.motions(#"{ "version": 2, "gaits": { "slow": { "tilesPerSecond": 1, "cycle": 1 }, "fast": { "tilesPerSecond": 2, "cycle": 1 } } }"#)) != nil)
    }

    @Test func clipsMustMatchTheRig() throws {
        let motions = try Self.motions()
        #expect(motions.problem(with: try VectorRigTests.rig(VectorRigTests.walkingJSON)) == nil)
        // 只有正面的造型：步態的斜向片段沒有地方用
        #expect(motions.problem(with: try VectorRigTests.rig()) == "fast.frontLeft")
        // 造型沒有片段用到的部件
        let finned = try VectorRigTests.rig(VectorRigTests.walkingJSON.replacingOccurrences(of: "\"arm\"", with: "\"fin\""))
        #expect(motions.problem(with: finned) == "hello.front.arm")
    }

    // MARK: - 沒有動作資料時

    @Test func stillOnlyMovesAtTheDefaultSpeed() throws {
        let still = CharacterMotions.still
        try still.validate()
        #expect(still.motions.isEmpty)
        #expect(still.gait(for: .slow).tilesPerSecond == 0.5 && still.gait(for: .fast).tilesPerSecond == 1)
        #expect(still.gait(for: .slow).clips.isEmpty)
    }

    @Test func placeholderWavesFromTheFront() throws {
        let motions = CharacterMotions.placeholder
        try motions.validate()
        let rig = VectorRig.placeholder
        #expect(motions.problem(with: rig) == nil)
        let hello = try #require(motions.motion(named: "hello"))
        #expect(hello.facing == .front && abs(hello.duration - 2.8) < 1e-9)       // 和作者定案的企鵝哈囉一樣長
        // 站著時手藏在身體裡；哈囉時手轉出身體外
        let front = rig.front
        let body = try #require(front.parts["body"]?.silhouette.first?.bounds)
        let arm = try #require(front.parts["arm"]?.silhouette.first?.bounds)
        #expect(arm.minX > body.minX && arm.maxX < body.maxX && arm.minY > body.minY && arm.maxY < body.maxY)
        let pose = CharacterPose(facing: .front, parts: try #require(hello.clips["front"]).poses(at: 1))
        let raised = try #require(rig.frame(pose)?.transforms["arm"])
        let hand = raised.apply(arm.minX + (arm.maxX - arm.minX) / 2, arm.maxY)
        guard case let .ellipse(cx, cy, rx, ry) = front.parts["body"]?.silhouette.first else {
            Issue.record("身體應該是一個橢圓")
            return
        }
        let dx = (hand.x - cx) / rx, dy = (hand.y - cy) / ry
        #expect(dx * dx + dy * dy > 1)                                              // 手尖在身體外面
        // 播完回到原位
        let end = try #require(hello.clips["front"]).poses(at: hello.duration)
        #expect(end.values.allSatisfy { $0 == .rest })
    }
}
