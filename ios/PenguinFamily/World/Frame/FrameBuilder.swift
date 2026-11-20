import CoreGraphics
import Foundation

/// 畫面準備（ADR 0008）：每次螢幕更新，拿模擬最近兩份快照內插出這一格的樣子，交出繪製清單給 render；點擊判斷也在這裡。
///
/// - **內插**：畫的時間點比模擬晚一個節拍，落在兩份快照之間；位置與移動的步態依比例算，動作照「畫的時間 − 開始的時間」播片段。
/// - **呈現狀態只在這裡**：鏡頭、縮放、進行中的手勢、閒置計時。丟掉也能從快照重新算出來，不影響模擬。
/// - **不改世界狀態、不做遊戲判斷**：點到哪一隻只回報身分，送進模擬的是外面（`RoomScene`）。
/// - **前後順序**：家具依「最靠近主人的角」排；角色依腳底高度插進去，再照和家具的格子關係修正（2026-11-18）：
///   長家具（例如佔三格的沙發）最近的角很低，只比腳底高度的話，站在它旁邊前方的角色會被畫到後面。
/// - **不分物種**（ADR 0009）：照每隻的動作資料找片段、播到這一刻，不知道是哪種動物、哪個動作。造型沒有某個方向時
///   （例如灰色剪影沒有斜向）面向鏡頭。缺角色包的替身在交給這裡之前就換好了（`StandIn`）。
/// - **鏡頭**：一開始對準第一隻的身體中央；閒置後慢慢回到第一隻身邊（作者 2026-11-19 決定），第一隻不在台上時看下一隻。
///
/// 在主執行緒用。手勢改了呈現狀態時呼叫 `onChange` 叫醒遊戲迴圈。時間由外面給（模擬的時間與真實時間），可以單獨測試。
final class FrameBuilder {
    /// 沒碰多久後鏡頭開始回到第一隻身邊（秒）。實機上調。
    static let idleSecondsBeforeReturn: Double = 5
    /// 回去時，以每秒 60 格計，每格走剩下距離的多少；更新率不同時換算成相同的速度。實機上調。
    static let returnStepPer60Hz: Double = 0.08

    /// 後台名單的一隻：身分、造型與動作。名單的順序就是一家的順序，最前面的是第一隻。
    struct CastMember {
        let id: CharacterID
        /// 向量造型（ADR 0007）；缺角色包的已經換成替身或灰色剪影（`StandIn`）。
        var vector: VectorRig = .placeholder
        /// 這隻的動作資料：一次性動作與步態的片段。
        var motions: CharacterMotions = .placeholder
    }

    /// 要畫的一樣東西：蓋住箱庭上的哪個範圍（單位，可以有小數）。
    /// 角色是角色畫布放在這裡、照 `pose` 轉動部件；多邊形本身就帶位置，範圍只是外接矩形。
    struct Sprite: Equatable {
        let key: DrawKey
        let x: Double
        let y: Double
        let width: Double
        let height: Double
        /// 角色這一格的方向與每個部件的樣子；其他是 nil。
        var pose: CharacterPose? = nil
    }

    /// 箱庭怎麼對到畫面：畫面左上角對著箱庭的哪一點（單位），每個單位幾 pt。
    struct ViewTransform: Equatable {
        let topLeftX: Double
        let topLeftY: Double
        let pointsPerUnit: Double
    }

    /// 這一格準備好的東西。
    struct Frame {
        /// 由遠到近要畫的東西。
        let sprites: [Sprite]
        /// 交給 render 的繪製清單；還沒量到畫面大小前是 nil。
        let drawList: DrawList?
        /// 鏡頭還在動或手勢進行中：下一格要繼續。
        let keepRunning: Bool
        /// 停下來之後，鏡頭該回去的時間（真實時間）；不用回去是 nil。
        let wakeAt: Double?
    }

    /// 這一格的一隻角色：第幾個上台、站在哪、長什麼樣子。
    private struct Placed {
        let id: CharacterID
        let order: Int
        let position: TilePosition
        let feet: ScenePoint
        let pose: CharacterPose
    }

    let room: RoomLayout
    /// 呈現狀態變了（拖曳、捏合、畫面大小）時呼叫，叫醒遊戲迴圈。
    var onChange: () -> Void = {}

