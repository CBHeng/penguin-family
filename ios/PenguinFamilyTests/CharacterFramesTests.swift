import CoreGraphics
import Foundation
import Testing
@testable import PenguinFamily

/// 預先算好的每一格：和當場合成的結果逐像素相同、超出範圍是站好、記憶體估算。
/// 用 `RigCompositorTests` 手寫的 10×10 假角色，永遠會跑。
struct CharacterFramesTests {
    /// 讀回圖片的 RGBA 位元組，和 `PixelImage.rgba` 同一種排法。
    static func bytes(_ image: CGImage?) -> [UInt8]? {
        guard let data = image?.dataProvider?.data else { return nil }
        return [UInt8](data as Data)
    }

    @Test func everyFrameMatchesComposingOnTheSpot() throws {
        let compositor = try RigCompositorTests.compositor()
        let frames = CharacterFrames(compositor: compositor)
        for i in 0..<Motion.hello.frameCount {
            let expected = PixelImage.rgba(compositor.compose(Motion.hello.pose(i)), colors: compositor.colors)
            #expect(Self.bytes(frames.image(.hello, frame: i)) == expected, "第 \(i) 格不同")
        }
        #expect(Self.bytes(frames.rest) == PixelImage.rgba(compositor.compose(.rest), colors: compositor.colors))
    }

    @Test func outOfRangeShowsRest() throws {
        let frames = CharacterFrames(compositor: try RigCompositorTests.compositor())
        let rest = Self.bytes(frames.rest)
        #expect(Self.bytes(frames.image(.hello, frame: Motion.hello.frameCount)) == rest)
        #expect(Self.bytes(frames.image(.hello, frame: -1)) == rest)
        // 沒算過的動作也顯示站好
        let unknown = Motion(name: "unknown", framesPerSecond: 20, frameCount: 3, pose: { _ in .rest })
        #expect(Self.bytes(frames.image(unknown, frame: 0)) == rest)
    }

    @Test func countsImagesAndBytes() throws {
        let frames = CharacterFrames(compositor: try RigCompositorTests.compositor())
        #expect(frames.imageCount == 1 + Motion.hello.frameCount)  // 站好 + 哈囉 56 格
        #expect(frames.byteCount == frames.imageCount * frames.width * frames.height * 4)
    }

    @Test @MainActor func helloMotionMatchesItsTimeline() {
        #expect(Motion.hello.frameCount == HelloMotion.frameCount)
        #expect(Motion.hello.duration == HelloMotion.duration)
        #expect(Motion.hello.pose(30) == HelloMotion.pose(frame: 30))
        #expect(PenguinView.motion(for: .hello)?.name == "hello")
        #expect(PenguinView.motion(for: .idle) == nil)
    }
}
