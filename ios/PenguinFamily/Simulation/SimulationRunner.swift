import Foundation
import QuartzCore
import Synchronization

/// 驅動模擬（ADR 0008）：模擬在自己的執行緒上照真實時間跑節拍，主執行緒只讀最新的快照、從不等它。
///
/// - **時間**：模擬的時間和真實時間對齊；`epoch` 是模擬時間 0 對到的真實時間（秒，`CACurrentMediaTime` 的時間軸）。
/// - **停下來不補跑**：沒有東西在動時直接跳到該醒來的前一拍（`Simulation.skip`）；執行緒睡到下一個排定的時間或有事件進來。
/// - **落後太多就丟掉時間**：一次最多補 `maxCatchUpTicks` 個節拍（例如 App 從背景回來），角色不會快轉。
/// - **畫的時間晚一個節拍**（`renderTime`），落在最近兩份快照之間，畫面準備在中間內插。
///
/// 跨執行緒只傳值，交接處用 `Mutex`（iOS 18 起）：
/// - 主執行緒 → 模擬：事件放進收件匣（`send`），叫醒模擬的執行緒。
/// - 模擬 → 主執行緒：每跑一拍就發布最近兩份快照與 `epoch`（`latest`）；輸出事件依序轉回主執行緒（`onOutputs`）；
///   台上的樣子變了就叫醒遊戲迴圈（`onWake`）。
///
/// `simulation` 與 `epoch` 只有跑節拍的那一方碰：`start` 之後是模擬的執行緒；沒有 `start` 時（測試）是呼叫 `advance` 的人。
/// 驗收用：啟動參數 `-SimulationExtraTickMilliseconds 50` 讓每個節拍多花 50 毫秒，確認狀態機變慢時畫面照樣順。
nonisolated final class SimulationRunner: @unchecked Sendable {
    /// 一次最多補跑幾個節拍（約 0.27 秒）。
    static let maxCatchUpTicks = 8

    /// 主執行緒讀的東西：最近兩份快照與模擬時間 0 對到的真實時間。
    struct Latest: Equatable, Sendable {
        /// 最新的前一份；剛開始或剛跳過節拍時和最新的一樣。
        var previous: SimulationSnapshot
        var current: SimulationSnapshot
        var epoch: Double
    }

    /// 兩邊都會碰的東西，只在 `Mutex` 裡讀寫。
    private struct Shared {
        var inbox: [Simulation.Event] = []
        var latest: Latest
        var stopped = false
    }

    private let shared: Mutex<Shared>
    /// 叫醒模擬的執行緒（有事件進來、要停下來）。
    private let signal = DispatchSemaphore(value: 0)
    /// 每個節拍故意多花幾秒（驗收用，預設 0）。
    private let extraTickDelay: Double

    private var simulation: Simulation
    private var epoch: Double
    private var thread: Thread?

    /// 模擬跑出來的事（事件紀錄等），在主執行緒上依序交出。
    @MainActor var onOutputs: ([Simulation.Output]) -> Void = { _ in }
    /// 送了事件、或台上的樣子變了：叫醒遊戲迴圈（在主執行緒上呼叫）。
    @MainActor var onWake: () -> Void = {}

    /// `now` 是現在的真實時間：模擬現在的時間對到它。
    init(simulation: Simulation, now: Double,
         extraTickDelay: Double = UserDefaults.standard.double(forKey: "SimulationExtraTickMilliseconds") / 1000) {
        self.simulation = simulation
        epoch = now - simulation.time
        let snapshot = simulation.snapshot
        shared = Mutex(Shared(latest: Latest(previous: snapshot, current: snapshot, epoch: epoch)))
        self.extraTickDelay = max(0, extraTickDelay)
    }

    private static var secondsPerTick: Double { 1 / Double(Simulation.ticksPerSecond) }

    // MARK: - 主執行緒

    /// 最近兩份快照與 `epoch`，任何執行緒都可以讀。
    var latest: Latest { shared.withLock { $0.latest } }
    var previous: SimulationSnapshot { latest.previous }
    var current: SimulationSnapshot { latest.current }

    /// 還有東西在動、或有事件還沒處理：遊戲迴圈要繼續。
    var isActive: Bool { shared.withLock { $0.latest.current.isActive || !$0.inbox.isEmpty } }

    /// 真實時間 `now` 對到的模擬時間（屬性條用來往前推算睏意、耐心）。
    func simulationTime(at now: Double) -> Double { now - latest.epoch }

    /// 真實時間 `now` 要畫的模擬時間：比現在晚一個節拍。
    func renderTime(at now: Double) -> Double { now - latest.epoch - Self.secondsPerTick }

    /// 事件放進收件匣，下一個節拍生效；叫醒模擬的執行緒與遊戲迴圈。
    @MainActor
    func send(_ event: Simulation.Event) {
        shared.withLock { $0.inbox.append(event) }
        signal.signal()
        onWake()
    }

    /// 開一條執行緒跑模擬。只開一次。
    @MainActor
    func start() {
        guard thread == nil else { return }
        let thread = Thread { [weak self] in self?.run() }
        thread.name = "Simulation"
        thread.qualityOfService = .userInteractive
        self.thread = thread
        thread.start()
    }

    /// 停下模擬的執行緒（畫面拆掉時）。
    @MainActor
    func stop() {
        shared.withLock { $0.stopped = true }
        signal.signal()
    }

    // MARK: - 跑節拍的那一方

    /// 模擬的執行緒：跑到現在 → 有輸出就交給主執行緒、樣子變了就叫醒遊戲迴圈 → 睡到下一拍、排定的時間或有事件進來。
    private func run() {
        while !shared.withLock({ $0.stopped }) {
            let before = latest.current
            let outputs = PerfSignposts.measure("simulate") { advance(to: CACurrentMediaTime()) }
            let after = latest.current
            let changed = after.characters != before.characters || after.isActive != before.isActive
            if !outputs.isEmpty || changed {
                DispatchQueue.main.async { [weak self] in
                    MainActor.assumeIsolated {
                        guard let self else { return }
                        if !outputs.isEmpty { self.onOutputs(outputs) }
                        self.onWake()
                    }
                }
            }
            _ = signal.wait(timeout: nextWake())
        }
    }

    /// 下次要醒來的時間：有東西在動或有事件在等時是下一拍；站著時是最早站滿的時間；都沒有就一直睡到有事件進來。
    private func nextWake() -> DispatchTime {
        let wakeAt: Double
        if simulation.isActive || shared.withLock({ !$0.inbox.isEmpty }) {
            wakeAt = epoch + Double(simulation.tick + 1) * Self.secondsPerTick
        } else if let standEnds = simulation.wakeAt {
            wakeAt = epoch + standEnds
        } else {
            return .distantFuture
        }
        return .now() + max(0, wakeAt - CACurrentMediaTime())
    }

    /// 把模擬推進到真實時間 `now`，回傳這段期間跑出來的事。每跑一拍就發布一次快照。
    /// 只能由跑節拍的那一方呼叫：`start` 之後是模擬的執行緒，沒有 `start` 時（測試）可以直接呼叫。
    @discardableResult
    func advance(to now: Double) -> [Simulation.Output] {
        let events = shared.withLock { state in
            defer { state.inbox.removeAll() }
            return state.inbox
        }
        for event in events { simulation.send(event) }
        let perSecond = Double(Simulation.ticksPerSecond)
        var target = Int(((now - epoch) * perSecond).rounded(.down))
        guard target > simulation.tick else { return [] }
        if !simulation.isMoving {
            // 沒有東西在動：停下來的期間不補跑，直接跳到該醒來的前一拍或現在；有事件在等時留一拍給它，現在就生效
            var until = target
            if let wakeAt = simulation.wakeAt { until = min(until, Int((wakeAt * perSecond).rounded(.up)) - 1) }
            if simulation.isActive { until = min(until, target - 1) }
            simulation.skip(to: until)
            if simulation.tick >= target {
                let snapshot = simulation.snapshot
                publish(previous: snapshot, current: snapshot)
                return []
            }
        }
        if target - simulation.tick > Self.maxCatchUpTicks {
            epoch += Double(target - simulation.tick - Self.maxCatchUpTicks) / perSecond
            target = simulation.tick + Self.maxCatchUpTicks
        }
        var outputs: [Simulation.Output] = []
        while simulation.tick < target {
            let before = simulation.snapshot
            outputs += simulation.step()
            if extraTickDelay > 0 { Thread.sleep(forTimeInterval: extraTickDelay) }
            publish(previous: before, current: simulation.snapshot)
        }
        return outputs
    }

    private func publish(previous: SimulationSnapshot, current: SimulationSnapshot) {
        let latest = Latest(previous: previous, current: current, epoch: epoch)
        shared.withLock { $0.latest = latest }
    }
}