    private let iso: IsoProjection
    private let furnitureSprites: [(sprite: Sprite, depth: Int)]
    private let roomPolygons: [DrawKey: [ColoredPolygon]]
    /// 後台名單，依給的順序。
    private let cast: [CastMember]
    /// 後台名單每一隻的造型與動作。
    private let castRigs: [CharacterID: VectorRig]
    private let castMotions: [CharacterID: CharacterMotions]
    /// 畫面大小（pt）與 1pt 幾個實體像素。還沒量到畫面大小前是 0。
    private(set) var viewport = CGSize.zero
    private(set) var displayScale = 1.0
    /// 每個單位畫成幾 pt。
    private(set) var zoom = RoomZoom.maxPointsPerUnit
    private(set) var camera: RoomCamera?

    /// 鏡頭要對著的點：第一隻的身體中央；還沒準備過畫面時是箱庭中央。
    private var focus: (x: Double, y: Double)
    /// 準備過至少一格。
    private var hasBuilt = false
    /// 鏡頭在第一格之前就建好了（先量到畫面大小）：第一格時再對準第一隻。
    private var needsFocus = false
    /// 這次拖曳上一次的手指移動量；不在拖曳時是 nil。
    private var lastDrag: CGSize?
    /// 這次拖曳是從角色身上開始的：留給之後的「拎起來」，不捲動。
    private var dragStartedOnCharacter = false
    private var pinchStart: (zoom: Double, center: (x: Double, y: Double))?
    private var lastTouch = -Double.infinity
    private var lastBuild: Double?
    /// 上一格畫的角色，前面（離主人近）的在前；點擊判斷用。
    private var lastCharacters: [Sprite] = []

    init(room: RoomLayout, cast: [CastMember]) {
        self.room = room
        self.cast = cast
        castRigs = Dictionary(uniqueKeysWithValues: cast.map { ($0.id, $0.vector) })
        castMotions = Dictionary(uniqueKeysWithValues: cast.map { ($0.id, $0.motions) })
        let iso = IsoProjection(room: room)
        self.iso = iso
        focus = (Double(iso.canvasWidth) / 2, Double(iso.canvasHeight) / 2)
        var polygons: [DrawKey: [ColoredPolygon]] = [.background: RoomRenderer.background(room)]
        var sprites: [(Sprite, Int)] = []
        for (i, item) in room.furniture.enumerated() {
            let shape = RoomRenderer.furniture(item, in: room)
            let b = RoomRenderer.bounds(shape)
            polygons[.furniture(i)] = shape
            sprites.append((Sprite(key: .furniture(i), x: b.minX, y: b.minY, width: b.maxX - b.minX, height: b.maxY - b.minY),
                            RoomRenderer.depth(of: item, in: room)))
        }
        roomPolygons = polygons
        furnitureSprites = sprites
    }

    // MARK: - render 載入時要的東西

    /// 箱庭的多邊形：背景與每件家具。render 載入時一次切成三角形送進 GPU。
    func polygons() -> [DrawKey: [ColoredPolygon]] { roomPolygons }

    /// 後台名單每一隻的造型（沒有角色包的是替身），包含還沒上台的；render 載入時一次把部件畫成貼圖。
    func rigs() -> [CharacterID: VectorRig] { castRigs }

    // MARK: - 每一格

