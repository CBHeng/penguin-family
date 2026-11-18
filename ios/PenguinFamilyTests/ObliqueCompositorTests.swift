import Foundation
import Testing
@testable import PenguinFamily

/// 斜向合成規則與步態的測試，只用這裡的假角色，不依賴角色包（和 Python 逐格比對在 `CharacterPackParityTests`）。
struct ObliqueCompositorTests {
    /// `RigCompositorTests` 的假角色加上斜向：8×10 的畫布，左前、左後同一組部件。
    /// 左邊方向：遠的腳 (2,8)、近的腳 (4,8)、身體 3×4 在 (2,4)、手兩格在 (5,5)、頭 3×3 在 (2,1)、帽子 (3,0)。
    /// 右邊方向翻轉左邊；帽子另外放在 (4,0)，和翻轉後的頭重疊的格子不畫。
    static let json: String = {
        let side = """
          "parts": {
            "farFoot": {"x": 2, "y": 8, "rows": ["A"]},
            "nearFoot": {"x": 4, "y": 8, "rows": ["A"]},
            "body": {"x": 2, "y": 4, "rows": ["BBB", "BBB", "BBB", "BBB"]},
            "arm": {"x": 5, "y": 5, "rows": ["U", "U"]},
            "head": {"x": 2, "y": 1, "rows": ["HHH", "HHH", "HHH"]},
            "hat": {"x": 3, "y": 0, "rows": ["R"]}
          },
          "drawOrder": ["farFoot", "nearFoot", "body", "arm", "head", "hat"],
          "leftFoot": "farFoot", "armSide": 1, "rigid": {"hat": [3.5, 0.5]}, "peek": {},
          "rest": {"x": 0, "y": 0, "rows": ["."]}
        """
        let oblique = """
        "oblique": {
          "canvas": {"width": 8, "height": 10},
          "anchor": [3.5, 8.5],
          "leanBaseY": 9.5,
          "shoulderY": 5.0,
          "hatRow": 0,
          "directions": {
            "frontLeft": {\(side), "forward": [-2, 1]},
            "backLeft": {\(side), "forward": [-2, -1]},
            "frontRight": {"mirrorOf": "frontLeft", "hat": {"x": 4, "y": 0, "rows": ["RR"]}, "rest": {"x": 0, "y": 0, "rows": ["."]}},
            "backRight": {"mirrorOf": "backLeft", "hat": {"x": 4, "y": 0, "rows": ["RR"]}, "rest": {"x": 0, "y": 0, "rows": ["."]}}
          }
        },
        """
        return RigCompositorTests.fakeJSON.replacingOccurrences(of: "\"front\": {", with: oblique + "\n  \"front\": {")
    }()

    static func compositor(_ json: String = json) throws -> ObliqueCompositor {
        try #require(try ObliqueCompositor(rig: RigCompositorTests.decode(json)))
    }

    static func compose(_ pose: WalkPose, _ facing: Facing = .frontLeft) throws -> PixelGrid {
        try #require(try compositor().compose(facing, pose))
    }

    // MARK: - 讀角色包

    @Test func oldPacksHaveNoOblique() throws {
        #expect(try ObliqueCompositor(rig: RigCompositorTests.decode(RigCompositorTests.fakeJSON)) == nil)
    }

    @Test func missingDirectionIsAnError() throws {
        let broken = Self.json.replacingOccurrences(of: "\"backRight\"", with: "\"elsewhere\"")
        #expect(throws: CharacterRigError.invalidDirection("backRight")) { try Self.compositor(broken) }
        let mirrorOfMirror = Self.json.replacingOccurrences(of: "\"mirrorOf\": \"backLeft\"", with: "\"mirrorOf\": \"frontRight\"")
        #expect(throws: CharacterRigError.invalidDirection("backRight")) { try Self.compositor(mirrorOfMirror) }
    }

    @Test func anchorUsesTheSameRoundingAsFront() throws {
        let c = try Self.compositor()
        #expect(c.anchor == PixelPoint(x: 3, y: 9))       // x 往下取整、y 往上取整
        #expect(c.compose(.front, .rest) == nil)          // 正面不歸這裡畫
    }

    // MARK: - 合成規則

    @Test func restPoseDrawsPartsAndOutline() throws {
        let g = try Self.compose(.rest)
        #expect(g[3, 0] == "R" && g[2, 1] == "H" && g[2, 4] == "B" && g[5, 5] == "U")
        #expect(g[2, 8] == "A" && g[4, 8] == "A")
        #expect(g[1, 4] == "O" && g[3, 9] == nil)          // 外圍描外框；腳之間往下沒東西
    }

    @Test func leanShiftsHigherRowsMore() throws {
        // 每列 0.25 格：第 y 列移 round(0.25 × (9 - y))，.5 取偶數
        let g = try Self.compose(WalkPose(lean: 0.25))
        #expect(g[4, 1] == "H" && g[2, 1] != "H")            // 第 1 列移 2 格
        #expect(g[3, 4] == "B" && g[2, 4] != "B")            // 第 4 列 1.25 → 1 格
        #expect(g[2, 7] == "B")                              // 第 7 列 0.5 → 0 格
        #expect(g[5, 0] == "R")                              // 帽子整塊跟著第 0 列：2.25 → 2 格
        #expect(g[2, 8] == "A" && g[4, 8] == "A")            // 腳不跟著斜
    }

    @Test func dipMovesEverythingButTheFeet() throws {
        let g = try Self.compose(WalkPose(dip: 1))
        #expect(g[3, 1] == "R" && g[2, 2] == "H" && g[2, 8] == "B")
        #expect(g[4, 8] == "B")                              // 身體往下蓋過近的腳原本的位置（腳先畫）
    }

