import MetalKit
import os
import SwiftUI

/// 把 Metal 的畫面放進 SwiftUI。畫面本身不會移動，鏡頭、縮放都在繪圖時處理。
struct MetalRoomView: UIViewRepresentable {
    let stage: RoomStage
    /// 某隻企鵝的動作播完了。
    var onMotionFinished: (PenguinID) -> Void

    func makeCoordinator() -> GameLoop {
        GameLoop(stage: stage)
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
        context.coordinator.onMotionFinished = onMotionFinished
        context.coordinator.attach(to: view)
        return view
    }

    func updateUIView(_ view: MTKView, context: Context) {
        context.coordinator.onMotionFinished = onMotionFinished
    }

    static func dismantleUIView(_ view: MTKView, coordinator: GameLoop) {
        coordinator.stop()
    }
}

/// 遊戲迴圈：跟著螢幕更新的節奏，最高到手機支援的更新率（作者 2026-11-16 決定）。
///
/// 每一格問 `RoomStage` 有沒有變化，有才畫；沒有東西在動時暫停，省電。
/// `RoomStage` 一有變化就叫醒它；閒置等待鏡頭回去時，到時間再醒來。
final class GameLoop: NSObject {
    let stage: RoomStage
    var onMotionFinished: (PenguinID) -> Void = { _ in }
    private weak var view: MTKView?
    private var renderer: SpriteRenderer?
    private var link: CADisplayLink?
    private var wakeTask: Task<Void, Never>?
    /// 暫停的時間點；量「暫停多久後醒來」用。
    private var pausedAt: CFTimeInterval?

    init(stage: RoomStage) {
        self.stage = stage
    }

    func attach(to view: MTKView) {
        self.view = view
        if let device = view.device {
            renderer = SpriteRenderer(device: device, pixelFormat: view.colorPixelFormat, stage: stage)
            view.delegate = renderer
        }
        let link = CADisplayLink(target: self, selector: #selector(tick(_:)))
        // 手機支援多高就跑多高；iPhone 11 是 60，ProMotion 機型可到 120（Info.plist 要有 CADisableMinimumFrameDurationOnPhone）
        link.preferredFrameRateRange = CAFrameRateRange(minimum: 30, maximum: 120, preferred: 120)
        link.add(to: .main, forMode: .common)
        self.link = link
        stage.onChange = { [weak self] in self?.wake() }
        wake()
    }

    func stop() {
        wakeTask?.cancel()
        link?.invalidate()
        link = nil
        stage.onChange = {}
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
        let tick = PerfSignposts.measure("update") { stage.update(now: now) }
        for penguin in tick.motionFinished { onMotionFinished(penguin) }
        if tick.draw { PerfSignposts.measure("draw") { view?.draw() } }
        guard !tick.keepRunning else { return }
        link.isPaused = true
        pausedAt = now
        PerfSignposts.signposter.emitEvent("pause")
        if let wakeAt = tick.wakeAt {
            wakeTask = Task { [weak self] in
                try? await Task.sleep(for: .seconds(max(0, wakeAt - now)))
                guard !Task.isCancelled else { return }
                self?.wake()
            }
        }
    }
}
