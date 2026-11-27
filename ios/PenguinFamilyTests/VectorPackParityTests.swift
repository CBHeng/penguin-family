import Foundation
import Testing
@testable import PenguinFamily

/// 拿真實角色包比對 App 播出來的動作和私有素材 repo `vector.js` 的算式（ADR 0009、0010）：
/// App 照角色包的片段播（和畫面準備相同的找法），在每個關鍵影格上每個部件的矩陣、要畫哪些部件、
/// 每個看得到的特效（矩陣與透明度）都要和算式相同；兩個關鍵影格中間不能差超過對照檔寫的 `tolerance`
/// （部件套在畫布四個角上最遠差幾個單位；特效比轉軸四周的方框與透明度）。
/// 哈囉、斜向四個方向（含翻轉的）的慢與快、坐下、打瞌睡、自己醒來、驚醒揉眼睛、上床、睡覺、被點醒、睡飽（分段的每一段，ADR 0011）都比。動作用那個角色包自己的 `motion.json`（每隻各一份）。
/// 對照檔 `vector.golden.json` 由 `vector/export.js` 寫到測試用的角色包資料夾，不進 git；沒有時跳過。
struct VectorPackParityTests {
    struct Golden: Decodable {
        /// 一個時間點：哪個動作（`hello`，或快慢 `slow`、`fast`）、哪個方向、第幾秒，算式算出的每個部件矩陣。
        struct Sample: Decodable {
            let motion: String
            /// 分段的動作是第幾段；不分段的沒有。
            let stage: Int?
            /// 方向或姿勢。
            let facing: String
            let t: Double
            /// 兩個關鍵影格的中間（不是關鍵影格）。
            let between: Bool?
            /// 部件名稱 → [a, b, c, d, tx, ty]。
            let transforms: [String: [Double]]
            /// 這一刻要畫的部件，依畫的先後。
            let shown: [String]
            /// 每條特效（看不到的也在），依軌道的順序。
            let effects: [Effect]
        }
        struct Effect: Decodable {
            let name: String
            /// [a, b, c, d, tx, ty]，已經是這個方向的（翻轉的只翻位置）。
            let m: [Double]
            let alpha: Double
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