    @Test func feetMoveOnTheirOwn() throws {
        let g = try Self.compose(WalkPose(feet: [ObliqueCompositor.farFoot: .init(dx: -2, dy: 1)]))
        #expect(g[0, 9] == "A" && g[2, 8] != "A")
        #expect(g[4, 8] == "A")
    }

    @Test func armOpensBelowTheShoulderAndBobs() throws {
        // 肩膀 5.0：第 5 列 round(1 × 0.5) = 0、第 6 列 round(1 × 1.5) = 2，往手那側（右）移
        let open = try Self.compose(WalkPose(armOpen: 1))
        #expect(open[5, 5] == "U" && open[7, 6] == "U" && open[5, 6] != "U")
        let up = try Self.compose(WalkPose(armDy: -1))
        #expect(up[5, 4] == "U" && up[5, 6] != "U")
    }

    @Test func rightSideIsAMirrorWithTheHatBehind() throws {
        let left = try Self.compose(.rest)
        let right = try Self.compose(.rest, .frontRight)
        // 身體、頭、腳左右翻轉（畫布寬 8：x ↔ 7 - x）
        for (x, y) in [(2, 4), (4, 7), (2, 1), (2, 8), (4, 8), (5, 5)] {
            #expect(right[7 - x, y] == left[x, y], "(\(x), \(y))")
        }
        // 左邊的帽子不跟著翻；另外放的帽子在 (4,0)、(5,0)，頭在第 1～3 列沒擋到，兩格都畫
        #expect(right[4, 0] == "R" && right[5, 0] == "R" && right[7 - 3, 0] == "R")
        // 往右傾時，翻轉後的帽子往左移（反方向）
        let leaning = try Self.compose(WalkPose(lean: 0.25), .frontRight)
        #expect(leaning[2, 0] == "R" && leaning[3, 0] == "R")
    }

    @Test func mirroredHatOnlyFillsEmptyCells() throws {
        // 帽子放到和頭重疊的地方：被頭擋住的格子不畫（畫在頭後面）
        let json = Self.json.replacingOccurrences(of: "\"mirrorOf\": \"frontLeft\", \"hat\": {\"x\": 4, \"y\": 0, \"rows\": [\"RR\"]}",
                                                  with: "\"mirrorOf\": \"frontLeft\", \"hat\": {\"x\": 4, \"y\": 0, \"rows\": [\"RR\", \"RR\"]}")
        #expect(json != Self.json)
        let g = try #require(try Self.compositor(json).compose(.frontRight, .rest))
        #expect(g[4, 0] == "R" && g[4, 1] == "H" && g[5, 1] == "H")
    }

    @Test func walkSideOfMirrorIsTheSourceSide() throws {
        let c = try Self.compositor()
        let side = try #require(c.walkSide(.frontRight))
        #expect(side.forward.x == -2 && side.forward.y == 1)
        #expect(side.leftFoot == "farFoot" && side.rightFoot == "nearFoot" && side.armSide == 1)
        #expect(c.walkSide(.backRight)?.forward.y == -1)
    }

    // MARK: - 步態

    @Test func gaitTimingMatchesTheArt() {
        #expect(Gait.walk.frameCount == 12 && Gait.trot.frameCount == 6)
        #expect(Gait.walk.tilesPerSecond == 0.5)      // 約 2 秒走一格地板
        #expect(Gait.trot.tilesPerSecond == 1)        // 小跑快一倍
    }

    @Test func walkStartsWithTheLeftFootBack() throws {
        let side = try #require(try Self.compositor().walkSide(.frontLeft))
        let pose = Gait.walk.pose(frame: 0, side: side)
        #expect(pose.lean == 0 && pose.dip == 1 && pose.armDy == 0)
        #expect(pose.feet["farFoot"] == .init(dx: 2, dy: -1))     // 往後一個單位
        #expect(pose.feet["nearFoot"] == .init(dx: -2, dy: 1))    // 往前一個單位
    }

    @Test func trotLeansTowardWhereItIsGoing() throws {
        let c = try Self.compositor()
        let left = Gait.trot.pose(frame: 0, side: try #require(c.walkSide(.frontLeft)))
        #expect(left.lean < 0)                        // 往左走：往左傾
        let walk = Gait.walk.pose(frame: 3, side: try #require(c.walkSide(.frontLeft)))
        #expect(walk.lean > 0)                        // 慢走只有左右搖擺：前半個循環往右
    }

    @Test func roundingHalfTowardZeroIsSymmetric() {
        #expect(Gait.roundHalfTowardZero(0.5) == 0 && Gait.roundHalfTowardZero(-0.5) == 0)
        #expect(Gait.roundHalfTowardZero(0.51) == 1 && Gait.roundHalfTowardZero(-0.87) == -1)
        #expect(Gait.roundHalfTowardZero(1.5) == 1 && Gait.roundHalfTowardZero(-1.5) == -1)
    }

    // MARK: - 預先算好的圖

    @Test func framesIncludeStandingAndEveryGaitFrame() throws {
        let rig = try RigCompositor(rig: RigCompositorTests.decode(Self.json))
        let frames = CharacterFrames(compositor: rig, oblique: try Self.compositor())
        let ob = try #require(frames.oblique)
        #expect(ob.standing.count == 4 && ob.width == 8 && ob.height == 10)
        #expect(ob.frameCount(.walk, .backRight) == 12 && ob.frameCount(.trot, .frontLeft) == 6)
        #expect(frames.imageCount == 1 + Motion.hello.frameCount + 4 + 4 * (12 + 6))
        #expect(ob.image(.trot, .frontLeft, frame: 7) == ob.image(.trot, .frontLeft, frame: 1))   // 超過一個循環從頭繞
        #expect(CharacterFrames(compositor: rig).oblique == nil)
    }
}
