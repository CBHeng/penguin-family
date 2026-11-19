import CoreGraphics
import Foundation

/// 箱庭的即時狀態：鏡頭、縮放、每隻企鵝的位置與正在播的動作；每一格要畫哪些東西、點擊打中了哪一隻。
///
/// 純邏輯，不碰 Metal 與 SwiftUI 的畫面，可以單獨測試。時間（秒）由外面傳進來：
/// 遊戲迴圈（`GameLoop`）每一格呼叫 `update(now:)`，手勢由 `RoomView` 呼叫對應的方法。
/// 有變化才需要重畫（作者 2026-11-16 決定），所以每次改變都會通知 `onChange` 叫醒遊戲迴圈。
///
/// 企鵝分「後台」與「台上」（作者 2026-11-17 決定）：建立時給後台名單（可能上台的每一隻與造型），
/// 牠們的圖在載入時一次送進 GPU；之後用 `add`、`remove` 決定誰在台上，只有台上的會畫、點得到、鏡頭會看。
/// 企鵝用 `PenguinID` 區分，不用編號。
///
/// 改走向量（ADR 0007）：位置不取整數、走路每一格都前進；有向量造型的企鵝，正面與斜向都照當下的姿勢轉動部件。
/// 角色包沒有向量造型（或缺斜向）時退回像素圖，A1 第 10 項拿掉。
final class RoomStage {
    /// 沒碰多久後鏡頭開始回到企鵝身邊（秒）。實機上調。
    static let idleSecondsBeforeReturn: Double = 5
    /// 回去時，以每秒 60 格計，每格走剩下距離的多少；更新率不同時換算成相同的速度。實機上調。
    static let returnStepPer60Hz: Double = 0.08

    /// 後台名單的一隻：身分與造型。兩種造型都沒有時用灰色剪影。
    struct CastMember {
        let id: PenguinID
        /// 像素造型：沒有向量造型（或向量造型缺斜向）時用（A1 第 10 項拿掉）。
        let frames: CharacterFrames?
        /// 向量造型（ADR 0007）：有的話用它畫；角色包沒有斜向時，斜向退回像素。
        var vector: VectorRig? = nil
    }

    /// 要畫的東西是哪一個。企鵝以身分區分，因為兩隻的造型不同。
    enum SpriteKey: Hashable, Sendable {
        /// 牆、地板與掛在牆上的東西（多邊形）。
        case background
        /// 地上的第幾件家具（多邊形）。
        case furniture(Int)
        /// 向量企鵝：照 `Sprite.vector` 的方向與姿勢轉動部件。
        case penguinVector(PenguinID)
        /// 像素企鵝正面站好（沒有向量造型時）。
        case penguinRest(PenguinID)
        /// 像素企鵝正面動作（哈囉）的第幾格（沒有向量造型時）。
        case penguinFrame(PenguinID, motion: String, frame: Int)
        /// 斜向站著（走到後維持走的方向）。
        case penguinStanding(PenguinID, Facing)
        /// 斜向走路：哪個步態、哪個方向、一個循環的第幾格。
        case penguinGait(PenguinID, gait: String, facing: Facing, frame: Int)
        case placeholder
    }

    /// 某隻企鵝走到了哪一格（到不了時是原地那一格）。
    struct Arrival: Equatable, Sendable {
        let id: PenguinID
        let tile: Tile
    }

    /// 要畫的一樣東西：蓋住箱庭上的哪個範圍（單位，可以有小數）。
    /// 圖（像素）貼滿這個範圍；向量企鵝是角色畫布放在這裡、照 `vector` 轉動部件；多邊形本身就帶位置，範圍只是外接矩形。
    struct Sprite: Equatable, Sendable {
        let key: SpriteKey
        let x: Double
        let y: Double
        let width: Double
        let height: Double
        /// 向量企鵝這一格的方向與姿勢；其他是 nil。
        var vector: VectorPose? = nil
    }

