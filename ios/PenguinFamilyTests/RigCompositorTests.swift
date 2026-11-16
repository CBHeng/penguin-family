import Foundation
import Testing
@testable import PenguinFamily

/// 合成規則的測試，只用這裡的假角色，不依賴角色包。
struct RigCompositorTests {
    /// 10x10 的假角色：3x3 的頭、兩格寬的帽子、3x2 的身體、一格的手。
    /// `front` 是手算的靜止姿勢（含外框 O），同時當作「不動時和定稿相同」的對照。
    static let fakeJSON = """
    {
      "format": 1,
      "canvas": {"width": 10, "height": 10},
      "palette": {"O": "#000000", "B": "#0000FF", "H": "#00FF00", "R": "#FF0000", "A": "#FFFF00", "U": "#00FFFF"},
      "outline": "O",
      "empty": ".",
      "drawOrder": ["body", "arm", "head", "hat"],
      "parts": {
        "body": {"x": 3, "y": 5, "rows": ["BBB", "BBB"], "pivot": [4.5, 7]},
        "arm": {"x": 6, "y": 5, "rows": ["A"], "pivot": [6.5, 5]},
        "armRaised": {"x": 6, "y": 4, "rows": ["U", "U"], "pivot": [6.5, 5]},
        "head": {"x": 3, "y": 2, "rows": ["HHH", "HHH", "HHH"], "pivot": [4.5, 5]},
        "hat": {"x": 4, "y": 1, "rows": ["RR"], "follows": "head", "anchor": [5, 1.5]}
      },
      "rig": {"neckY": 5, "armRaisedAboveDegrees": 20},
      "front": {"x": 0, "y": 0, "rows": [
        "....OO....",
        "...ORRO...",
        "..OHHHO...",
        "..OHHHO...",
        "..OHHHO...",
        "..OBBBAO..",
        "..OBBBO...",
        "...OOO....",
        "..........",
        ".........."
      ]}
    }
    """

    static func decode(_ json: String) throws -> CharacterRig {
        try JSONDecoder().decode(CharacterRig.self, from: Data(json.utf8))
    }

    static func compositor() throws -> RigCompositor {
        try RigCompositor(rig: decode(fakeJSON))
    }

    static func cells(of code: Character, in grid: PixelGrid) -> [(x: Int, y: Int)] {
        var found: [(x: Int, y: Int)] = []
        for y in 0..<grid.height {
            for x in 0..<grid.width where grid[x, y] == code {
                found.append((x, y))
            }
        }
        return found
    }

    @Test func restPoseMatchesFrontWithOutline() throws {
        let c = try Self.compositor()
        #expect(c.compose(.rest) == c.frontGrid())
    }

    @Test func partsFollowingHeadMoveButDoNotRotate() throws {
        let c = try Self.compositor()
        let hat = Self.cells(of: "R", in: c.compose(RigPose(headDegrees: 90)))
        // 兩格寬的帽子轉 90 度會變直的；只移動不轉時仍是同一列相鄰的兩格
        #expect(hat.count == 2)
        #expect(hat[0].y == hat[1].y)
        #expect(abs(hat[0].x - hat[1].x) == 1)
        // 而且確實跟著頭移動了（原本在第 1 列）
        #expect(hat[0].y != 1)
    }

    @Test(arguments: [
        (degrees: 0.0, raised: false),
        (degrees: 20.0, raised: false),
        (degrees: 20.5, raised: true),
        (degrees: -21.0, raised: true),
    ])
    func armSwapsToRaisedPartAboveThreshold(degrees: Double, raised: Bool) throws {
        let grid = try Self.compositor().compose(RigPose(armDegrees: degrees))
        #expect(Self.cells(of: "U", in: grid).isEmpty == !raised)
        #expect(Self.cells(of: "A", in: grid).isEmpty == raised)
    }

    @Test func dropRoundsHalfToEvenLikePython() throws {
        // 身體轉軸 y=7、脖子 y=5，高度 75% 時下沉 (7-5)*0.25 = 0.5 格：
        // .5 取偶數是 0，頭不動；若用 Swift 預設的取整會變成 1，頭往下掉一格
        let grid = try Self.compositor().compose(RigPose(squash: 0.75))
        #expect(Self.cells(of: "H", in: grid).map(\.y).min() == 2)
    }

    @Test func roundHalfEvenMatchesPython() {
        #expect(RigCompositor.roundHalfEven(0.5) == 0)
        #expect(RigCompositor.roundHalfEven(1.5) == 2)
        #expect(RigCompositor.roundHalfEven(2.5) == 2)
        #expect(RigCompositor.roundHalfEven(-0.5) == 0)
        #expect(RigCompositor.roundHalfEven(-1.5) == -2)
        #expect(RigCompositor.roundHalfEven(0.6) == 1)
    }

    @Test func rejectsUnsupportedFormat() throws {
        let rig = try Self.decode(Self.fakeJSON.replacingOccurrences(of: "\"format\": 1", with: "\"format\": 2"))
        #expect(throws: CharacterRigError.unsupportedFormat(2)) { try RigCompositor(rig: rig) }
    }

    @Test func rejectsMissingPart() throws {
        let rig = try Self.decode(Self.fakeJSON.replacingOccurrences(of: "\"armRaised\"", with: "\"armSpare\""))
        #expect(throws: CharacterRigError.missingPart("armRaised")) { try RigCompositor(rig: rig) }
    }

    @Test func rejectsCodeOutsidePalette() throws {
        let rig = try Self.decode(Self.fakeJSON.replacingOccurrences(of: "[\"RR\"]", with: "[\"RZ\"]"))
        #expect(throws: CharacterRigError.unknownCode(part: "hat", code: "Z")) { try RigCompositor(rig: rig) }
    }

    @Test func rejectsPartOutsideCanvas() throws {
        let rig = try Self.decode(Self.fakeJSON.replacingOccurrences(of: "\"x\": 6, \"y\": 5", with: "\"x\": 10, \"y\": 5"))
        #expect(throws: CharacterRigError.partOutOfCanvas("arm")) { try RigCompositor(rig: rig) }
    }
}
