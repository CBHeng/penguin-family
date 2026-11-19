import Foundation
import Testing
@testable import PenguinFamily

/// 拿真實角色包比對 Swift 合成和私有素材 repo 的 Python 合成是否逐格相同。
///
/// 角色包與對照檔由私有素材 repo 的匯出程式寫到 `PenguinFamilyTests/CharacterPacks.bundle/<角色>/`，
/// 不進 git；乾淨 clone 下來沒有這些檔案，這組測試會跳過。
/// 角色 id 只從資料夾讀，不寫在程式裡（角色名稱只能出現在私有 repo）。
struct CharacterPackParityTests {
    struct Golden: Decodable {
        struct Frame: Decodable {
            let headDegrees: Double
            let armDegrees: Double
            let squash: Double
            let rows: [String]
        }
        let format: Int
        let motion: String
        let frames: [Frame]
    }

    private final class BundleToken {}

    static let packs: [URL] = {
        let bundle = Bundle(for: BundleToken.self)
        guard let root = bundle.url(forResource: "CharacterPacks", withExtension: "bundle"),
              let dirs = try? FileManager.default.contentsOfDirectory(
                at: root, includingPropertiesForKeys: nil, options: .skipsHiddenFiles)
        else { return [] }
        return dirs
            .filter { FileManager.default.fileExists(atPath: $0.appending(path: "rig.json").path) }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }()

    static func compositor(_ pack: URL) throws -> RigCompositor {
        let data = try Data(contentsOf: pack.appending(path: "rig.json"))
        return try RigCompositor(rig: JSONDecoder().decode(CharacterRig.self, from: data))
    }

    /// 第一個不同的像素，方便看錯在哪裡；完全相同回傳 nil。
    static func firstDifference(_ got: [String], _ want: [String]) -> String? {
        guard got.count == want.count else { return "rows \(got.count) != \(want.count)" }
        for (y, (g, w)) in zip(got, want).enumerated() where g != w {
            let x = zip(g, w).enumerated().first { $0.element.0 != $0.element.1 }?.offset ?? min(g.count, w.count)
            return "first difference at (\(x), \(y)): got \(Array(g)[safe: x].map(String.init) ?? "-"), want \(Array(w)[safe: x].map(String.init) ?? "-")"
        }
        return nil
    }

    @Test(.enabled(if: !packs.isEmpty, "沒有角色包（乾淨 clone），跳過"), arguments: packs)
    func restPoseMatchesFront(pack: URL) throws {
        let c = try Self.compositor(pack)
        let empty = Character(c.rig.empty)
        let diff = Self.firstDifference(c.compose(.rest).rows(empty: empty), c.frontGrid().rows(empty: empty))
        #expect(diff == nil, "\(diff ?? "")")
    }

    @Test(.enabled(if: !packs.isEmpty, "沒有角色包（乾淨 clone），跳過"), arguments: packs)
    func motionsMatchPythonFrameByFrame(pack: URL) throws {
        let c = try Self.compositor(pack)
        let empty = Character(c.rig.empty)
        let files = try FileManager.default.contentsOfDirectory(at: pack, includingPropertiesForKeys: nil)
            .filter { $0.lastPathComponent.hasSuffix(".golden.json") && $0.lastPathComponent != "vector.golden.json" }
        try #require(!files.isEmpty, "角色包裡沒有 .golden.json 對照檔")
        for file in files {
            let golden = try JSONDecoder().decode(Golden.self, from: Data(contentsOf: file))
            for (i, frame) in golden.frames.enumerated() {
                let pose = RigPose(headDegrees: frame.headDegrees, armDegrees: frame.armDegrees, squash: frame.squash)
                let diff = Self.firstDifference(c.compose(pose).rows(empty: empty), frame.rows)
                #expect(diff == nil, "\(golden.motion) frame \(i): \(diff ?? "")")
            }
        }
    }

    /// App 播放哈囉用的 Swift 時間軸，每一格的姿勢與畫面都要和 Python 相同。
    @Test(.enabled(if: !packs.isEmpty, "沒有角色包（乾淨 clone），跳過"), arguments: packs)
    func helloTimelineMatchesPython(pack: URL) throws {
        let c = try Self.compositor(pack)
        let empty = Character(c.rig.empty)
        let file = pack.appending(path: "hello.golden.json")
        let golden = try JSONDecoder().decode(Golden.self, from: Data(contentsOf: file))
        #expect(golden.frames.count == HelloMotion.frameCount)
        for (i, frame) in golden.frames.enumerated() {
            let pose = HelloMotion.pose(frame: i)
            #expect(abs(pose.headDegrees - frame.headDegrees) < 1e-9, "frame \(i) head")
            #expect(abs(pose.armDegrees - frame.armDegrees) < 1e-9, "frame \(i) arm")
            #expect(abs(pose.squash - frame.squash) < 1e-12, "frame \(i) squash")
            let diff = Self.firstDifference(c.compose(pose).rows(empty: empty), frame.rows)
            #expect(diff == nil, "frame \(i): \(diff ?? "")")
        }
    }

