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
            .filter { $0.lastPathComponent.hasSuffix(".golden.json") }
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
}

private extension Array {
    subscript(safe i: Int) -> Element? { indices.contains(i) ? self[i] : nil }
}
