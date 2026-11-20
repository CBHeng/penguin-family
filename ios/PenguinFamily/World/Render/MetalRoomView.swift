import MetalKit
import os
import SwiftUI

/// 把 Metal 的畫面放進 SwiftUI。畫面本身不會移動，鏡頭、縮放都在畫面準備時處理。
struct MetalRoomView: UIViewRepresentable {
    let scene: RoomScene
    /// 模擬跑出來的事（例如主人點了哪一隻），交給外面記錄。
    var onOutputs: ([Simulation.Output]) -> Void = { _ in }

    func makeCoordinator() -> GameLoop {
        GameLoop(scene: scene)
    }

    func makeUIView(context: Context) -> MTKView {
        let view = MTKView(frame: .zero, device: MTLCreateSystemDefaultDevice())
        view.colorPixelFormat = .bgra8Unorm
        // 箱庭外面的顏色，和 `GameView.outsideColor` 相同
        view.clearColor = MTLClearColor(red: 0.23, green: 0.21, blue: 0.19, alpha: 1)
        // 由遊戲迴圈決定什麼時候畫，MTKView 自己不定時重畫
        view.isPaused = true
        view.enableSetNeedsDisplay = false
        view.framebufferOnly = true
        // 顏色標成 sRGB，和 SwiftUI 的顏色、調色盤一致
        (view.layer as? CAMetalLayer)?.colorspace = CGColorSpace(name: CGColorSpace.sRGB)
        scene.runner.onOutputs = onOutputs
        context.coordinator.attach(to: view, displayScale: context.environment.displayScale)
        return view
    }

    func updateUIView(_ view: MTKView, context: Context) {
        scene.runner.onOutputs = onOutputs
    }

    static func dismantleUIView(_ view: MTKView, coordinator: GameLoop) {
        coordinator.stop()
    }
}

/// 遊戲迴圈：跟著螢幕更新的節奏，最高到手機支援的更新率（作者 2026-11-16 決定）。
///
/// 只做畫面（ADR 0008）：每一格讀模擬最新的快照（模擬在自己的執行緒，這裡從不等它）→ 畫面準備交出繪製清單
/// → 清單和上一格不同才畫。沒有東西在動時暫停，省電；送了事件、模擬的樣子變了、手勢改了鏡頭時被叫醒，
/// 閒置後鏡頭該回去時到時間再醒來。畫面出現時開模擬的執行緒，拆掉時停下。
final class GameLoop: NSObject {
    let scene: RoomScene
    private weak var view: MTKView?
    private var renderer: SpriteRenderer?
    private var link: CADisplayLink?
    private var wakeTask: Task<Void, Never>?
    /// 暫停的時間點；量「暫停多久後醒來」用。
    private var pausedAt: CFTimeInterval?

    init(scene: RoomScene) {
        self.scene = scene
    }

    func attach(to view: MTKView, displayScale: Double) {
        self.view = view
        if let device = view.device {
            renderer = SpriteRenderer(device: device, pixelFormat: view.colorPixelFormat, polygons: scene.builder.polygons(),
                                      rigs: scene.builder.rigs(), displayScale: displayScale)
            view.delegate = renderer
        }
        let link = CADisplayLink(target: self, selector: #selector(tick(_:)))
        // 手機支援多高就跑多高；iPhone 11 是 60，ProMotion 機型可到 120（Info.plist 要有 CADisableMinimumFrameDurationOnPhone）
        link.preferredFrameRateRange = CAFrameRateRange(minimum: 30, maximum: 120, preferred: 120)
        link.add(to: .main, forMode: .common)
        self.link = link
        scene.builder.onChange = { [weak self] in self?.wake() }
        scene.runner.onWake = { [weak self] in self?.wake() }
        scene.runner.start()
        wake()
    }

    func stop() {
        wakeTask?.cancel()
        link?.invalidate()
        link = nil
        scene.runner.stop()
        scene.builder.onChange = {}
        scene.runner.onWake = {}
    }

    private func wake() {
        wakeTask?.cancel()
        wakeTask = nil
        if let pausedAt, link?.isPaused == true {
            let pausedMs = Int((CACurrentMediaTime() - pausedAt) * 1000)
            PerfSignposts.signposter.emitEvent("wake", "paused \(pausedMs) ms")
            self.pausedAt = nil
        }
        link?.isPaused = false
    }

    @objc private func tick(_ link: CADisplayLink) {
        let frame = PerfSignposts.signposter.beginInterval("frame")
        defer { PerfSignposts.signposter.endInterval("frame", frame) }
        let now = CACurrentMediaTime()
        let runner = scene.runner
        let latest = runner.latest
        let time = now - latest.epoch - 1 / Double(Simulation.ticksPerSecond)   // 比模擬晚一個節拍
        let prepared = PerfSignposts.measure("prepare") {
            scene.builder.build(previous: latest.previous, current: latest.current, at: time, now: now)
        }
        if let list = prepared.drawList, list != renderer?.drawList {
            renderer?.drawList = list
            PerfSignposts.measure("draw") { view?.draw() }
        }
        // 模擬還在動、鏡頭還在動，或畫面還沒追上最新的快照（落後一個節拍）：下一格繼續。
        // 站著的角色站滿時，模擬的執行緒會叫醒這裡，不用自己算時間
        guard !(runner.isActive || prepared.keepRunning || time < latest.current.time) else { return }
        link.isPaused = true
        pausedAt = now
        PerfSignposts.signposter.emitEvent("pause")
        if let wakeAt = prepared.wakeAt {
            wakeTask = Task { [weak self] in
                try? await Task.sleep(for: .seconds(max(0, wakeAt - now)))
                guard !Task.isCancelled else { return }
                self?.wake()
            }
        }
    }
}
