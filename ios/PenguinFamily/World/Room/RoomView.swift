import CoreGraphics
import SwiftUI

/// 一個區域的等角箱庭：背景、家具與企鵝，依前後排序疊起來。
///
/// 鏡頭：打開時對準企鵝；拖曳空地捲動（從企鵝身上開始拖不捲動，留給之後的「拎起來」）；
/// 一段時間沒碰，鏡頭慢慢移回企鵝身邊（遊戲設計 2026-11-16）。
/// 縮放：雙指捏合，最大每個像素 3pt，最小房間左右塞滿畫面；放開後吸附到整數個實體像素（見 `RoomZoom`）。
struct RoomView: View {
    /// 沒碰多久後鏡頭開始回到企鵝身邊（秒）。實機上調。
    static let idleSecondsBeforeReturn: Double = 5
    /// 回去時每一格畫面走剩下距離的多少，越大越快。實機上調。
    static let returnStep: Double = 0.08

    let room: RoomLayout
    let character: CharacterFrames?
    /// 企鵝站在地板的哪一點（格）。
    let penguinPosition: TilePosition
    let intent: PenguinBehavior.Intent
    var onTap: () -> Void = {}
    var onMotionFinished: () -> Void = {}

    @State private var art: RoomArt
    @State private var camera: RoomCamera?
    /// 每個箱庭像素畫成幾 pt。
    @State private var zoom = RoomZoom.maxPointsPerPixel
    /// 這次拖曳上一次回報的手指移動量；不在拖曳時是 nil。
    @State private var lastDrag: CGSize?
    /// 捏合開始時的縮放與鏡頭中心；不在捏合時是 nil。
    @State private var pinchStart: (zoom: Double, center: (x: Double, y: Double))?
    /// 主人最後一次碰箱庭的時間；改變時重新計算閒置。
    @State private var lastTouch = Date.now
    /// 1pt 等於幾個螢幕實體像素（iPhone 17 是 3，iPhone 11 是 2）。
    @Environment(\.displayScale) private var displayScale

    init(room: RoomLayout, character: CharacterFrames?, penguinPosition: TilePosition, intent: PenguinBehavior.Intent,
         onTap: @escaping () -> Void = {}, onMotionFinished: @escaping () -> Void = {}) {
        self.room = room
        self.character = character
        self.penguinPosition = penguinPosition
        self.intent = intent
        self.onTap = onTap
        self.onMotionFinished = onMotionFinished
        _art = State(initialValue: RoomArt(room))
    }

    private enum Item: Hashable {
        case furniture(Int)
        case penguin
    }

    /// 拖曳量要以不會動的外框為基準。手勢掛在會跟著鏡頭移動的背景圖上，若用預設的 `.local`，
    /// 背景一移動，量到的拖曳量就跟著變，鏡頭在兩個位置間來回跳（2026-11-16 模擬器上看到閃爍）。
    private static let viewportSpace = "RoomViewport"

