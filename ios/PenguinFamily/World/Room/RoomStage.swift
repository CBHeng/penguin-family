import CoreGraphics
import Foundation

/// 箱庭的即時狀態：鏡頭、縮放、每隻企鵝的位置與正在播的動作；每一格要畫哪些東西、點擊打中了哪一隻。
///
/// 純邏輯，不碰 Metal 與 SwiftUI 的畫面，可以單獨測試。時間（秒）由外面傳進來：
/// 遊戲迴圈（`GameLoop`）每一格呼叫 `update(now:)`，手勢由 `RoomView` 呼叫對應的方法。
/// 有變化才需要重畫（作者 2026-11-16 決定），所以每次改變都會通知 `onChange` 叫醒遊戲迴圈。
/// 企鵝用編號（0 起算）區分，順序和 `penguins` 相同。
final class RoomStage {
    /// 沒碰多久後鏡頭開始回到企鵝身邊（秒）。實機上調。
    static let idleSecondsBeforeReturn: Double = 5
    /// 回去時，以每秒 60 格計，每格走剩下距離的多少；更新率不同時換算成相同的速度。實機上調。
    static let returnStepPer60Hz: Double = 0.08

    /// 一隻企鵝的初始設定：造型（nil 表示用灰色剪影）與站的位置。
    struct PenguinSetup {
        let frames: CharacterFrames?
        let position: TilePosition
    }

    /// 要畫的一張圖是哪一張。企鵝的圖以編號區分，因為兩隻的造型不同。
    enum SpriteKey: Hashable, Sendable {
        case background
        case furniture(Int)
        case penguinRest(penguin: Int)
        case penguinFrame(penguin: Int, motion: String, frame: Int)
        case placeholder
    }

    /// 要畫的一張圖：放在箱庭圖上的哪裡（像素）。
    struct Sprite: Equatable, Sendable {
        let key: SpriteKey
        let x: Int
        let y: Int
        let width: Int
        let height: Int
    }

    /// 箱庭圖怎麼對到畫面：畫面左上角對著箱庭的哪一點（像素，已對齊螢幕實體像素），每個像素幾 pt。
    struct ViewTransform: Equatable, Sendable {
        let topLeftX: Double
        let topLeftY: Double
        let pointsPerPixel: Double
    }

    /// 每一格更新後，遊戲迴圈要做什麼。
    struct Tick: Equatable, Sendable {
        /// 畫面有變，要重畫。
        var draw = false
        /// 剛播完動作的企鵝編號，要回報給各自的 `Behavior`。
        var motionFinished: [Int] = []
        /// 還有東西在動，下一格要繼續跑；否則遊戲迴圈可以暫停。
        var keepRunning = false
        /// 暫停後要在這個時間醒來（例如閒置一段時間後鏡頭回到企鵝身邊）。
        var wakeAt: Double?
    }

    /// 一隻企鵝現在的樣子。
    private struct Penguin {
        let frames: CharacterFrames?
        var feet: PixelPoint
        var intent: PenguinBehavior.Intent?
        var playing: (motion: Motion, start: Double)?
        var currentFrame: Int?
    }

    let room: RoomLayout
    /// 有變化時呼叫，叫醒遊戲迴圈。
    var onChange: () -> Void = {}

    private let iso: IsoProjection
    private let furnitureSprites: [(sprite: Sprite, depth: Int)]
    private let roomBitmaps: [SpriteKey: PixelBitmap]
    private var penguins: [Penguin]
    /// 畫面大小（pt）與 1pt 幾個實體像素。還沒量到畫面大小前是 0。
    private(set) var viewport = CGSize.zero
    private(set) var displayScale = 1.0
    /// 每個箱庭像素畫成幾 pt。
    private(set) var zoom = RoomZoom.maxPointsPerPixel
    private(set) var camera: RoomCamera?