    // MARK: - 斜向（走路、小跑）

    /// `oblique.parity.json`：慢走、小跑在四個方向每一格的姿勢與 Python 合成結果。
    struct ObliqueGolden: Decodable {
        struct Frame: Decodable {
            let lean: Double
            let dip: Int
            let armOpen: Double
            let armDy: Int
            let feet: [String: [Int]]
            let rows: [String]

            var pose: WalkPose {
                WalkPose(lean: lean, dip: dip, armOpen: armOpen, armDy: armDy,
                         feet: feet.mapValues { WalkPose.Offset(dx: $0[0], dy: $0[1]) })
            }
        }
        let format: Int
        let framesPerSecond: Double
        /// 步態名稱 → 方向 → 每一格。
        let gaits: [String: [String: [Frame]]]
    }

    static func oblique(_ pack: URL) throws -> (ObliqueCompositor, Character) {
        let c = try compositor(pack)
        let ob = try #require(try ObliqueCompositor(rig: c.rig), "角色包沒有斜向")
        return (ob, Character(c.rig.empty))
    }

    @Test(.enabled(if: !packs.isEmpty, "沒有角色包（乾淨 clone），跳過"), arguments: packs)
    func obliqueRestMatchesFinalImages(pack: URL) throws {
        let (ob, empty) = try Self.oblique(pack)
        for facing in Facing.oblique {
            let got = try #require(ob.compose(facing, .rest)).rows(empty: empty)
            let want = try #require(ob.restGrid(facing)).rows(empty: empty)
            let diff = Self.firstDifference(got, want)
            #expect(diff == nil, "\(facing): \(diff ?? "")")
        }
    }

    /// App 的步態（Swift 的 `Gait`）每一格的姿勢與畫面都要和 Python 的 `walk.py` 相同。
    @Test(.enabled(if: !packs.isEmpty, "沒有角色包（乾淨 clone），跳過"), arguments: packs)
    func walkAndTrotMatchPythonFrameByFrame(pack: URL) throws {
        let (ob, empty) = try Self.oblique(pack)
        let golden = try JSONDecoder().decode(
            ObliqueGolden.self, from: Data(contentsOf: pack.appending(path: "oblique.parity.json")))
        #expect(golden.framesPerSecond == Gait.framesPerSecond)
        #expect(Set(golden.gaits.keys) == Set(Gait.all.map(\.name)))
        for gait in Gait.all {
            for facing in Facing.oblique {
                let frames = try #require(golden.gaits[gait.name]?[facing.rawValue], "\(gait.name) \(facing)")
                #expect(frames.count == gait.frameCount, "\(gait.name) \(facing) 格數")
                let side = try #require(ob.walkSide(facing))
                for (i, frame) in frames.enumerated() {
                    let label = "\(gait.name) \(facing) frame \(i)"
                    let pose = gait.pose(frame: i, side: side)
                    #expect(abs(pose.lean - frame.lean) < 1e-12, "\(label) lean")
                    #expect(abs(pose.armOpen - frame.armOpen) < 1e-12, "\(label) armOpen")
                    #expect(pose.dip == frame.pose.dip && pose.armDy == frame.pose.armDy && pose.feet == frame.pose.feet,
                            "\(label) dip/armDy/feet")
                    let diff = Self.firstDifference(try #require(ob.compose(facing, frame.pose)).rows(empty: empty), frame.rows)
                    #expect(diff == nil, "\(label): \(diff ?? "")")
                }
            }
        }
    }
}

// MARK: - 向量（ADR 0007）

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

    static let packs = CharacterPackParityTests.packs.filter {
        FileManager.default.fileExists(atPath: $0.appending(path: "vector.golden.json").path)
    }

    @Test(.enabled(if: !packs.isEmpty, "沒有向量對照檔（乾淨 clone），跳過"), arguments: packs)
    func helloMatchesJSFrameByFrame(pack: URL) throws {
        let rig = try VectorRig.decode(Data(contentsOf: pack.appending(path: "vector.json")))
        let golden = try JSONDecoder().decode(Golden.self, from: Data(contentsOf: pack.appending(path: "vector.golden.json")))
        #expect(golden.motion == "hello" && golden.framesPerSecond == HelloMotion.framesPerSecond)
        #expect(golden.frames.count == HelloMotion.frameCount)
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

private extension Array {
    subscript(safe i: Int) -> Element? { indices.contains(i) ? self[i] : nil }
}
