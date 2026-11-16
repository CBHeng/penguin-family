import CoreGraphics
import SwiftUI

/// 一個區域的等角箱庭：背景、家具與企鵝，依前後排序疊起來，每個像素 3pt。
///
/// 鏡頭：打開時對準企鵝；拖曳空地捲動（從企鵝身上開始拖不捲動，留給之後的「拎起來」）；
/// 一段時間沒碰，鏡頭慢慢移回企鵝身邊（遊戲設計 2026-11-16）。
struct RoomView: View {
    static let pointsPerPixel: CGFloat = 3
    /// 沒碰多久後鏡頭開始回到企鵝身邊（秒）。實機上調。
    static let idleSecondsBeforeReturn: Double = 5
    /// 回去時每一格畫面走剩下距離的多少，越大越快。實機上調。
    static let returnStep: Double = 0.08

    let room: RoomLayout
    let character: RigCompositor?
    /// 企鵝站在地板的哪一點（格）。
    let penguinPosition: TilePosition
    let intent: PenguinBehavior.Intent
    var onTap: () -> Void = {}
    var onMotionFinished: () -> Void = {}

    @State private var art: RoomArt
    @State private var camera: RoomCamera?
    /// 拖曳開始時鏡頭對著的點；不在拖曳時是 nil。
    @State private var dragStart: (x: Double, y: Double)?
    /// 主人最後一次碰箱庭的時間；改變時重新計算閒置。
    @State private var lastTouch = Date.now

    init(room: RoomLayout, character: RigCompositor?, penguinPosition: TilePosition, intent: PenguinBehavior.Intent,
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

    var body: some View {
        let ppp = Self.pointsPerPixel
        let iso = IsoProjection(room: room)
        let feet = iso.feet(at: penguinPosition)
        GeometryReader { proxy in
            let cam = camera ?? makeCamera(viewport: proxy.size, focus: feet)
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
            .offset(x: -CGFloat(cam.topLeft.x) * ppp, y: -CGFloat(cam.topLeft.y) * ppp)
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .topLeading)
            .clipped()
            .onAppear { camera = makeCamera(viewport: proxy.size, focus: feet) }
            .onChange(of: proxy.size) { _, size in
                // 畫面大小改變（例如旋轉）時保留原本對著的點
                let old = camera ?? cam
                camera = makeCamera(viewport: size, focus: feet, center: (old.centerX, old.centerY))
            }
            .task(id: lastTouch) { await returnToPenguin(feet: feet) }
        }
    }

    /// 企鵝身體的中央，大約在腳底上方 16 像素。
    private func focus(_ feet: PixelPoint) -> (x: Double, y: Double) {
        (Double(feet.x), Double(feet.y - 16))
    }

    private func makeCamera(viewport: CGSize, focus feet: PixelPoint, center: (Double, Double)? = nil) -> RoomCamera {
        let iso = IsoProjection(room: room)
        let target = center ?? focus(feet)
        return RoomCamera(canvasWidth: Double(iso.canvasWidth), canvasHeight: Double(iso.canvasHeight),
                          viewportWidth: viewport.width / Self.pointsPerPixel,
                          viewportHeight: viewport.height / Self.pointsPerPixel,
                          centerX: target.0, centerY: target.1)
    }

    /// 拖曳空地捲動：手指往右拖，畫面往右移，也就是鏡頭往左。
    private func panGesture(from cam: RoomCamera) -> some Gesture {
        DragGesture()
            .onChanged { value in
                let start = dragStart ?? (cam.centerX, cam.centerY)
                dragStart = start
                var moved = camera ?? cam
                moved.moveTo(x: start.x - value.translation.width / Self.pointsPerPixel,
                             y: start.y - value.translation.height / Self.pointsPerPixel)
                camera = moved
            }
            .onEnded { _ in
                dragStart = nil
                lastTouch = .now
            }
    }

    /// 閒置一段時間後，鏡頭一格一格靠回企鵝身邊；主人再碰就中斷。
    private func returnToPenguin(feet: PixelPoint) async {
        do {
            try await Task.sleep(for: .seconds(Self.idleSecondsBeforeReturn))
        } catch {
            return
        }
        let target = focus(feet)
        while !Task.isCancelled, dragStart == nil, var moving = camera {
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