    /// 這次拖曳上一次的手指移動量；不在拖曳時是 nil。
    private var lastDrag: CGSize?
    /// 這次拖曳是從企鵝身上開始的：留給之後的「拎起來」，不捲動。
    private var dragStartedOnPenguin = false
    private var pinchStart: (zoom: Double, center: (x: Double, y: Double))?
    private var lastTouch = -Double.infinity
    private var lastUpdate: Double?
    private var needsDraw = true

    init(room: RoomLayout, penguins setups: [PenguinSetup]) {
        self.room = room
        let iso = IsoProjection(room: room)
        self.iso = iso
        penguins = setups.map { Penguin(frames: $0.frames, feet: iso.feet(at: $0.position)) }
        var bitmaps: [SpriteKey: PixelBitmap] = [.background: PixelBitmap(RoomRenderer.background(room),
                                                                          colors: RoomRenderer.colors)]
        var sprites: [(Sprite, Int)] = []
        for (i, item) in room.furniture.enumerated() {
            let (grid, origin) = RoomRenderer.sprite(for: item, in: room)
            bitmaps[.furniture(i)] = PixelBitmap(grid, colors: RoomRenderer.colors)
            sprites.append((Sprite(key: .furniture(i), x: origin.x, y: origin.y, width: grid.width, height: grid.height),
                            RoomRenderer.depth(of: item, in: room)))
        }
        roomBitmaps = bitmaps
        furnitureSprites = sprites
    }

    /// 有幾隻企鵝。
    var penguinCount: Int { penguins.count }

    /// 某隻企鵝的腳底在箱庭圖上的位置（像素）。
    func feet(of penguin: Int) -> PixelPoint { penguins[penguin].feet }

    // MARK: - 貼圖

    /// 所有可能用到的圖；繪圖層載入時一次全部送進 GPU（用首次載入換順暢）。
    func allBitmaps() -> [SpriteKey: PixelBitmap] {
        var all = roomBitmaps
        for (index, penguin) in penguins.enumerated() {
            guard let frames = penguin.frames else {
                all[.placeholder] = PlaceholderSilhouette.bitmap
                continue
            }
            all[.penguinRest(penguin: index)] = frames.rest
            for motion in Motion.all {
                for frame in 0..<frames.frameCount(of: motion) {
                    all[.penguinFrame(penguin: index, motion: motion.name, frame: frame)] = frames.image(motion, frame: frame)
                }
            }
        }
        return all
    }

    // MARK: - 外面告訴我們的事

    /// 畫面大小改變（第一次出現、旋轉）。第一次時鏡頭對準企鵝；之後保留原本對著的點，縮放重新限制在範圍內。
    func resize(viewport size: CGSize, displayScale scale: Double) {
        guard size.width > 0, size.height > 0 else { return }
        let first = camera == nil
        viewport = size
        displayScale = scale
        let limits = zoomLimits()
        zoom = first ? limits.clamped(zoom) : limits.snapped(zoom)
        let center = camera.map { (x: $0.centerX, y: $0.centerY) } ?? focus
        camera = makeCamera(center: center)
        changed()
    }

    func setIntent(_ newIntent: PenguinBehavior.Intent, for penguin: Int, now: Double) {
        guard penguins.indices.contains(penguin), newIntent != penguins[penguin].intent else { return }
        penguins[penguin].intent = newIntent
        penguins[penguin].playing = Self.motion(for: newIntent).map { ($0, now) }
        changed()
    }

    func setPosition(_ position: TilePosition, for penguin: Int) {
        guard penguins.indices.contains(penguin) else { return }
        penguins[penguin].feet = iso.feet(at: position)
        changed()
    }

    /// 意圖要播哪個動作；待機不播。
    static func motion(for intent: PenguinBehavior.Intent) -> Motion? {
        switch intent {
        case .idle: nil
        case .hello: .hello
        }
    }

    // MARK: - 手勢（座標是畫面上的 pt，左上角為原點）

