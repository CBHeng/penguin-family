import Foundation
import Testing
@testable import PenguinFamily

/// 拿真實角色包比對 Swift 和私有素材 repo 的 `vector.js`：哈囉每一格、斜向每個步態抽樣的姿勢與每個部件的矩陣都要相同。
/// 對照檔 `vector.golden.json` 由 `vector/export.js` 寫到測試用的角色包資料夾，不進 git；沒有時跳過。
struct VectorPackParityTests {
    struct Golden: Decodable {
        struct Frame: Decodable {
            let t: Double
            let headDegrees: Double
            let armDegrees: Double
            let squash: Double
            /// 部件名稱 → [a, b, c, d, tx, ty]。
            let transforms: [String: [Double]]
        }
        /// 斜向的一個抽樣：哪個步態（`rest` 是站著）、哪個方向、第幾秒的姿勢與每個部件的矩陣。
        struct Walk: Decodable {
            let gait: String
            let facing: String
            let t: Double
            let swayDegrees: Double
            let dip: Double
            let armOpenDegrees: Double
            let armDy: Double
            /// 腳 → [dx, dy]。
            let feet: [String: [Double]]
            let transforms: [String: [Double]]
        }
        let format: Int
        let motion: String
        let framesPerSecond: Double
        let frames: [Frame]
        let walks: [Walk]?
    }

    static func matches(_ t: Affine2D, _ want: [Double]) -> Bool {
        zip([t.a, t.b, t.c, t.d, t.tx, t.ty], want).allSatisfy { abs($0 - $1) < 1e-9 }
    }

    private final class BundleToken {}

    /// 測試用的角色包裡有 `vector.json` 的資料夾，依名稱排序。角色 id 只從資料夾讀，不寫在程式裡。
    static let allPacks: [URL] = {
        let bundle = Bundle(for: BundleToken.self)
        guard let root = bundle.url(forResource: "CharacterPacks", withExtension: "bundle") else { return [] }
        return CharacterPackLibrary.packs(in: root)
    }()

    /// 其中有對照檔的。
    static let packs = allPacks.filter {
        FileManager.default.fileExists(atPath: $0.appending(path: "vector.golden.json").path)
    }

    @Test(.enabled(if: !packs.isEmpty, "沒有向量對照檔（乾淨 clone），跳過"), arguments: packs)
    func helloMatchesJSFrameByFrame(pack: URL) throws {
        let rig = try VectorRig.decode(Data(contentsOf: pack.appending(path: "vector.json")))
        let golden = try JSONDecoder().decode(Golden.self, from: Data(contentsOf: pack.appending(path: "vector.golden.json")))
        #expect(golden.motion == "hello")
        #expect(golden.frames.count == Int((HelloMotion.duration * golden.framesPerSecond).rounded()))
        for (i, frame) in golden.frames.enumerated() {
            let pose = HelloMotion.pose(at: frame.t)
            #expect(abs(pose.headDegrees - frame.headDegrees) < 1e-12, "frame \(i) head")
            #expect(abs(pose.armDegrees - frame.armDegrees) < 1e-12, "frame \(i) arm")
            #expect(abs(pose.squash - frame.squash) < 1e-12, "frame \(i) squash")
            let transforms = rig.front.frontTransforms(pose)
            #expect(Set(transforms.keys) == Set(frame.transforms.keys), "frame \(i) parts")
            for (name, want) in frame.transforms {
                let t = try #require(transforms[name])
                #expect(Self.matches(t, want), "frame \(i) \(name): \(t) != \(want)")
            }
        }
    }

    /// 斜向四個方向（含翻轉的）：每個步態抽樣的姿勢與每個部件的矩陣都要和 JS 相同。
    @Test(.enabled(if: !packs.isEmpty, "沒有向量對照檔（乾淨 clone），跳過"), arguments: packs)
    func walkingMatchesJSFrameByFrame(pack: URL) throws {
        let rig = try VectorRig.decode(Data(contentsOf: pack.appending(path: "vector.json")))
        let golden = try JSONDecoder().decode(Golden.self, from: Data(contentsOf: pack.appending(path: "vector.golden.json")))
        let walks = try #require(golden.walks, "對照檔沒有斜向")
        #expect(Set(walks.map(\.facing)) == Set(Facing.oblique.map(\.rawValue)))
        #expect(Set(walks.map(\.gait)) == Set(Gait.all.map(\.name) + ["rest"]))
        for w in walks {
            let label = "\(w.gait) \(w.facing) t=\(w.t)"
            let facing = try #require(Facing(rawValue: w.facing))
            let walk = try #require(rig.walk(w.facing), "\(label)")
            var pose = VectorWalkPose.rest
            if w.gait != "rest" {
                pose = try #require(Gait.all.first { $0.name == w.gait }).vectorPose(at: w.t, walk: walk)
            }
            #expect(abs(pose.swayDegrees - w.swayDegrees) < 1e-9 && abs(pose.dip - w.dip) < 1e-9
                    && abs(pose.armOpenDegrees - w.armOpenDegrees) < 1e-9 && abs(pose.armDy - w.armDy) < 1e-9, "\(label)")
            #expect(Set(pose.feet.keys) == Set(w.feet.keys), "\(label) feet")
            for (name, want) in w.feet {
                let got = try #require(pose.feet[name])
                #expect(abs(got.dx - want[0]) < 1e-9 && abs(got.dy - want[1]) < 1e-9, "\(label) \(name)")
            }
            let frame = try #require(rig.frame(.oblique(facing, pose)))
            #expect(Set(frame.transforms.keys) == Set(w.transforms.keys), "\(label) parts")
            for (name, want) in w.transforms {
                let t = try #require(frame.transforms[name])
                #expect(Self.matches(t, want), "\(label) \(name): \(t) != \(want)")
            }
        }
    }
}
