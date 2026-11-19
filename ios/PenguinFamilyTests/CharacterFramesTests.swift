import Testing
@testable import PenguinFamily

/// 預先算好的每一格：和當場合成的結果逐像素相同、超出範圍是站好、記憶體估算。
/// 用 `RigCompositorTests` 手寫的 10×10 假角色，永遠會跑。
struct CharacterFramesTests {
    @Test func everyFrameMatchesComposingOnTheSpot() throws {
        let compositor = try RigCompositorTests.compositor()
        let frames = CharacterFrames(compositor: compositor)
        for i in 0..<Motion.hello.frameCount {
            let expected = PixelBitmap(compositor.compose(Motion.hello.pose(i)), colors: compositor.colors)
            #expect(frames.image(.hello, frame: i) == expected, "第 \(i) 格不同")
        }
        #expect(frames.rest == PixelBitmap(compositor.compose(.rest), colors: compositor.colors))
    }

    @Test func outOfRangeShowsRest() throws {
        let frames = CharacterFrames(compositor: try RigCompositorTests.compositor())
        #expect(frames.image(.hello, frame: Motion.hello.frameCount) == frames.rest)
        #expect(frames.image(.hello, frame: -1) == frames.rest)
        // 沒算過的動作也顯示站好
        let unknown = Motion(name: "unknown", framesPerSecond: 20, frameCount: 3, pose: { _ in .rest }, poseAt: { _ in .rest })
        #expect(frames.image(unknown, frame: 0) == frames.rest)
        #expect(frames.frameCount(of: unknown) == 0)
    }

    @Test func countsImagesAndBytes() throws {
        let frames = CharacterFrames(compositor: try RigCompositorTests.compositor())
        #expect(frames.imageCount == 1 + Motion.hello.frameCount)  // 站好 + 哈囉 56 格
        #expect(frames.byteCount == frames.imageCount * frames.width * frames.height * 4)
    }

    @Test func helloMotionMatchesItsTimeline() {
        #expect(Motion.hello.frameCount == HelloMotion.frameCount)
        #expect(Motion.hello.duration == HelloMotion.duration)
        #expect(Motion.hello.pose(30) == HelloMotion.pose(frame: 30))
    }
}