    /// 這一點點到哪一隻企鵝；沒點到是 nil。觸控範圍是整張企鵝圖，比企鵝本身大一圈。
    /// 兩隻重疊時，畫在前面（離主人近）的那隻優先。
    func penguin(at point: CGPoint) -> Int? {
        guard let transform = viewTransform else { return nil }
        let x = transform.topLeftX + point.x / transform.pointsPerPixel
        let y = transform.topLeftY + point.y / transform.pointsPerPixel
        // 和 `sprites()` 的順序相反：深度大的先；深度相同時，編號大的畫在後面，也就是在前面
        let frontFirst = penguins.indices.sorted { (penguins[$0].feet.y, $0) > (penguins[$1].feet.y, $1) }
        return frontFirst.first { index in
            let p = sprite(of: index)
            return x >= Double(p.x) && x < Double(p.x + p.width) && y >= Double(p.y) && y < Double(p.y + p.height)
        }
    }

    /// 主人碰了箱庭（例如點企鵝）：重新計算閒置。
    func ownerTouched(now: Double) {
        lastTouch = now
        changed()
    }

    /// 拖曳中：每次只套用和上一次相比移了多少，捏合中不捲動，捏完剩一根手指拖也不跳。
    func panChanged(translation: CGSize, startLocation: CGPoint, now: Double) {
        if lastDrag == nil { dragStartedOnPenguin = penguin(at: startLocation) != nil }
        let last = lastDrag ?? .zero
        lastDrag = translation
        lastTouch = now
        guard !dragStartedOnPenguin, pinchStart == nil, var moved = camera else { return }
        // 手指往右拖，畫面往右移，也就是鏡頭往左
        moved.moveTo(x: moved.centerX - (translation.width - last.width) / zoom,
                     y: moved.centerY - (translation.height - last.height) / zoom)
        camera = moved
        changed()
    }

    func panEnded(now: Double) {
        lastDrag = nil
        dragStartedOnPenguin = false
        lastTouch = now
        changed()
    }

    /// 捏合中：連續縮放，以捏合開始的位置為中心。
    func pinchChanged(magnification: Double, anchor: CGPoint, now: Double) {
        guard let current = camera else { return }
        let start = pinchStart ?? (zoom, (current.centerX, current.centerY))
        pinchStart = start
        lastTouch = now
        apply(zoom: zoomLimits().clamped(start.zoom * magnification), from: start, anchor: anchor)
    }

    /// 放開：吸附到整數個實體像素。
    func pinchEnded(magnification: Double, anchor: CGPoint, now: Double) {
        if let start = pinchStart {
            apply(zoom: zoomLimits().snapped(start.zoom * magnification), from: start, anchor: anchor)
        }
        pinchStart = nil
        lastTouch = now
        changed()
    }

    // MARK: - 每一格

    /// 遊戲迴圈每一格呼叫：推進每隻的動作、閒置後把鏡頭移回企鵝身邊，回報要不要重畫、要不要繼續跑。
    func update(now: Double) -> Tick {
        var tick = Tick()
        let elapsed = lastUpdate.map { min(max(now - $0, 0), 0.1) } ?? (1.0 / 60)
        lastUpdate = now

        for index in penguins.indices {
            if let p = penguins[index].playing, now - p.start >= p.motion.duration {
                penguins[index].playing = nil
                tick.motionFinished.append(index)
            }
            let frame = penguins[index].playing.map { Int(((now - $0.start) * $0.motion.framesPerSecond).rounded(.down)) }
            if frame != penguins[index].currentFrame {
                penguins[index].currentFrame = frame
                needsDraw = true
            }
        }

        var returning = false
        if var cam = camera {
            let target = focus
            let idle = now - lastTouch >= Self.idleSecondsBeforeReturn
            if idle, lastDrag == nil, pinchStart == nil {
                // 每格走剩下距離的一部分；很近時直接到位（最後一小段也要補上）
                let fraction = 1 - pow(1 - Self.returnStepPer60Hz, elapsed * 60)
                returning = !cam.approach(x: target.x, y: target.y, fraction: fraction)
                if cam != camera {
                    camera = cam
                    needsDraw = true
                }
            } else if !idle {
                var probe = cam
                if !probe.approach(x: target.x, y: target.y, fraction: 0) || probe != cam {
                    tick.wakeAt = lastTouch + Self.idleSecondsBeforeReturn
                }
            }
        }

        tick.draw = needsDraw
        needsDraw = false
        let anyPlaying = penguins.contains { $0.playing != nil }
        tick.keepRunning = anyPlaying || returning || lastDrag != nil || pinchStart != nil
        if tick.keepRunning {
            tick.wakeAt = nil
        } else {
            // 暫停後再醒來時，不把暫停的時間算成一大步
            lastUpdate = nil
        }
        return tick
    }

