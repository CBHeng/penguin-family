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
/// 走平面向量（ADR 0007）：位置不取整數、走路每一格都前進；企鵝的正面與斜向都照當下的姿勢轉動部件。
/// 沒有角色包的位置用灰色剪影，它也是向量，只有正面。
final class RoomStage {
    /// 沒碰多久後鏡頭開始回到企鵝身邊（秒）。實機上調。
    static let idleSecondsBeforeReturn: Double = 5
    /// 回去時，以每秒 60 格計，每格走剩下距離的多少；更新率不同時換算成相同的速度。實機上調。
    static let returnStepPer60Hz: Double = 0.08

    /// 後台名單的一隻：身分與造型。
    struct CastMember {
        let id: PenguinID
        /// 向量造型（ADR 0007）；nil 用灰色剪影（`VectorRig.placeholder`）。
        var vector: VectorRig? = nil
    }

    /// 要畫的東西是哪一個。企鵝以身分區分，因為兩隻的造型不同。
    enum SpriteKey: Hashable, Sendable {
        /// 牆、地板與掛在牆上的東西（多邊形）。
        case background
        /// 地上的第幾件家具（多邊形）。
        case furniture(Int)
        /// 企鵝：照 `Sprite.pose` 的方向與姿勢轉動部件。
        case penguin(PenguinID)
    }

    /// 某隻企鵝走到了哪一格（到不了時是原地那一格）。
    struct Arrival: Equatable, Sendable {
        let id: PenguinID
        let tile: Tile
    }

    /// 要畫的一樣東西：蓋住箱庭上的哪個範圍（單位，可以有小數）。
    /// 企鵝是角色畫布放在這裡、照 `pose` 轉動部件；多邊形本身就帶位置，範圍只是外接矩形。
    struct Sprite: Equatable, Sendable {
        let key: SpriteKey
        let x: Double
        let y: Double
        let width: Double
        let height: Double
        /// 企鵝這一格的方向與姿勢；其他是 nil。
        var pose: VectorPose? = nil
    }

    /// 箱庭怎麼對到畫面：畫面左上角對著箱庭的哪一點（單位，可以有小數），每個單位幾 pt。
    struct ViewTransform: Equatable, Sendable {
        let topLeftX: Double
        let topLeftY: Double
        let pointsPerUnit: Double
    }

    /// 每一格更新後，遊戲迴圈要做什麼。
    struct Tick: Equatable, Sendable {
        /// 畫面有變，要重畫。
        var draw = false
        /// 剛播完動作或站滿的企鵝，要回報給各自的 `Behavior`。
        var motionFinished: [PenguinID] = []
        /// 剛走到的企鵝，要回報給各自的 `Behavior`。
        var arrived: [Arrival] = []
        /// 還有東西在動，下一格要繼續跑；否則遊戲迴圈可以暫停。
        var keepRunning = false
        /// 暫停後要在這個時間醒來（例如閒置一段時間後鏡頭回到企鵝身邊、某隻站滿了）。
        var wakeAt: Double?
    }

    /// 台上一隻企鵝現在的樣子。
    private struct Penguin {
        let id: PenguinID
        let vector: VectorRig
        /// 站在地板的哪一點；走路時一直變。
        var position: TilePosition
        var feet: ScenePoint
        /// 面向哪裡：一開始面向鏡頭；走路時是這一段的方向，走到後維持；哈囉時轉回正面；站著時照意圖轉。
        var facing: Facing = .front
        var intent: PenguinBehavior.Intent?
        /// `Behavior` 的意圖編號：同樣的意圖再要一次時，看這個才知道要重新開始。
        var serial = 0
        var playing: (motion: Motion, start: Double)?
        /// 站著（`.stand`）要站到幾秒；畫面不動，遊戲迴圈可以暫停，到時間再醒來。
        var standUntil: Double?
        /// 正面現在的姿勢（斜向的姿勢由走路算）。
        var pose: RigPose = .rest
        var walking: Walk?
        /// 走路被打斷時停在兩格之間；在格子中心時是 nil。
        var midway: Midway?
    }