    /// 準備這一格：`previous`、`current` 是模擬最近兩份快照，`time` 是要畫的模擬時間（比最新的晚一個節拍），
    /// `now` 是真實時間（鏡頭閒置用）。閒置後把鏡頭移回第一隻身邊。
    func build(previous: SimulationSnapshot?, current: SimulationSnapshot, at time: Double, now: Double) -> Frame {
        let elapsed = lastBuild.map { min(max(now - $0, 0), 0.1) } ?? (1.0 / 60)
        lastBuild = now
        let placed = place(previous: previous, current: current, at: time)
        focus = focus(of: placed)
        hasBuilt = true
        if needsFocus {
            needsFocus = false
            camera = makeCamera(center: focus)
        }

        var returning = false
        var wakeAt: Double?
        if var cam = camera {
            let idle = now - lastTouch >= Self.idleSecondsBeforeReturn
            if idle, lastDrag == nil, pinchStart == nil {
                // 每格走剩下距離的一部分；很近時直接到位（最後一小段也要補上）
                let fraction = 1 - pow(1 - Self.returnStepPer60Hz, elapsed * 60)
                returning = !cam.approach(x: focus.x, y: focus.y, fraction: fraction)
                camera = cam
            } else if !idle {
                var probe = cam
                if !probe.approach(x: focus.x, y: focus.y, fraction: 0) || probe != cam {
                    wakeAt = lastTouch + Self.idleSecondsBeforeReturn
                }
            }
        }

        let sprites = order(placed)
        lastCharacters = Array(sprites.filter { sprite in
            if case .character = sprite.key { return true }
            return false
        }.reversed())
        let keepRunning = returning || lastDrag != nil || pinchStart != nil
        if !keepRunning { lastBuild = nil }   // 停下來再醒來時，不把停下來的時間算成一大步
        return Frame(sprites: sprites, drawList: viewTransform.map { drawList(sprites, $0) },
                     keepRunning: keepRunning, wakeAt: keepRunning ? nil : wakeAt)
    }

    /// 畫面左上角對著箱庭哪一點；還沒量到畫面大小前是 nil。
    var viewTransform: ViewTransform? {
        guard let camera else { return nil }
        let topLeft = camera.topLeft
        return ViewTransform(topLeftX: topLeft.x, topLeftY: topLeft.y, pointsPerUnit: zoom)
    }

    /// 這一格每隻在哪、長什麼樣子：位置與走路的步態在兩份快照之間依比例內插（新上台的直接用最新的）。
    private func place(previous: SimulationSnapshot?, current: SimulationSnapshot, at time: Double) -> [Placed] {
        var alpha = 1.0
        if let previous, current.tick > previous.tick {
            alpha = min(1, max(0, (time - previous.time) / (current.time - previous.time)))
        }
        return current.characters.enumerated().compactMap { order, character in
            guard let rig = castRigs[character.id] else { return nil }
            let before = previous?.character(character.id)
            let position = before.map { a in
                TilePosition(i: a.position.i + (character.position.i - a.position.i) * alpha,
                             j: a.position.j + (character.position.j - a.position.j) * alpha)
            } ?? character.position
            let pose = Self.pose(of: character, before: before, alpha: alpha, at: time, rig: rig,
                                 motions: castMotions[character.id] ?? .still)
            return Placed(id: character.id, order: order, position: position, feet: iso.feet(at: position), pose: pose)
        }
    }

    /// 一隻角色這一格的樣子（ADR 0009）：照牠的動作資料找這個方向的片段，播到這一刻。不分物種。
    /// - 移動：步態的循環片段，播到走了幾秒（兩份快照之間內插；重新起步時不往回算）。
    /// - 播動作：一次性的片段，照「畫的時間 − 開始的時間」播（還沒開始算 0 秒，播完停在最後一格）。
    /// - 站著、等別隻讓路，或這個方向沒有片段：每個部件在原位。
    /// - 造型沒有這個方向時（例如灰色剪影沒有斜向）面向鏡頭。翻轉的方向用來源的片段。
    static func pose(of character: SimulationSnapshot.Character, before: SimulationSnapshot.Character?, alpha: Double,
                     at time: Double, rig: VectorRig, motions: CharacterMotions) -> CharacterPose {
        let facing = rig.look(character.facing.rawValue) != nil ? character.facing : .front
        guard let source = rig.look(facing.rawValue)?.source else { return CharacterPose(facing: facing) }
        switch character.activity {
        case .moving(let pace, let elapsed):
            var t = elapsed
            if case .moving(let earlierPace, let earlier)? = before?.activity, earlierPace == pace, earlier <= elapsed {
                t = earlier + (elapsed - earlier) * alpha
            }
            let gait = motions.gait(for: pace)
            guard let clip = gait.clips[source] else { return CharacterPose(facing: facing) }
            return CharacterPose(facing: facing, parts: clip.poses(at: t, cycle: gait.cycle))
        case .motion(let intent, let since):
            guard let name = intent.motionName, let motion = motions.motion(named: name),
                  let clip = motion.clips[source] else { return CharacterPose(facing: facing) }
            return CharacterPose(facing: facing, parts: clip.poses(at: min(max(0, time - since), motion.duration)))
        case .still:
            return CharacterPose(facing: facing)
        }
    }