    /// App 在這個時間點播出來的樣子：和畫面準備相同，從快照的「在做什麼」找片段。
    static func played(_ sample: Golden.Sample, rig: VectorRig, motions: CharacterMotions) throws
        -> (transforms: [String: Affine2D], shown: [String], pose: CharacterPose, look: VectorRig.Look) {
        // 分段的、用姿勢播的：直接拿那一段片段；其他照快照的「在做什麼」找
        if let motion = motions.motion(named: sample.motion), let clip = Self.clip(sample, motion) {
            let pose = CharacterPose(look: sample.facing, clip: clip, at: sample.t, cycle: motion.cycle)
            let frame = try #require(rig.frame(pose))
            return (frame.transforms, rig.shownParts(frame.look, pose), pose, frame.look)
        }
        let facing = try #require(Facing(rawValue: sample.facing))
        let activity: SimulationSnapshot.Activity
        if let intent = CharacterBehavior.Intent.playing.first(where: { $0.motionName == sample.motion }) {
            activity = .motion(intent, since: 0)
        } else if motions.motion(named: sample.motion) != nil {
            // 點一下的反應（歪頭、嚇一跳、開心哈囉、不耐煩）：動作名稱就是反應的意圖
            activity = .motion(.react(sample.motion), since: 0)
        } else {
            activity = .moving(try #require(CharacterBehavior.Pace(rawValue: sample.motion)), elapsed: sample.t)
        }
        let character = SimulationSnapshot.Character(id: CharacterID("pack"), position: TilePosition(i: 0.5, j: 0.5),
                                                     facing: facing, activity: activity)
        let pose = FrameBuilder.pose(of: character, before: nil, alpha: 1, at: sample.t, rig: rig, motions: motions)
        #expect(pose.look == sample.facing)
        let frame = try #require(rig.frame(pose))
        return (frame.transforms, rig.shownParts(frame.look, pose), pose, frame.look)
    }

    /// 分段的動作那一段的片段，或用姿勢播的片段；造型要和對照檔的一樣。其他是 nil。
    static func clip(_ sample: Golden.Sample, _ motion: CharacterMotions.Motion) -> MotionClip? {
        if let stage = sample.stage {
            return motion.stages.indices.contains(stage) && motion.stages[stage].look == sample.facing ? motion.stages[stage].clip : nil
        }
        return motion.look == sample.facing ? motion.clips[sample.facing] : nil
    }

    /// 共用特效的形狀（App 裡的 `effects.json`）：比特效時用轉軸。
    static let effects = EffectLibrary.bundled()

    /// App 在這個時間點每條特效軌道的樣子（看不到的也在），換成這個方向的矩陣。
    static func playedEffects(_ sample: Golden.Sample, rig: VectorRig, motions: CharacterMotions, look: VectorRig.Look) throws
        -> [(name: String, m: Affine2D, alpha: Double)] {
        guard let motion = motions.motion(named: sample.motion),
              let clip = Self.clip(sample, motion) ?? motion.clips[look.source] else { return [] }
        let t = motion.loops ? sample.t : min(max(0, sample.t), motion.duration)
        return try clip.effectPoses(at: t, cycle: motion.cycle, includeHidden: true).map { effect in
            let pivot = try #require(effects.effects[effect.name], "effects.json 沒有 \(effect.name)").pivot
            return (effect.name, rig.effectMatrix(effect, pivot: pivot, look: look), effect.alpha)
        }
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
    func coversEveryMotionInEveryFacing(pack: URL) throws {
        let golden = try Self.load(pack).golden
        #expect(golden.format == CharacterMotions.supportedVersion)
        let facings = { (motion: String) in Set(golden.samples.filter { $0.motion == motion }.map(\.facing)) }
        #expect(facings("hello") == ["front"])
        #expect(facings("wakeStartled") == ["front"])
        for pace in CharacterBehavior.Pace.allCases {
            #expect(facings(pace.rawValue) == Set(Facing.oblique.map(\.rawValue)), "\(pace.rawValue)")
        }
        for motion in ["sitDown", "doze", "standUp"] {
            #expect(facings(motion) == Set(Facing.allCases.map(\.rawValue)), "\(motion)")
        }
        // 去床上睡（ADR 0011）：分段的每一段都比
        #expect(facings("sleep") == ["lieBack"])
        for motion in ["climbIn", "wakeTapped", "wakeRested"] {
            let stages = try #require(try Self.load(pack).motions.motion(named: motion)).stages
            let compared = golden.samples.filter { $0.motion == motion }
            #expect(Set(compared.compactMap(\.stage)) == Set(stages.indices), "\(motion)")
            #expect(Set(compared.map(\.facing)) == Set(stages.map(\.look)), "\(motion)")
        }
    }

    @Test(.enabled(if: !packs.isEmpty, "沒有向量對照檔（乾淨 clone），跳過"), arguments: packs)
    func keyframesMatchJSExactly(pack: URL) throws {
        let (rig, motions, golden) = try Self.load(pack)
        for sample in golden.samples where sample.between != true {
            let label = "\(sample.motion) \(sample.facing) t=\(sample.t)"
            let got = try Self.played(sample, rig: rig, motions: motions)
            #expect(got.shown == sample.shown, "\(label) shown")
            // 只比畫得到的部件：整段都藏著的部件沒有軌道，App 放在原位也不會畫
            for name in sample.shown {
                let t = try #require(got.transforms[name]), want = try #require(sample.transforms[name])
                #expect(Self.matches(t, want), "\(label) \(name): \(t) != \(want)")
            }
            let want = sample.effects.filter { $0.alpha > 0 }
            #expect(got.pose.effects.count == want.count, "\(label) effects")
            let effects = try Self.playedEffects(sample, rig: rig, motions: motions, look: got.look).filter { $0.alpha > 0 }
            for (e, w) in zip(effects, want) {
                #expect(e.name == w.name && abs(e.alpha - w.alpha) < 1e-9 && Self.matches(e.m, w.m), "\(label) \(w.name)")
            }
        }
    }

    @Test(.enabled(if: !packs.isEmpty, "沒有向量對照檔（乾淨 clone），跳過"), arguments: packs)
    func betweenKeyframesStaysWithinTolerance(pack: URL) throws {
        let (rig, motions, golden) = try Self.load(pack)
        var worst = 0.0
        for sample in golden.samples where sample.between == true {
            let got = try Self.played(sample, rig: rig, motions: motions)
            let canvas = try #require(rig.look(sample.facing).flatMap { rig.drawn($0.source) }).canvas
            for name in sample.shown {
                worst = max(worst, Self.gap(try #require(got.transforms[name]), try #require(sample.transforms[name]), canvas: canvas))
            }
            // 特效：位置的差乘上看得到的程度，加上透明度的差（和 vector.js 的 effectGap 相同）
            let effects = try Self.playedEffects(sample, rig: rig, motions: motions, look: got.look)
            #expect(effects.count == sample.effects.count, "\(sample.motion) \(sample.facing) t=\(sample.t) effects")
            for (e, w) in zip(effects, sample.effects) {
                let pivot = try #require(Self.effects.effects[w.name]).pivot, b = 3.0
                let corners = VectorRig.Size(width: 2 * b, height: 2 * b)
                let shift = Affine2D.translation(pivot.x - b, pivot.y - b)
                let wantShifted = [w.m[0], w.m[1], w.m[2], w.m[3],
                                   w.m[0] * (pivot.x - b) + w.m[2] * (pivot.y - b) + w.m[4],
                                   w.m[1] * (pivot.x - b) + w.m[3] * (pivot.y - b) + w.m[5]]
                let position = Self.gap(e.m * shift, wantShifted, canvas: corners) * max(e.alpha, w.alpha)
                worst = max(worst, position, abs(e.alpha - w.alpha) * 2)
            }
        }
        #expect(worst <= golden.tolerance + 1e-9, "關鍵影格中間最多差 \(worst) 單位，超過 \(golden.tolerance)")
    }
}