    /// 停在兩格之間：從 `from` 往 `to` 走了 `fraction`（0～1，不含兩端）。
    /// 下次走路從這一點沿格線接著走，不跳回格子中心（走路中被點，作者 2026-11-19 決定）。
    private struct Midway {
        let from: Tile
        let to: Tile
        let fraction: Double
    }

    /// 正在走的一段路。
    private struct Walk {
        let path: RoomPath
        let gait: Gait
        let start: Double
        /// 走了幾秒：步態每一格照這個算姿勢，位置也每一格都前進（ADR 0007）。
        var elapsed = 0.0
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
    private(set) var zoom = RoomZoom.maxPointsPerUnit
    private(set) var camera: RoomCamera?

    /// 這次拖曳上一次的手指移動量；不在拖曳時是 nil。
    private var lastDrag: CGSize?
    /// 這次拖曳是從企鵝身上開始的：留給之後的「拎起來」，不捲動。
    private var dragStartedOnPenguin = false
    private var pinchStart: (zoom: Double, center: (x: Double, y: Double))?
    private var lastTouch = -Double.infinity
    private var lastUpdate: Double?
    private var needsDraw = true

    /// 到目前為止建過幾個舞台。測試用：確認 `RoomView` 被重新建立時不會跟著重建舞台。
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

    /// 台上某隻企鵝這一格的方向與姿勢；不在台上是 nil。
    func pose(of id: PenguinID) -> VectorPose? { penguins.first { $0.id == id }.map(Self.pose(of:)) }

    // MARK: - 上台、下台