    /// 箱庭怎麼對到畫面：畫面左上角對著箱庭的哪一點（單位，已對齊螢幕實體像素），每個單位幾 pt。
    struct ViewTransform: Equatable, Sendable {
        let topLeftX: Double
        let topLeftY: Double
        let pointsPerPixel: Double
    }

    /// 每一格更新後，遊戲迴圈要做什麼。
    struct Tick: Equatable, Sendable {
        /// 畫面有變，要重畫。
        var draw = false
        /// 剛播完動作的企鵝，要回報給各自的 `Behavior`。
        var motionFinished: [PenguinID] = []
        /// 剛走到的企鵝，要回報給各自的 `Behavior`。
        var arrived: [Arrival] = []
        /// 還有東西在動，下一格要繼續跑；否則遊戲迴圈可以暫停。
        var keepRunning = false
        /// 暫停後要在這個時間醒來（例如閒置一段時間後鏡頭回到企鵝身邊）。
        var wakeAt: Double?
    }

    /// 台上一隻企鵝現在的樣子。
    private struct Penguin {
        let id: PenguinID
        let frames: CharacterFrames?
        let vector: VectorRig?
        /// 站在地板的哪一點；走路時一直變。
        var position: TilePosition
        var feet: ScenePoint
        /// 面向哪裡：一開始面向鏡頭；走路時是這一段的方向，走到後維持；哈囉時轉回正面。
        var facing: Facing = .front
        var intent: PenguinBehavior.Intent?
        var playing: (motion: Motion, start: Double)?
        /// 像素正面動作播到第幾格。
        var currentFrame: Int?
        /// 向量正面現在的姿勢（斜向的姿勢由走路算）。
        var pose: RigPose = .rest
        var walking: Walk?
    }

    /// 正在走的一段路。
    private struct Walk {
        let path: RoomPath
        let gait: Gait
        let start: Double
        /// 走了幾秒：向量的步態每一格照這個算姿勢，位置也每一格都前進（ADR 0007）。
        var elapsed = 0.0
        /// 像素的走路動畫到第幾格了（每秒 12 格）。
        var frame = 0
    }

    let room: RoomLayout
    /// 有變化時呼叫，叫醒遊戲迴圈。
    var onChange: () -> Void = {}

    private let iso: IsoProjection
    private let furnitureSprites: [(sprite: Sprite, depth: Int)]
    private let roomPolygons: [SpriteKey: [ColoredPolygon]]
    /// 後台名單，依給的順序。
    private let cast: [CastMember]
    /// 台上的企鵝，依上台先後；深度相同時後上台的畫在前面。
    private var penguins: [Penguin] = []
    /// 畫面大小（pt）與 1pt 幾個實體像素。還沒量到畫面大小前是 0。
    private(set) var viewport = CGSize.zero
    private(set) var displayScale = 1.0
    /// 每個單位畫成幾 pt。
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

    /// 到目前為止建過幾個舞台。測試用：確認 `RoomView` 被重新建立時不會跟著重建舞台（2026-11-18 修過）。
    private(set) static var createdCount = 0

