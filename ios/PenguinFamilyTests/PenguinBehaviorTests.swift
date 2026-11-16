import Testing
@testable import PenguinFamily

/// 行為狀態機：只看意圖怎麼變，不碰畫面與時間。
struct PenguinBehaviorTests {
    @Test func startsIdle() {
        #expect(PenguinBehavior().intent == .idle)
    }

    @Test func tapWhileIdleSaysHello() {
        var behavior = PenguinBehavior()
        let changed = behavior.handle(.ownerTapped)
        #expect(changed)
        #expect(behavior.intent == .hello)
    }

    @Test func tapDuringHelloIsIgnored() {
        var behavior = PenguinBehavior()
        behavior.handle(.ownerTapped)
        let changed = behavior.handle(.ownerTapped)
        #expect(!changed)
        #expect(behavior.intent == .hello)
    }

    @Test func helloReturnsToIdleWhenMotionFinishes() {
        var behavior = PenguinBehavior()
        behavior.handle(.ownerTapped)
        let changed = behavior.handle(.motionFinished)
        #expect(changed)
        #expect(behavior.intent == .idle)
    }

    @Test func motionFinishedWhileIdleIsIgnored() {
        var behavior = PenguinBehavior()
        let changed = behavior.handle(.motionFinished)
        #expect(!changed)
        #expect(behavior.intent == .idle)
    }

    @Test func canSayHelloAgainAfterFinishing() {
        var behavior = PenguinBehavior()
        let inputs: [PenguinBehavior.Input] = [.ownerTapped, .ownerTapped, .motionFinished, .ownerTapped]
        let intents = inputs.map { input -> PenguinBehavior.Intent in
            behavior.handle(input)
            return behavior.intent
        }
        #expect(intents == [.hello, .hello, .idle, .hello])
    }
}
