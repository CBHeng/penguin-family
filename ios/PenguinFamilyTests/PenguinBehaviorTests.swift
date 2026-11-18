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

    // MARK: - 走路

    static let goal = Tile(i: 8, j: 7)

    /// 依序處理，回傳每一次有沒有改變意圖。
    static func results(_ inputs: [PenguinBehavior.Input], from start: PenguinBehavior = PenguinBehavior())
        -> (changed: [Bool], behavior: PenguinBehavior) {
        var behavior = start
        let changed = inputs.map { behavior.handle($0) }
        return (changed, behavior)
    }

    @Test func walkRequestWhileIdleStartsWalking() {
        let (changed, behavior) = Self.results([.walkRequested(to: Self.goal, pace: .trot)])
        #expect(changed == [true])
        #expect(behavior.intent == .walk(to: Self.goal, pace: .trot))
    }

    @Test func arrivingReturnsToIdle() {
        let (changed, behavior) = Self.results([.walkRequested(to: Self.goal, pace: .walk), .arrived, .arrived])
        #expect(changed == [true, true, false])           // 已經在待機時再收到走到：不理
        #expect(behavior.intent == .idle)
    }

    @Test func tapsAndNewRequestsWhileWalkingAreIgnored() {
        let (changed, behavior) = Self.results([
            .walkRequested(to: Self.goal, pace: .walk), .ownerTapped,
            .walkRequested(to: Tile(i: 1, j: 1), pace: .trot), .motionFinished,
        ])
        #expect(changed == [true, false, false, false])
        #expect(behavior.intent == .walk(to: Self.goal, pace: .walk))
    }

    @Test func noWalkingDuringHello() {
        let (changed, behavior) = Self.results([.ownerTapped, .walkRequested(to: Self.goal, pace: .walk)])
        #expect(changed == [true, false])
        #expect(behavior.intent == .hello)
    }
}