    /// 建立時台上沒有企鵝；用 `add` 讓後台名單裡的企鵝上台。一個畫面只建一次。
    init(room: RoomLayout, cast: [CastMember]) {
        Self.createdCount += 1
        self.room = room
        self.cast = cast
        let iso = IsoProjection(room: room)
        self.iso = iso
        var polygons: [SpriteKey: [ColoredPolygon]] = [.background: RoomRenderer.background(room)]
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

    /// 台上有誰，依上台先後。
    var onStage: [PenguinID] { penguins.map(\.id) }

    /// 台上某隻企鵝的腳底在箱庭上的位置；不在台上是 nil。
    func feet(of id: PenguinID) -> ScenePoint? { penguins.first { $0.id == id }?.feet }

    /// 台上某隻企鵝站在地板的哪一點；不在台上是 nil。
    func position(of id: PenguinID) -> TilePosition? { penguins.first { $0.id == id }?.position }

    /// 台上某隻企鵝面向哪裡；不在台上是 nil。
    func facing(of id: PenguinID) -> Facing? { penguins.first { $0.id == id }?.facing }

    /// 台上某隻向量企鵝現在的姿勢；不在台上是 nil。
    func pose(of id: PenguinID) -> RigPose? { penguins.first { $0.id == id }?.pose }
    /// 向量企鵝這一格的方向與姿勢（測試用）。
    func vectorPose(of id: PenguinID) -> VectorPose? { penguins.first { $0.id == id }.flatMap(Self.vectorPose(of:)) }

    // MARK: - 上台、下台

    /// 讓後台名單裡的一隻站到 `position` 上台。不在名單裡、或已經在台上時不做事。
    func add(_ id: PenguinID, at position: TilePosition) {
        guard !penguins.contains(where: { $0.id == id }), let member = cast.first(where: { $0.id == id }) else { return }
        penguins.append(Penguin(id: id, frames: member.frames, vector: member.vector, position: position,
                                feet: iso.feet(at: position)))
        changed()
    }

    /// 讓一隻下台：不再畫、點不到、鏡頭不再看牠。正在播的動作直接停掉，不回報播完。
    func remove(_ id: PenguinID) {
        guard let index = penguins.firstIndex(where: { $0.id == id }) else { return }
        penguins.remove(at: index)
        changed()
    }

    // MARK: - 繪圖層載入時要的東西

    /// 所有可能用到的像素圖，包含後台還沒上台的企鵝；繪圖層載入時一次全部送進 GPU（用首次載入換順暢），
    /// 之後上台不用再載入。有向量造型的企鵝不放正面的像素圖；向量造型四個斜向都有時，也不放斜向的像素圖。
    func allBitmaps() -> [SpriteKey: PixelBitmap] {
        var all: [SpriteKey: PixelBitmap] = [:]
        for member in cast {
            guard let frames = member.frames else {
                if member.vector == nil { all[.placeholder] = PlaceholderSilhouette.bitmap }
                continue
            }
            if member.vector == nil {
                all[.penguinRest(member.id)] = frames.rest
                for motion in Motion.all {
                    for frame in 0..<frames.frameCount(of: motion) {
                        all[.penguinFrame(member.id, motion: motion.name, frame: frame)] = frames.image(motion, frame: frame)
                    }
                }
            }
            // 向量造型四個斜向都有時，不用像素的斜向
            let vectorOblique = Facing.oblique.allSatisfy { member.vector?.look($0.rawValue) != nil }
            guard let oblique = frames.oblique, !vectorOblique else { continue }
            for (facing, image) in oblique.standing {
                all[.penguinStanding(member.id, facing)] = image
            }
            for gait in Gait.all {
                for facing in Facing.oblique {
                    for frame in 0..<oblique.frameCount(gait, facing) {
                        all[.penguinGait(member.id, gait: gait.name, facing: facing, frame: frame)] =
                            oblique.image(gait, facing, frame: frame)
                    }
                }
            }
        }
        return all
    }

    /// 箱庭的多邊形：背景與每件家具。繪圖層載入時一次切成三角形送進 GPU。
    func polygons() -> [SpriteKey: [ColoredPolygon]] { roomPolygons }

    /// 後台名單裡有向量造型的每一隻；繪圖層載入時把部件畫成貼圖。
    func vectorRigs() -> [PenguinID: VectorRig] {
        Dictionary(uniqueKeysWithValues: cast.compactMap { member in member.vector.map { (member.id, $0) } })
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

    /// 台上某隻的意圖變了：換播對應的動作，或開始走路。不在台上或意圖沒變時不做事。
    /// - 哈囉：先轉回正面（哈囉只有正面的圖），作者 2026-11-18 決定。
    /// - 走路：從現在站的那一格找路；到不了時停在原地，下一格就回報走到（`Tick.arrived`）。
    /// - 待機：不換方向，走到後維持走的方向。
    func setIntent(_ newIntent: PenguinBehavior.Intent, for id: PenguinID, now: Double) {
        guard let index = penguins.firstIndex(where: { $0.id == id }), newIntent != penguins[index].intent else { return }
        penguins[index].intent = newIntent
        penguins[index].playing = Self.motion(for: newIntent).map { ($0, now) }
        penguins[index].walking = nil
        switch newIntent {
        case .idle:
            break
        case .hello:
            penguins[index].facing = .front
        case .walk(let goal, let pace):
            let here = Tile(containing: penguins[index].position)
            let path = RoomPath.find(in: room, from: here, to: goal) ?? RoomPath(tiles: [here])
            penguins[index].walking = Walk(path: path, gait: Self.gait(for: pace), start: now)
            moveAlong(index, distance: 0)
        }
        changed()
    }

    /// 台上某隻換位置。不在台上、正在走路（位置由走路決定）或位置沒變時不做事。
    func setPosition(_ position: TilePosition, for id: PenguinID) {
        guard let index = penguins.firstIndex(where: { $0.id == id }), penguins[index].walking == nil,
              position != penguins[index].position else { return }
        penguins[index].position = position
        penguins[index].feet = iso.feet(at: position)
        changed()
    }

    /// 走路的快慢用哪個步態。
    static func gait(for pace: PenguinBehavior.Pace) -> Gait {
        switch pace {
        case .walk: .walk
        case .trot: .trot
        }
    }

    /// 意圖要播哪個正面動作；待機與走路不播（走路用斜向的步態）。
    static func motion(for intent: PenguinBehavior.Intent) -> Motion? {
        switch intent {
        case .idle, .walk: nil
        case .hello: .hello
        }
    }

    // MARK: - 手勢（座標是畫面上的 pt，左上角為原點）

    /// 這一點點到台上哪一隻企鵝；沒點到是 nil。觸控範圍是整張企鵝圖（角色畫布），比企鵝本身大一圈。
    /// 兩隻重疊時，畫在前面（離主人近）的那隻優先。
    func penguin(at point: CGPoint) -> PenguinID? {
        guard let transform = viewTransform else { return nil }
        let x = transform.topLeftX + point.x / transform.pointsPerPixel
        let y = transform.topLeftY + point.y / transform.pointsPerPixel
        // 和 `sprites()` 的順序相反：深度大的先；深度相同時，後上台的畫在後面，也就是在前面
        let frontFirst = penguins.indices.sorted { (penguins[$0].feet.y, $0) > (penguins[$1].feet.y, $1) }
        return frontFirst.first { index in
            let p = sprite(of: index)
            return x >= p.x && x < p.x + p.width && y >= p.y && y < p.y + p.height
        }.map { penguins[$0].id }
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

    /// 遊戲迴圈每一格呼叫：推進每隻的動作與走路、閒置後把鏡頭移回企鵝身邊，回報要不要重畫、要不要繼續跑。
    func update(now: Double) -> Tick {
        var tick = Tick()
        let elapsed = lastUpdate.map { min(max(now - $0, 0), 0.1) } ?? (1.0 / 60)
        lastUpdate = now

        for index in penguins.indices {
            if let p = penguins[index].playing, now - p.start >= p.motion.duration {
                penguins[index].playing = nil
                tick.motionFinished.append(penguins[index].id)
            }
            if penguins[index].vector != nil {
                // 向量：每一格照第幾秒的姿勢轉動部件
                let pose = penguins[index].playing.map { $0.motion.poseAt(now - $0.start) } ?? .rest
                if pose != penguins[index].pose {
                    penguins[index].pose = pose
                    needsDraw = true
                }
            } else {
                let frame = penguins[index].playing.map { Int(((now - $0.start) * $0.motion.framesPerSecond).rounded(.down)) }
                if frame != penguins[index].currentFrame {
                    penguins[index].currentFrame = frame
                    needsDraw = true
                }
            }
            if let arrival = advanceWalk(index, now: now) { tick.arrived.append(arrival) }
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
        let anyPlaying = penguins.contains { $0.playing != nil || $0.walking != nil }
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

    /// 這一格要畫的東西，由遠到近：背景先畫，越靠近主人（畫面越下方）畫在越前面。
    ///
    /// 家具依「最靠近主人的角」排；企鵝再一隻隻插進去，先照腳底高度，再照格子關係修正（2026-11-18）：
    /// 長家具（例如佔三格的沙發）最近的角很低，只比腳底高度的話，站在它旁邊前方的企鵝會被畫到後面。
    func sprites() -> [Sprite] {
        let furniture = RoomRenderer.drawOrder(furnitureSprites.map { ($0.sprite, $0.depth) })
        var order: [(sprite: Sprite, depth: Double, footprint: TileRect?)] = furniture.map { sprite in
            guard case .furniture(let i) = sprite.key else { return (sprite, 0, nil) }
            return (sprite, Double(furnitureSprites[i].depth), room.furniture[i].footprint)
        }
        // 企鵝之間：腳底高的先畫；一樣時後上台的畫在後面（前面）
        for index in penguins.indices.sorted(by: { (penguins[$0].feet.y, $0) < (penguins[$1].feet.y, $1) }) {
            let penguin = penguins[index]
            var at = order.firstIndex { $0.depth > penguin.feet.y } ?? order.count
            for (k, item) in order.enumerated() {
                guard let footprint = item.footprint else { continue }
                switch Self.relation(of: penguin.position, to: footprint) {
                case .front where k >= at: at = k + 1
                case .behind where k < at: at = k
                default: break
                }
            }
            order.insert((sprite(of: index), penguin.feet.y, nil), at: at)
        }
        let background = Sprite(key: .background, x: 0, y: 0,
                                width: Double(iso.canvasWidth), height: Double(iso.canvasHeight))
        return [background] + order.map(\.sprite)
    }

    /// 企鵝和一件家具的前後。
    enum Relation: Equatable {
        case front, behind, unknown
    }

    /// 企鵝當作佔一格（以牠站的點為中心）：沿 i 軸或 j 軸整個在家具後面（離主人更近）就畫在前面，
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

    private func sprite(of index: Int) -> Sprite {
        let penguin = penguins[index]
        let feet = penguin.feet
        // 向量：正面與角色包有的斜向
        if let pose = Self.vectorPose(of: penguin), let vector = penguin.vector,
           let look = vector.look(pose.facing.rawValue), let canvas = vector.facings[look.source] {
            return Sprite(key: .penguinVector(penguin.id), x: feet.x - canvas.feet.x, y: feet.y - canvas.feet.y,
                          width: canvas.canvas.width, height: canvas.canvas.height, vector: pose)
        }
        // 像素的斜向：走路用步態的那一格；站著用斜向站姿。沒有斜向時退回正面
        if penguin.facing != .front, let oblique = penguin.frames?.oblique {
            var key: SpriteKey?
            if let walk = penguin.walking, oblique.frameCount(walk.gait, penguin.facing) > 0 {
                let frame = walk.frame % oblique.frameCount(walk.gait, penguin.facing)
                key = .penguinGait(penguin.id, gait: walk.gait.name, facing: penguin.facing, frame: frame)
            } else if oblique.standing[penguin.facing] != nil {
                key = .penguinStanding(penguin.id, penguin.facing)
            }
            if let key {
                return Sprite(key: key, x: feet.x - Double(oblique.anchor.x), y: feet.y - Double(oblique.anchor.y),
                              width: Double(oblique.width), height: Double(oblique.height))
            }
        }
        if let vector = penguin.vector {
            let front = vector.front
            return Sprite(key: .penguinVector(penguin.id), x: feet.x - front.feet.x, y: feet.y - front.feet.y,
                          width: front.canvas.width, height: front.canvas.height, vector: .front(penguin.pose))
        }
        guard let frames = penguin.frames else {
            let a = PlaceholderSilhouette.anchor, g = PlaceholderSilhouette.grid
            return Sprite(key: .placeholder, x: feet.x - Double(a.x), y: feet.y - Double(a.y),
                          width: Double(g.width), height: Double(g.height))
        }
        var key = SpriteKey.penguinRest(penguin.id)
        if let playing = penguin.playing, let frame = penguin.currentFrame, frame < frames.frameCount(of: playing.motion) {
            key = .penguinFrame(penguin.id, motion: playing.motion.name, frame: max(0, frame))
        }
        return Sprite(key: key, x: feet.x - Double(frames.anchor.x), y: feet.y - Double(frames.anchor.y),
                      width: Double(frames.width), height: Double(frames.height))
    }

    /// 向量企鵝這一格的樣子：正面用哈囉等動作的姿勢；斜向用步態在走了幾秒時的姿勢，站著時是站姿。
    /// 角色包沒有這個斜向時是 nil（退回像素）。
    private static func vectorPose(of penguin: Penguin) -> VectorPose? {
        guard let vector = penguin.vector else { return nil }
        guard penguin.facing != .front else { return .front(penguin.pose) }
        guard let walk = vector.walk(penguin.facing.rawValue) else { return nil }
        return .oblique(penguin.facing, penguin.walking.map { $0.gait.vectorPose(at: $0.elapsed, walk: walk) } ?? .rest)
    }

    // MARK: - 走路

    /// 推進一隻正在走的企鵝：位置與向量的步態每一格都照經過的時間前進（ADR 0007；像素的走路動畫每秒換 12 格）；走到時回報。
    private func advanceWalk(_ index: Int, now: Double) -> Arrival? {
        guard var walk = penguins[index].walking else { return nil }
        let elapsed = max(0, now - walk.start)
        let distance = walk.gait.tilesPerSecond * elapsed
        if distance >= Double(walk.path.steps) {
            moveAlong(index, distance: Double(walk.path.steps))
            penguins[index].walking = nil
            needsDraw = true
            return Arrival(id: penguins[index].id, tile: walk.path.goal)
        }
        walk.elapsed = elapsed
        walk.frame = Int((elapsed * Gait.framesPerSecond).rounded(.down))
        penguins[index].walking = walk
        moveAlong(index, distance: distance)
        needsDraw = true
        return nil
    }

    /// 把正在走的企鵝放到路上走了 `distance` 格的地方，面向這一段的方向（剛好在轉角時面向下一段）。
    private func moveAlong(_ index: Int, distance: Double) {
        guard let path = penguins[index].walking?.path else { return }
        let tiles = path.tiles
        guard tiles.count > 1 else {
            penguins[index].position = tiles[0].center
            penguins[index].feet = iso.feet(at: tiles[0].center)
            return
        }
        let segment = min(Int(distance.rounded(.down)), tiles.count - 2)
        let fraction = distance - Double(segment)
        let a = tiles[segment].center, b = tiles[segment + 1].center
        let position = TilePosition(i: a.i + (b.i - a.i) * fraction, j: a.j + (b.j - a.j) * fraction)
        penguins[index].position = position
        penguins[index].feet = iso.feet(at: position)
        if let step = Step(from: tiles[segment], to: tiles[segment + 1]) { penguins[index].facing = step.facing }
    }

    // MARK: - 小工具

    /// 鏡頭要回到哪裡：台上所有企鵝身體中央的中點（腳底上方約 16 單位）。台上沒有企鵝時是箱庭中央。
    private var focus: (x: Double, y: Double) {
        guard !penguins.isEmpty else { return (Double(iso.canvasWidth) / 2, Double(iso.canvasHeight) / 2) }
        let n = Double(penguins.count)
        let x = penguins.reduce(0.0) { $0 + $1.feet.x } / n
        let y = penguins.reduce(0.0) { $0 + $1.feet.y - 16 } / n
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
