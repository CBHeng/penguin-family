import Foundation
import Testing
@testable import PenguinFamily

/// 拿真實角色包比對 App 播出來的動作和私有素材 repo `vector.js` 的算式（ADR 0009）：
/// App 照角色包的片段播（和畫面準備相同的找法），在每個關鍵影格上每個部件的矩陣都要和算式相同，
/// 兩個關鍵影格中間不能差超過對照檔寫的 `tolerance`（部件套在畫布四個角上最遠差幾個單位）。
/// 哈囉與斜向四個方向（含翻轉的）、慢與快都比。動作用那個角色包自己的 `motion.json`（每隻各一份）。
/// 對照檔 `vector.golden.json` 由 `vector/export.js` 寫到測試用的角色包資料夾，不進 git；沒有時跳過。
struct VectorPackParityTests {
    struct Golden: Decodable {
        /// 一個時間點：哪個動作（`hello`，或快慢 `slow`、`fast`）、哪個方向、第幾秒，算式算出的每個部件矩陣。
        struct Sample: Decodable {
            let motion: String
            let facing: String
            let t: Double
            /// 兩個關鍵影格的中間（不是關鍵影格）。
            let between: Bool?
            /// 部件名稱 → [a, b, c, d, tx, ty]。
            let transforms: [String: [Double]]
        }
        let format: Int
        let tolerance: Double
        let samples: [Sample]
    }

    private final class BundleToken {}

    /// 測試用的角色包裡有 `vector.json` 的資料夾，照名單的順序（沒有名單就依名稱）。角色 id 只從資料夾讀，不寫在程式裡。
    static let allPacks: [URL] = {
        let bundle = Bundle(for: BundleToken.self)
        guard let root = bundle.url(forResource: "CharacterPacks", withExtension: "bundle") else { return [] }
        return CharacterPackLibrary.packs(in: root)
    }()

    /// 其中有對照檔的。
    static let packs = allPacks.filter {
        FileManager.default.fileExists(atPath: $0.appending(path: "vector.golden.json").path)
    }

    static func load(_ pack: URL) throws -> (rig: VectorRig, motions: CharacterMotions, golden: Golden) {
        let character = try CharacterPackLibrary.load(pack)
        let motions = try #require(character.motions, "motion.json 讀不懂或對不上造型")
        let golden = try JSONDecoder().decode(Golden.self, from: Data(contentsOf: pack.appending(path: "vector.golden.json")))
        return (character.vector, motions, golden)
    }

    /// App 在這個時間點播出來的每個部件矩陣：和畫面準備相同，從快照的「在做什麼」找片段。
    static func played(_ sample: Golden.Sample, rig: VectorRig, motions: CharacterMotions) throws -> [String: Affine2D] {
        let facing = try #require(Facing(rawValue: sample.facing))
        let activity: SimulationSnapshot.Activity
        if sample.motion == "hello" {
            activity = .motion(.hello, since: 0)
        } else {
            activity = .moving(try #require(CharacterBehavior.Pace(rawValue: sample.motion)), elapsed: sample.t)
        }
        let character = SimulationSnapshot.Character(id: CharacterID("pack"), position: TilePosition(i: 0.5, j: 0.5),
                                                     facing: facing, activity: activity)
        let pose = FrameBuilder.pose(of: character, before: nil, alpha: 1, at: sample.t, rig: rig, motions: motions)
        #expect(pose.facing == facing)
        return try #require(rig.frame(pose)).transforms
    }

    static func matches(_ t: Affine2D, _ want: [Double]) -> Bool {
        zip([t.a, t.b, t.c, t.d, t.tx, t.ty], want).allSatisfy { abs($0 - $1) < 1e-9 }
    }

    /// 兩個矩陣套在畫布四個角上最遠差幾個單位（和 `vector.js` 的 `gap` 相同）。
    static func gap(_ t: Affine2D, _ want: [Double], canvas: VectorRig.Size) -> Double {
        [(0.0, 0.0), (canvas.width, 0), (0, canvas.height), (canvas.width, canvas.height)].map { x, y in
            let p = t.apply(x, y)
            return hypot(p.x - (want[0] * x + want[2] * y + want[4]), p.y - (want[1] * x + want[3] * y + want[5]))
        }.max() ?? 0
    }

    @Test(.enabled(if: !packs.isEmpty, "沒有向量對照檔（乾淨 clone），跳過"), arguments: packs)
    func coversHelloAndBothPacesInEveryFacing(pack: URL) throws {
        let golden = try Self.load(pack).golden
        #expect(golden.format == CharacterMotions.supportedVersion)
        #expect(Set(golden.samples.filter { $0.motion == "hello" }.map(\.facing)) == ["front"])
        for pace in CharacterBehavior.Pace.allCases {
            #expect(Set(golden.samples.filter { $0.motion == pace.rawValue }.map(\.facing)) == Set(Facing.oblique.map(\.rawValue)),
                    "\(pace.rawValue)")
        }
    }

    @Test(.enabled(if: !packs.isEmpty, "沒有向量對照檔（乾淨 clone），跳過"), arguments: packs)
    func keyframesMatchJSExactly(pack: URL) throws {
        let (rig, motions, golden) = try Self.load(pack)
        for sample in golden.samples where sample.between != true {
            let label = "\(sample.motion) \(sample.facing) t=\(sample.t)"
            let got = try Self.played(sample, rig: rig, motions: motions)
            #expect(Set(got.keys) == Set(sample.transforms.keys), "\(label) parts")
            for (name, want) in sample.transforms {
                let t = try #require(got[name])
                #expect(Self.matches(t, want), "\(label) \(name): \(t) != \(want)")
            }
        }
    }

    @Test(.enabled(if: !packs.isEmpty, "沒有向量對照檔（乾淨 clone），跳過"), arguments: packs)
    func betweenKeyframesStaysWithinTolerance(pack: URL) throws {
        let (rig, motions, golden) = try Self.load(pack)
        var worst = 0.0
        for sample in golden.samples where sample.between == true {
            let got = try Self.played(sample, rig: rig, motions: motions)
            let canvas = try #require(rig.look(sample.facing).flatMap { rig.facings[$0.source] }).canvas
            for (name, want) in sample.transforms {
                worst = max(worst, Self.gap(try #require(got[name]), want, canvas: canvas))
            }
        }
        #expect(worst <= golden.tolerance + 1e-9, "關鍵影格中間最多差 \(worst) 單位，超過 \(golden.tolerance)")
    }
}
