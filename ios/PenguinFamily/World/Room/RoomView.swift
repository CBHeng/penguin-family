import CoreGraphics
import SwiftUI

/// 一個區域的等角箱庭：背景、家具與企鵝，依前後排序疊起來，每個像素 3pt。
///
/// 捲動目前先用系統的 ScrollView 左右看；A1 第 2 項改成自訂鏡頭（拖曳空地捲動、閒置時回到企鵝身邊）。
struct RoomView: View {
    static let pointsPerPixel: CGFloat = 3

    let room: RoomLayout
    let character: RigCompositor?
    /// 企鵝站在地板的哪一點（格）。
    let penguinPosition: TilePosition
    let intent: PenguinBehavior.Intent
    var onTap: () -> Void = {}
    var onMotionFinished: () -> Void = {}

    @State private var art: RoomArt

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
        ScrollView(.horizontal) {
            ZStack(alignment: .topLeading) {
                PixelImageView(image: art.background, pixelWidth: iso.canvasWidth, pixelHeight: iso.canvasHeight,
                               pointsPerPixel: ppp)
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
                                    onTap: onTap, onMotionFinished: onMotionFinished)
                            .offset(x: CGFloat(feet.x - anchor.x) * ppp, y: CGFloat(feet.y - anchor.y) * ppp)
                    }
                }
            }
            .frame(width: CGFloat(iso.canvasWidth) * ppp, height: CGFloat(iso.canvasHeight) * ppp, alignment: .topLeading)
            .frame(maxHeight: .infinity)  // 箱庭比畫面矮，上下置中
        }
        .defaultScrollAnchor(.center)
        .scrollIndicators(.hidden)
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