    var body: some View {
        let ppp = CGFloat(zoom)
        let iso = IsoProjection(room: room)
        let feet = iso.feet(at: penguinPosition)
        GeometryReader { proxy in
            let cam = camera ?? makeCamera(viewport: proxy.size, center: focus(feet))
            let topLeft = cam.topLeft(step: 1 / (zoom * displayScale))
            ZStack(alignment: .topLeading) {
                PixelImageView(image: art.background, pixelWidth: iso.canvasWidth, pixelHeight: iso.canvasHeight,
                               pointsPerPixel: ppp)
                    .gesture(panGesture(from: cam))
                ForEach(drawOrder(feet: feet), id: \.self) { item in
                    switch item {
                    case .furniture(let i):
                        let sprite = art.furniture[i]
                        PixelImageView(image: sprite.image, pixelWidth: sprite.width, pixelHeight: sprite.height,
                                       pointsPerPixel: ppp)
                            .offset(x: CGFloat(sprite.origin.x) * ppp, y: CGFloat(sprite.origin.y) * ppp)
                            .allowsHitTesting(false)
                    case .penguin:
                        let anchor = PenguinView.anchor(for: character)
                        PenguinView(character: character, intent: intent, pointsPerPixel: ppp,
                                    onTap: { lastTouch = .now; onTap() }, onMotionFinished: onMotionFinished)
                            .offset(x: CGFloat(feet.x - anchor.x) * ppp, y: CGFloat(feet.y - anchor.y) * ppp)
                    }
                }
            }
            .frame(width: CGFloat(iso.canvasWidth) * ppp, height: CGFloat(iso.canvasHeight) * ppp, alignment: .topLeading)
            .offset(x: -topLeft.x * ppp, y: -topLeft.y * ppp)
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .topLeading)
            .clipped()
            // 縮到最小時上下是空的，也要能捏
            .contentShape(Rectangle())
            .simultaneousGesture(pinchGesture(viewport: proxy.size, from: cam))
            .coordinateSpace(.named(Self.viewportSpace))
            .onAppear {
                let fitted = limits(viewport: proxy.size).clamped(zoom)
                zoom = fitted
                camera = makeCamera(viewport: proxy.size, center: focus(feet), zoom: fitted)
            }
            .onChange(of: proxy.size) { _, size in
                // 畫面大小改變（例如旋轉）時保留原本對著的點，縮放也重新限制在範圍內
                let old = camera ?? cam
                let fitted = limits(viewport: size).snapped(zoom)
                zoom = fitted
                camera = makeCamera(viewport: size, center: (old.centerX, old.centerY), zoom: fitted)
            }
            .task(id: lastTouch) { await returnToPenguin(feet: feet) }
        }
    }

    /// 企鵝身體的中央，大約在腳底上方 16 像素。
    private func focus(_ feet: PixelPoint) -> (x: Double, y: Double) {
        (Double(feet.x), Double(feet.y - 16))
    }

    private func limits(viewport: CGSize) -> RoomZoom {
        RoomZoom(viewportWidth: viewport.width, canvasWidth: Double(IsoProjection(room: room).canvasWidth),
                 displayScale: displayScale)
    }

    /// - Parameters:
    ///   - center: 鏡頭中心（箱庭像素）。
    ///   - zoom: 每個箱庭像素幾 pt；不給時用目前的縮放。
    private func makeCamera(viewport: CGSize, center: (x: Double, y: Double), zoom: Double? = nil) -> RoomCamera {
        let iso = IsoProjection(room: room)
        let ppp = zoom ?? self.zoom
        return RoomCamera(canvasWidth: Double(iso.canvasWidth), canvasHeight: Double(iso.canvasHeight),
                          viewportWidth: viewport.width / ppp, viewportHeight: viewport.height / ppp,
                          centerX: center.x, centerY: center.y)
    }

    /// 拖曳空地捲動：手指往右拖，畫面往右移，也就是鏡頭往左。
    ///
    /// 每次只套用「和上一次相比移了多少」：捏合中不捲動，捏合結束剩一根手指繼續拖時，畫面也不會跳。
    private func panGesture(from cam: RoomCamera) -> some Gesture {
        DragGesture(coordinateSpace: .named(Self.viewportSpace))
            .onChanged { value in
                let last = lastDrag ?? .zero
                lastDrag = value.translation
                guard pinchStart == nil else { return }
                var moved = camera ?? cam
                moved.moveTo(x: moved.centerX - (value.translation.width - last.width) / zoom,
                             y: moved.centerY - (value.translation.height - last.height) / zoom)
                camera = moved
            }
            .onEnded { _ in
                lastDrag = nil
                lastTouch = .now
            }
    }

    /// 雙指捏合縮放：以捏合開始的位置為中心，手指下面那一點留在原地。
    private func pinchGesture(viewport: CGSize, from cam: RoomCamera) -> some Gesture {
        MagnifyGesture()
            .onChanged { value in
                let range = limits(viewport: viewport)
                let current = camera ?? cam
                let start = pinchStart ?? (zoom, (current.centerX, current.centerY))
                pinchStart = start
                apply(zoom: range.clamped(start.zoom * value.magnification), from: start,
                      anchor: value.startLocation, viewport: viewport)
            }
            .onEnded { value in
                if let start = pinchStart {
                    let range = limits(viewport: viewport)
                    apply(zoom: range.snapped(start.zoom * value.magnification), from: start,
                          anchor: value.startLocation, viewport: viewport)
                }
                pinchStart = nil
                lastTouch = .now
            }
    }

    private func apply(zoom newZoom: Double, from start: (zoom: Double, center: (x: Double, y: Double)),
                       anchor: CGPoint, viewport: CGSize) {
        let center = RoomZoom.center(keeping: (anchor.x, anchor.y), center: start.center,
                                     viewport: (viewport.width, viewport.height), from: start.zoom, to: newZoom)
        zoom = newZoom
        camera = makeCamera(viewport: viewport, center: center, zoom: newZoom)
    }

    /// 閒置一段時間後，鏡頭一格一格靠回企鵝身邊；主人再碰就中斷。縮放維持不變。
    private func returnToPenguin(feet: PixelPoint) async {
        do {
            try await Task.sleep(for: .seconds(Self.idleSecondsBeforeReturn))
        } catch {
            return
        }
        let target = focus(feet)
        while !Task.isCancelled, lastDrag == nil, pinchStart == nil, var moving = camera {
            let arrived = moving.approach(x: target.x, y: target.y, fraction: Self.returnStep)
            camera = moving
            if arrived { return }
            do {
                try await Task.sleep(for: .milliseconds(16))
            } catch {
                return
            }
        }
    }

    /// 由遠到近：越靠近主人（畫面越下方）畫在越前面。
    private func drawOrder(feet: PixelPoint) -> [Item] {
        var items: [(id: Item, depth: Int)] = art.furniture.indices.map { (.furniture($0), art.furniture[$0].depth) }
        items.append((.penguin, feet.y))
        return RoomRenderer.drawOrder(items)
    }
}

/// 箱庭裡不會變的圖，只算一次。
private struct RoomArt {
    struct Sprite {
        let image: CGImage?
        let width: Int
        let height: Int
        let origin: PixelPoint
        let depth: Int
    }

    let background: CGImage?
    let furniture: [Sprite]

    init(_ room: RoomLayout) {
        background = PixelImage.cgImage(RoomRenderer.background(room), colors: RoomRenderer.colors)
        furniture = room.furniture.map { item in
            let (grid, origin) = RoomRenderer.sprite(for: item, in: room)
            return Sprite(image: PixelImage.cgImage(grid, colors: RoomRenderer.colors),
                          width: grid.width, height: grid.height, origin: origin,
                          depth: RoomRenderer.depth(of: item, in: room))
        }
    }
}

#Preview("沒有角色包") {
    RoomView(room: .indoor, character: nil, penguinPosition: TilePosition(i: 4.5, j: 4.5), intent: .idle)
}
