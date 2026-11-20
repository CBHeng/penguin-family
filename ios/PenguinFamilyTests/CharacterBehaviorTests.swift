import Testing
@testable import PenguinFamily

/// 行為狀態機：只看意圖怎麼變，不碰畫面與時間。閒晃怎麼挑下一步在 `WanderTests`。
struct CharacterBehaviorTests {
    @Test func startsIdle() {
        #expect(CharacterBehavior().intent == .idle)
    }

    @Test func tapWhileIdleSaysHello() {
        var behavior = CharacterBehavior()
        let changed = behavior.handle(.ownerTapped)
        #expect(changed)
        #expect(behavior.intent == .hello)
    }

    @Test func tapDuringHelloIsIgnored() {
        var behavior = CharacterBehavior()
        behavior.handle(.ownerTapped)
        let changed = behavior.handle(.ownerTapped)
        #expect(!changed)
        #expect(behavior.intent == .hello)
    }

    @Test func helloReturnsToIdleWhenMotionFinishes() {
        var behavior = CharacterBehavior()
        behavior.handle(.ownerTapped)
        let changed = behavior.handle(.motionFinished)
        #expect(changed)
        #expect(behavior.intent == .idle)
    }

    @Test func motionFinishedWhileIdleIsIgnored() {
        var behavior = CharacterBehavior()
        let changed = behavior.handle(.motionFinished)
        #expect(!changed)
        #expect(behavior.intent == .idle)
    }

    @Test func canSayHelloAgainAfterFinishing() {
        var behavior = CharacterBehavior()
        let inputs: [CharacterBehavior.Input] = [.ownerTapped, .ownerTapped, .motionFinished, .ownerTapped]
        let intents = inputs.map { input -> CharacterBehavior.Intent in
            behavior.handle(input)
            return behavior.intent
        }
        #expect(intents == [.hello, .hello, .idle, .hello])
    }

    // MARK: - 走路

    static let goal = Tile(i: 8, j: 7)

    /// 依序處理，回傳每一次有沒有改變意圖。
    static func results(_ inputs: [CharacterBehavior.Input], from start: CharacterBehavior = CharacterBehavior())
        -> (changed: [Bool], behavior: CharacterBehavior) {
        var behavior = start
        let changed = inputs.map { behavior.handle($0) }
        return (changed, behavior)
    }

    @Test func walkRequestWhileIdleStartsWalking() {
        let (changed, behavior) = Self.results([.moveRequested(to: Self.goal, pace: .fast)])
        #expect(changed == [true])
        #expect(behavior.intent == .move(to: Self.goal, pace: .fast))
    }

    @Test func arrivingReturnsToIdle() {
        let (changed, behavior) = Self.results([.moveRequested(to: Self.goal, pace: .slow), .arrived, .arrived])
        #expect(changed == [true, true, false])           // 已經在待機時再收到走到：不理
        #expect(behavior.intent == .idle)
    }

    @Test func newRequestsWhileWalkingAreIgnored() {
        let (changed, behavior) = Self.results([
            .moveRequested(to: Self.goal, pace: .slow),
            .moveRequested(to: Tile(i: 1, j: 1), pace: .fast), .motionFinished,
        ])
        #expect(changed == [true, false, false])
        #expect(behavior.intent == .move(to: Self.goal, pace: .slow))
    }

    @Test func tapWhileWalkingSaysHelloThenKeepsWalking() {
        // 作者 2026-11-19 決定：走路中被點當場停下哈囉，揮完接著走原本那段路
        let walk = CharacterBehavior.Intent.move(to: Self.goal, pace: .fast)
        var behavior = CharacterBehavior()
        let inputs: [CharacterBehavior.Input] = [.moveRequested(to: Self.goal, pace: .fast), .ownerTapped, .ownerTapped,
                                               .arrived, .motionFinished, .arrived]
        let intents = inputs.map { input -> CharacterBehavior.Intent in
            behavior.handle(input)
            return behavior.intent
        }
        // 哈囉中再點不理、走到也不理（還沒接著走）
        #expect(intents == [walk, .hello, .hello, .hello, walk, .idle])
        #expect(behavior.interruptedMove == nil)
    }

    @Test func helloAfterResumingDoesNotWalkAgain() {
        // 接回去的路走完後，下一次哈囉播完就回到待機，不會又走一次
        let (_, behavior) = Self.results([.moveRequested(to: Self.goal, pace: .slow), .ownerTapped, .motionFinished,
                                          .arrived, .ownerTapped, .motionFinished])
        #expect(behavior.intent == .idle)
    }

    @Test func noWalkingDuringHello() {
        let (changed, behavior) = Self.results([.ownerTapped, .moveRequested(to: Self.goal, pace: .slow)])
        #expect(changed == [true, false])
        #expect(behavior.intent == .hello)
    }

    // MARK: - 站著（A1 第 11 項：發呆、東張西望、在家具旁邊待一下）

    @Test func standsUntilWorldSaysItIsDone() {
        let (changed, behavior) = Self.results([.standRequested(facing: .backRight, seconds: 3), .motionFinished, .motionFinished])
        #expect(changed == [true, true, false])
        #expect(behavior.intent == .idle)
    }

    @Test func tapWhileStandingSaysHello() {
        // 站著也算閒著：發呆時被點就打招呼
        let (changed, behavior) = Self.results([.standRequested(facing: nil, seconds: 5), .ownerTapped])
        #expect(changed == [true, true])
        #expect(behavior.intent == .hello)
    }

    @Test func oneThingAtATime() {
        let stand = CharacterBehavior.Input.standRequested(facing: nil, seconds: 1)
        let walk = CharacterBehavior.Input.moveRequested(to: Self.goal, pace: .slow)
        // 站著時不接走路或另一次站著；走路、哈囉時也不接站著
        #expect(Self.results([stand, walk, stand]).changed == [true, false, false])
        #expect(Self.results([walk, stand]).changed == [true, false])
        #expect(Self.results([.ownerTapped, stand]).changed == [true, false])
        #expect(Self.results([stand, .arrived]).changed == [true, false])
    }

    @Test func sameIntentTwiceIsTwoChanges() {
        let stand = CharacterBehavior.Input.standRequested(facing: .front, seconds: 2)
        // 同樣的站著要兩次，中間經過待機：兩次都算改變，模擬才會重新站
        let (changed, behavior) = Self.results([stand, .motionFinished, stand, .ownerTapped, .ownerTapped])
        #expect(changed == [true, true, true, true, false])
        #expect(behavior.intent == .hello)
    }
}