    // MARK: - 要畫什麼

    /// 畫面左上角對著箱庭哪一點；還沒量到畫面大小前是 nil。
    var viewTransform: ViewTransform? {
        guard let camera else { return nil }
        let topLeft = camera.topLeft(step: 1 / (zoom * displayScale))
        return ViewTransform(topLeftX: topLeft.x, topLeftY: topLeft.y, pointsPerPixel: zoom)
    }

    /// 這一格要畫的圖，由遠到近：背景先畫，越靠近主人（畫面越下方）畫在越前面。
    func sprites() -> [Sprite] {
        var items: [(id: Sprite, depth: Int)] = furnitureSprites.map { ($0.sprite, $0.depth) }
        for index in penguins.indices {
            items.append((sprite(of: index), penguins[index].feet.y))
        }
        let background = Sprite(key: .background, x: 0, y: 0, width: iso.canvasWidth, height: iso.canvasHeight)
        return [background] + RoomRenderer.drawOrder(items)
    }

    private func sprite(of index: Int) -> Sprite {
        let penguin = penguins[index]
        guard let frames = penguin.frames else {
            let a = PlaceholderSilhouette.anchor, g = PlaceholderSilhouette.grid
            return Sprite(key: .placeholder, x: penguin.feet.x - a.x, y: penguin.feet.y - a.y,
                          width: g.width, height: g.height)
        }
        var key = SpriteKey.penguinRest(penguin: index)
        if let playing = penguin.playing, let frame = penguin.currentFrame, frame < frames.frameCount(of: playing.motion) {
            key = .penguinFrame(penguin: index, motion: playing.motion.name, frame: max(0, frame))
        }
        return Sprite(key: key, x: penguin.feet.x - frames.anchor.x, y: penguin.feet.y - frames.anchor.y,
                      width: frames.width, height: frames.height)
    }

    // MARK: - 小工具

    /// 鏡頭要回到哪裡：所有企鵝身體中央的中點（腳底上方約 16 像素）。沒有企鵝時是箱庭中央。
    private var focus: (x: Double, y: Double) {
        guard !penguins.isEmpty else { return (Double(iso.canvasWidth) / 2, Double(iso.canvasHeight) / 2) }
        let n = Double(penguins.count)
        let x = penguins.reduce(0.0) { $0 + Double($1.feet.x) } / n
        let y = penguins.reduce(0.0) { $0 + Double($1.feet.y - 16) } / n
        return (x, y)
    }

    private func zoomLimits() -> RoomZoom {
        RoomZoom(viewportWidth: viewport.width, canvasWidth: Double(iso.canvasWidth), displayScale: displayScale)
    }

    private func makeCamera(center: (x: Double, y: Double)) -> RoomCamera {
        RoomCamera(canvasWidth: Double(iso.canvasWidth), canvasHeight: Double(iso.canvasHeight),
                   viewportWidth: viewport.width / zoom, viewportHeight: viewport.height / zoom,
                   centerX: center.x, centerY: center.y)
    }

    private func apply(zoom newZoom: Double, from start: (zoom: Double, center: (x: Double, y: Double)), anchor: CGPoint) {
        let center = RoomZoom.center(keeping: (anchor.x, anchor.y), center: start.center,
                                     viewport: (viewport.width, viewport.height), from: start.zoom, to: newZoom)
        zoom = newZoom
        camera = makeCamera(center: center)
        changed()
    }

    private func changed() {
        needsDraw = true
        onChange()
    }
}
