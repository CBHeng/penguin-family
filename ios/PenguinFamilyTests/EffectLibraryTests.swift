import Foundation
import Testing
@testable import PenguinFamily

/// 共用特效的形狀（ADR 0010）：App 裡的 `effects.json` 讀得進來、有動作片段會用到的特效、每個都畫得出來；壞掉的資料擋下來。
struct EffectLibraryTests {
    @Test func bundledEffectsHaveWhatTheDozeUses() throws {
        let library = EffectLibrary.bundled()
        #expect(Set(library.effects.keys).isSuperset(of: ["z", "bubble", "pop"]))
        for (name, effect) in library.effects {
            #expect(effect.silhouette.isEmpty, "\(name) 不描共用外框")
            let images = try #require(VectorRasterizer.rasterizeEffect(effect, name: name, pixelsPerUnit: 16), "\(name) 畫不出來")
            #expect(images.outline == nil && images.fill.width > 0)
        }
    }

    @Test func rejectsBrokenEffects() {
        func decode(_ json: String) -> Error? {
            do {
                _ = try EffectLibrary.decode(Data(json.utf8))
                return nil
            } catch {
                return error
            }
        }
        let ok = """
            {"version": 1, "effects": {"z": {"pivot": {"x": 0, "y": 0}, "silhouette": [],
              "layers": [{"stroke": "#525e70", "width": 0.8, "shapes": [{"path": [["M", -1, -1], ["L", 1, 1]]}]}]}}}
            """
        #expect(decode(ok) == nil)
        #expect(decode(ok.replacingOccurrences(of: "\"version\": 1", with: "\"version\": 2")) as? VectorRigError == .unsupportedFormat(2))
        #expect(decode(ok.replacingOccurrences(of: "#525e70", with: "blue")) as? VectorRigError == .invalidColor("blue"))
        #expect(decode(ok.replacingOccurrences(of: "[{\"path\": [[\"M\", -1, -1], [\"L\", 1, 1]]}]", with: "[]")) != nil)
    }
}