    /// 鏡頭要對著哪裡：第一隻的身體中央（看牠的造型，不分物種）；第一隻不在台上時是台上的下一隻，
    /// 台上沒有角色時是箱庭中央。
    private func focus(of placed: [Placed]) -> (x: Double, y: Double) {
        let lead = cast.lazy.compactMap { member in placed.first { $0.id == member.id } }.first
        guard let lead else { return (Double(iso.canvasWidth) / 2, Double(iso.canvasHeight) / 2) }
        return (lead.feet.x, lead.feet.y - (castRigs[lead.id]?.bodyCenterAboveFeet ?? 0))
    }

    /// 由遠到近：背景先畫，家具依深度排，角色再一隻隻插進去。
    private func order(_ placed: [Placed]) -> [Sprite] {
        let furniture = RoomRenderer.drawOrder(furnitureSprites.map { ($0.sprite, $0.depth) })
        var order: [(sprite: Sprite, depth: Double, footprint: TileRect?)] = furniture.map { sprite in
            guard case .furniture(let i) = sprite.key else { return (sprite, 0, nil) }
            return (sprite, Double(furnitureSprites[i].depth), room.furniture[i].footprint)
        }
        // 角色之間：腳底高的先畫；一樣時後上台的畫在後面（前面）
        for character in placed.sorted(by: { ($0.feet.y, $0.order) < ($1.feet.y, $1.order) }) {
            var at = order.firstIndex { $0.depth > character.feet.y } ?? order.count
            for (k, item) in order.enumerated() {
                guard let footprint = item.footprint else { continue }
                switch Self.relation(of: character.position, to: footprint) {
                case .front where k >= at: at = k + 1
                case .behind where k < at: at = k
                default: break
                }
            }
            order.insert((sprite(of: character), character.feet.y, nil), at: at)
        }
        let background = Sprite(key: .background, x: 0, y: 0,
                                width: Double(iso.canvasWidth), height: Double(iso.canvasHeight))
        return [background] + order.map(\.sprite)
    }

    /// 角色和一件家具的前後。
    enum Relation: Equatable {
        case front, behind, unknown
    }

    /// 角色當作佔一格（以牠站的點為中心）：沿 i 軸或 j 軸整個在家具後面（離主人更近）就畫在前面，
    /// 整個在家具前面就畫在後面；斜對角或兩邊都成立時看不出來，交給腳底高度決定。
    static func relation(of position: TilePosition, to footprint: TileRect) -> Relation {
        let tolerance = 1e-9
        let front = position.i - 0.5 >= Double(footprint.maxX) - tolerance
            || position.j - 0.5 >= Double(footprint.maxY) - tolerance
        let behind = position.i + 0.5 <= Double(footprint.x) + tolerance
            || position.j + 0.5 <= Double(footprint.y) + tolerance
        if front && !behind { return .front }
        if behind && !front { return .behind }
        return .unknown
    }

    /// 角色畫布的腳底對到站的點；畫布的大小看這個方向的圖（翻轉的方向用來源的）。
    private func sprite(of character: Placed) -> Sprite {
        let rig = castRigs[character.id] ?? .placeholder
        let canvas = rig.look(character.pose.facing.rawValue).flatMap { rig.facings[$0.source] } ?? rig.front
        return Sprite(key: .character(character.id), x: character.feet.x - canvas.feet.x, y: character.feet.y - canvas.feet.y,
                      width: canvas.canvas.width, height: canvas.canvas.height, pose: character.pose)
    }