    /// 讓後台名單裡的一隻站到 `position` 上台。不在名單裡、或已經在台上時不做事。
    func add(_ id: PenguinID, at position: TilePosition) {
        guard !penguins.contains(where: { $0.id == id }), let member = cast.first(where: { $0.id == id }) else { return }
        penguins.append(Penguin(id: id, vector: member.vector ?? .placeholder, position: position,
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

    /// 箱庭的多邊形：背景與每件家具。繪圖層載入時一次切成三角形送進 GPU。
    func polygons() -> [SpriteKey: [ColoredPolygon]] { roomPolygons }

    /// 後台名單的每一隻的造型（沒有角色包的是灰色剪影），包含還沒上台的；繪圖層載入時一次把部件畫成貼圖。
    func rigs() -> [PenguinID: VectorRig] {
        Dictionary(uniqueKeysWithValues: cast.map { ($0.id, $0.vector ?? .placeholder) })
    }

    // MARK: - 外面告訴我們的事

    /// 畫面大小改變（第一次出現、旋轉）。第一次時鏡頭對準企鵝；之後保留原本對著的點，縮放重新限制在範圍內。
    func resize(viewport size: CGSize, displayScale scale: Double) {
        guard size.width > 0, size.height > 0 else { return }
        let first = camera == nil
        viewport = size
        displayScale = scale
        let limits = zoomLimits()
        zoom = limits.clamped(zoom)
        let center = camera.map { (x: $0.centerX, y: $0.centerY) } ?? focus
        camera = makeCamera(center: center)
        changed()
    }

    /// 台上某隻的意圖變了：換播對應的動作、站著，或開始走路。不在台上、或意圖與編號（`serial`）都沒變時不做事。
    /// - 哈囉：先轉回正面（哈囉只有正面的圖），作者 2026-11-18 決定。
    /// - 走路：從現在站的那一格找路；到不了時停在原地，下一格就回報走到（`Tick.arrived`）。
    ///   停在兩格之間時，先走到兩端其中一格再接著走（見 `route`）。
    /// - 走路被別的意圖打斷（例如被點就哈囉）：停在當下的位置，記下停在哪兩格之間。
    /// - 站著：轉向意圖給的方向（nil 不轉），站滿後回報播完（`Tick.motionFinished`）。
    /// - 待機：不換方向，走到後維持走的方向。
    func setIntent(_ newIntent: PenguinBehavior.Intent, for id: PenguinID, now: Double, serial: Int = 0) {
        guard let index = penguins.firstIndex(where: { $0.id == id }),
              newIntent != penguins[index].intent || serial != penguins[index].serial else { return }
        penguins[index].intent = newIntent
        penguins[index].serial = serial
        penguins[index].playing = Self.motion(for: newIntent).map { ($0, now) }
        if let walk = penguins[index].walking { penguins[index].midway = Self.midway(of: walk) }
        penguins[index].walking = nil
        penguins[index].standUntil = nil
        switch newIntent {
        case .idle:
            break
        case .stand(let facing, let seconds):
            if let facing { penguins[index].facing = facing }
            penguins[index].standUntil = now + seconds
        case .hello:
            penguins[index].facing = .front
        case .walk(let goal, let pace):
            let gait = Self.gait(for: pace)
            let (path, walked) = route(index, to: goal)
            // 已經走了一段（從半路出發）時，把開始的時間往前推，位置與步態都從那裡接著算
            let seconds = walked / gait.tilesPerSecond
            penguins[index].midway = nil
            penguins[index].walking = Walk(path: path, gait: gait, start: now - seconds, elapsed: seconds)
            moveAlong(index, distance: walked)
        }
        changed()
    }

    /// 台上某隻換位置。不在台上、正在走路或停在半路（位置由舞台決定）、或位置沒變時不做事。
    func setPosition(_ position: TilePosition, for id: PenguinID) {
        guard let index = penguins.firstIndex(where: { $0.id == id }), penguins[index].walking == nil,
              penguins[index].midway == nil, position != penguins[index].position else { return }
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

    /// 意圖要播哪個正面動作；待機、站著與走路不播（走路用斜向的步態）。
    static func motion(for intent: PenguinBehavior.Intent) -> Motion? {
        switch intent {
        case .idle, .stand, .walk: nil
        case .hello: .hello
        }
    }

    // MARK: - 手勢（座標是畫面上的 pt，左上角為原點）

    /// 這一點點到台上哪一隻企鵝；沒點到是 nil。觸控範圍是整張企鵝圖（角色畫布），比企鵝本身大一圈。
    /// 兩隻重疊時，畫在前面（離主人近）的那隻優先。
    func penguin(at point: CGPoint) -> PenguinID? {
        guard let transform = viewTransform else { return nil }
        let x = transform.topLeftX + point.x / transform.pointsPerUnit
        let y = transform.topLeftY + point.y / transform.pointsPerUnit
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

    /// 放開：停在放開時的倍率（向量任何倍率都清楚，不用吸附）。
    func pinchEnded(magnification: Double, anchor: CGPoint, now: Double) {
        if let start = pinchStart {
            apply(zoom: zoomLimits().clamped(start.zoom * magnification), from: start, anchor: anchor)
        }
        pinchStart = nil
        lastTouch = now
        changed()
    }

    // MARK: - 每一格

    /// 遊戲迴圈每一格呼叫：推進每隻的動作、站著與走路，閒置後把鏡頭移回企鵝身邊，回報要不要重畫、要不要繼續跑。
    func update(now: Double) -> Tick {
        var tick = Tick()
        let elapsed = lastUpdate.map { min(max(now - $0, 0), 0.1) } ?? (1.0 / 60)
        lastUpdate = now

        for index in penguins.indices {
            if let p = penguins[index].playing, now - p.start >= p.motion.duration {
                penguins[index].playing = nil
                tick.motionFinished.append(penguins[index].id)
            }
            if let until = penguins[index].standUntil, now >= until {
                penguins[index].standUntil = nil
                tick.motionFinished.append(penguins[index].id)
            }
            // 正面的動作：每一格照第幾秒的姿勢轉動部件
            let pose = penguins[index].playing.map { $0.motion.poseAt(now - $0.start) } ?? .rest
            if pose != penguins[index].pose {
                penguins[index].pose = pose
                needsDraw = true
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

        // 站著的企鵝畫面不動，不用一直跑；最早站滿的那隻到時間再叫醒
        if let standEnds = penguins.compactMap(\.standUntil).min() {
            tick.wakeAt = min(tick.wakeAt ?? standEnds, standEnds)
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
        let topLeft = camera.topLeft
        return ViewTransform(topLeftX: topLeft.x, topLeftY: topLeft.y, pointsPerUnit: zoom)
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
        let pose = Self.pose(of: penguin)
        let canvas = penguin.vector.look(pose.facing.rawValue).flatMap { penguin.vector.facings[$0.source] } ?? penguin.vector.front
        return Sprite(key: .penguin(penguin.id), x: penguin.feet.x - canvas.feet.x, y: penguin.feet.y - canvas.feet.y,
                      width: canvas.canvas.width, height: canvas.canvas.height, pose: pose)
    }

    /// 企鵝這一格的樣子：斜向用步態在走了幾秒時的姿勢，站著時是站姿；正面用哈囉等動作的姿勢。
    /// 造型沒有這個斜向時（例如灰色剪影）面向鏡頭。
    private static func pose(of penguin: Penguin) -> VectorPose {
        if penguin.facing != .front, let walk = penguin.vector.walk(penguin.facing.rawValue) {
            return .oblique(penguin.facing, penguin.walking.map { $0.gait.vectorPose(at: $0.elapsed, walk: walk) } ?? .rest)
        }
        return .front(penguin.pose)
    }

    // MARK: - 走路

    /// 推進一隻正在走的企鵝：位置與步態每一格都照經過的時間前進（ADR 0007）；走到時回報。
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
        penguins[index].walking = walk
        moveAlong(index, distance: distance)
        needsDraw = true
        return nil
    }

    /// 從現在的位置走到 `goal` 的路，與這條路上已經走了幾格。
    /// - 站在格子上：從那一格找路，已經走了 0 格。
    /// - 停在兩格之間：往前走到 `to` 或回頭走到 `from`，挑總步數少的（一樣時往前），再從那一格找路；
    ///   路的第一步就是停的那一步，所以位置接得上、不會跳。
    /// - 到不了：停在原地；停在兩格之間時走到比較近的那一格。
    private func route(_ index: Int, to goal: Tile) -> (path: RoomPath, walked: Double) {
        guard let m = penguins[index].midway else {
            let here = Tile(containing: penguins[index].position)
            return (RoomPath.find(in: room, from: here, to: goal) ?? RoomPath(tiles: [here]), 0)
        }
        // 兩種走法：這一步從 back 走向 end，已經走了 walked
        let ways = [(back: m.from, end: m.to, walked: m.fraction), (back: m.to, end: m.from, walked: 1 - m.fraction)]
        let found = ways.compactMap { way in RoomPath.find(in: room, from: way.end, to: goal).map { (way: way, rest: $0) } }
        func cost(_ option: (way: (back: Tile, end: Tile, walked: Double), rest: RoomPath)) -> Double {
            1 - option.way.walked + Double(option.rest.steps)
        }
        if let best = found.min(by: { cost($0) < cost($1) }) {
            return (RoomPath(tiles: [best.way.back] + best.rest.tiles), best.way.walked)
        }
        let nearer = ways[m.fraction >= 0.5 ? 0 : 1]
        return (RoomPath(tiles: [nearer.back, nearer.end]), nearer.walked)
    }

    /// 走到一半時停在哪兩格之間；剛好在格子中心時是 nil。
    private static func midway(of walk: Walk) -> Midway? {
        let tiles = walk.path.tiles
        guard tiles.count > 1 else { return nil }
        let distance = walk.gait.tilesPerSecond * walk.elapsed
        let segment = min(Int(distance.rounded(.down)), tiles.count - 2)
        let fraction = distance - Double(segment)
        guard fraction > 0, fraction < 1 else { return nil }
        return Midway(from: tiles[segment], to: tiles[segment + 1], fraction: fraction)
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
        changed()
    }

    private func changed() {
        needsDraw = true
        onChange()
    }
}