    /// 繪製清單：角色每個部件的矩陣把部件的畫布座標換到畫面上的 pt（姿勢 → 放到箱庭上 → 鏡頭 → 縮放）。
    private func drawList(_ sprites: [Sprite], _ transform: ViewTransform) -> DrawList {
        let items: [DrawList.Item] = sprites.compactMap { sprite in
            switch sprite.key {
            case .background, .furniture:
                return .polygons(sprite.key)
            case .character(let id):
                guard let pose = sprite.pose, let frame = castRigs[id]?.frame(pose) else { return nil }
                let toScreen = Affine2D.scale(transform.pointsPerUnit, transform.pointsPerUnit)
                    * Affine2D.translation(sprite.x - transform.topLeftX, sprite.y - transform.topLeftY)
                let parts = frame.look.drawOrder.map {
                    DrawList.Part(name: $0, transform: toScreen * (frame.transforms[$0] ?? .identity))
                }
                return .character(id, look: frame.look.source, parts: parts)
            }
        }
        return DrawList(viewportWidth: viewport.width, viewportHeight: viewport.height, topLeftX: transform.topLeftX,
                        topLeftY: transform.topLeftY, pointsPerUnit: transform.pointsPerUnit, items: items)
    }

    // MARK: - 外面告訴我們的事（座標是畫面上的 pt，左上角為原點）

    /// 畫面大小改變（第一次出現、旋轉）。第一次時鏡頭對準第一隻；之後保留原本對著的點，縮放重新限制在範圍內。
    func resize(viewport size: CGSize, displayScale scale: Double) {
        guard size.width > 0, size.height > 0 else { return }
        viewport = size
        displayScale = scale
        zoom = zoomLimits().clamped(zoom)
        if let camera {
            self.camera = makeCamera(center: (camera.centerX, camera.centerY))
        } else {
            camera = makeCamera(center: focus)
            needsFocus = !hasBuilt
        }
        onChange()
    }

    /// 這一點點到哪一隻角色（照上一格畫的位置）；沒點到是 nil。觸控範圍是整張角色畫布，比角色本身大一圈。
    /// 兩隻重疊時，畫在前面（離主人近）的那隻優先。
    func character(at point: CGPoint) -> CharacterID? {
        guard let transform = viewTransform else { return nil }
        let x = transform.topLeftX + point.x / transform.pointsPerUnit
        let y = transform.topLeftY + point.y / transform.pointsPerUnit
        let hit = lastCharacters.first { x >= $0.x && x < $0.x + $0.width && y >= $0.y && y < $0.y + $0.height }
        guard case .character(let id)? = hit?.key else { return nil }
        return id
    }

    /// 主人碰了箱庭（例如點角色）：重新計算閒置。
    func ownerTouched(now: Double) {
        lastTouch = now
        onChange()
    }

    /// 拖曳中：每次只套用和上一次相比移了多少，捏合中不捲動，捏完剩一根手指拖也不跳。
    func panChanged(translation: CGSize, startLocation: CGPoint, now: Double) {
        if lastDrag == nil { dragStartedOnCharacter = character(at: startLocation) != nil }
        let last = lastDrag ?? .zero
        lastDrag = translation
        lastTouch = now
        guard !dragStartedOnCharacter, pinchStart == nil, var moved = camera else { return }
        // 手指往右拖，畫面往右移，也就是鏡頭往左
        moved.moveTo(x: moved.centerX - (translation.width - last.width) / zoom,
                     y: moved.centerY - (translation.height - last.height) / zoom)
        camera = moved
        onChange()
    }

    func panEnded(now: Double) {
        lastDrag = nil
        dragStartedOnCharacter = false
        lastTouch = now
        onChange()
    }

    /// 捏合中：連續縮放，以捏合開始的位置為中心。
    func pinchChanged(magnification: Double, anchor: CGPoint, now: Double) {
        guard let current = camera else { return }
        let start = pinchStart ?? (zoom, (current.centerX, current.centerY))
        pinchStart = start
        lastTouch = now
        apply(zoom: zoomLimits().clamped(start.zoom * magnification), from: start, anchor: anchor)
    }

    /// 放開：停在放開時的倍率（向量任何倍率都清楚，不用吸附）。
    func pinchEnded(magnification: Double, anchor: CGPoint, now: Double) {
        if let start = pinchStart {
            apply(zoom: zoomLimits().clamped(start.zoom * magnification), from: start, anchor: anchor)
        }
        pinchStart = nil
        lastTouch = now
        onChange()
    }

    // MARK: - 小工具

    private func zoomLimits() -> RoomZoom {
        RoomZoom(viewportWidth: viewport.width, canvasWidth: Double(iso.canvasWidth))
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
        onChange()
    }
}
