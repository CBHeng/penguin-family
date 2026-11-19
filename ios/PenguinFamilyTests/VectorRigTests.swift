import CoreGraphics
import Foundation
import Testing
@testable import PenguinFamily

/// 向量角色包（ADR 0007）：讀檔與檢查、正面的姿勢連動、部件畫成貼圖、角色包一起載入。
/// 用一隻 20×20 的假角色：身體、手、頭各一個橢圓，肚子只畫在身體裡（肚子的陰影要在身體裡、也要在肚子裡），頭上有一條曲線。
/// `walkingJSON` 再加上斜向：左前、左後畫好，右前、右後翻轉。
struct VectorRigTests {
    static let json = """
    {"format": 1, "outline": {"color": "#525e70", "width": 0.75},
     "facings": {"front": {"canvas": {"width": 20, "height": 20}, "feet": {"x": 10, "y": 18}, "neckY": 10,
       "drawOrder": ["body", "arm", "head"],
       "parts": {
         "body": {"pivot": {"x": 10, "y": 18}, "silhouette": [{"ellipse": [10, 14, 6, 4]}],
                  "layers": [{"fill": "#baccdc", "shapes": [{"ellipse": [10, 14, 6, 4]}]},
                             {"fill": "#f6f0e2", "clip": [[{"ellipse": [10, 14, 6, 4]}]], "shapes": [{"ellipse": [10, 16, 4, 4]}]},
                             {"fill": "#e2d9c6", "clip": [[{"ellipse": [10, 14, 6, 4]}], [{"ellipse": [10, 16, 4, 4]}]],
                              "shapes": [{"ellipse": [10, 18, 3, 1.2]}]}]},
         "arm": {"pivot": {"x": 15, "y": 12}, "silhouette": [{"ellipse": [16, 14, 1, 2]}],
                 "layers": [{"fill": "#baccdc", "shapes": [{"ellipse": [16, 14, 1, 2]}]}]},
         "head": {"pivot": {"x": 10, "y": 10}, "silhouette": [{"ellipse": [10, 7, 5, 4]}],
                  "layers": [{"fill": "#baccdc", "shapes": [{"ellipse": [10, 7, 5, 4]}]},
                             {"stroke": "#26262c", "width": 0.5, "shapes": [{"path": [["M", 8, 7], ["C", 8.5, 6, 9.5, 6, 10, 7]]}]}]}
       }}}}
    """

    /// 斜向的假角色：兩隻腳、身體、手、頭、帽子各一個橢圓，腳底在 (10, 18)，身體的轉軸在 (11, 18)。
    static func oblique(forwardY: Int, leftFoot: String, armSide: Int) -> String {
        func part(_ name: String, _ e: [Double], pivot: (Double, Double), color: String = "#baccdc") -> String {
            let shape = "{\"ellipse\": [\(e.map { "\($0)" }.joined(separator: ", "))]}"
            return "\"\(name)\": {\"pivot\": {\"x\": \(pivot.0), \"y\": \(pivot.1)}, \"silhouette\": [\(shape)], "
                + "\"layers\": [{\"fill\": \"\(color)\", \"shapes\": [\(shape)]}]}"
        }
        let parts = [
            part("farFoot", [7, 18, 2, 1], pivot: (7, 18), color: "#f9e9aa"),
            part("nearFoot", [13, 18, 2, 1], pivot: (13, 18), color: "#f9e9aa"),
            part("body", [11, 14, 6, 4], pivot: (11, 18)),
            part("arm", [16, 14, 1, 2], pivot: (16, 12)),
            part("head", [11, 7, 5, 4], pivot: (11, 18)),
            part("hat", [13, 3, 1, 1], pivot: (13, 3), color: "#de382e"),
        ].joined(separator: ", ")
        return """
        {"canvas": {"width": 20, "height": 20}, "feet": {"x": 10, "y": 18},
         "walk": {"forward": {"x": -2, "y": \(forwardY)}, "leftFoot": "\(leftFoot)", "armSide": \(armSide), "peek": {"farFoot": 1}},
         "drawOrder": ["farFoot", "nearFoot", "body", "arm", "head", "hat"], "parts": {\(parts)}}
        """
    }

    static let walkingJSON = String(json.dropLast(2)) + """
    , "frontLeft": \(oblique(forwardY: 1, leftFoot: "farFoot", armSide: 1)),
       "backLeft": \(oblique(forwardY: -1, leftFoot: "nearFoot", armSide: -1))},
     "mirrors": {
       "frontRight": {"of": "frontLeft", "drawOrder": ["farFoot", "nearFoot", "body", "arm", "hat", "head"],
                      "shift": {"hat": {"x": -4, "y": 0}}},
       "backRight": {"of": "backLeft", "drawOrder": ["farFoot", "nearFoot", "body", "arm", "head", "hat"], "shift": {}}}}
    """

    static func rig(_ text: String = json) throws -> VectorRig {
        try VectorRig.decode(Data(text.utf8))
    }

    // MARK: - 讀檔與檢查

    @Test func decodesShapesAndPaths() throws {
        let front = try Self.rig().front
        #expect(front.drawOrder == ["body", "arm", "head"])
        #expect(front.feet == VectorRig.Point(x: 10, y: 18))
        #expect(front.parts["arm"]?.silhouette == [.ellipse(cx: 16, cy: 14, rx: 1, ry: 2)])
        #expect(front.parts["head"]?.layers[1].shapes == [.path([.move(x: 8, y: 7), .curve(x1: 8.5, y1: 6, x2: 9.5, y2: 6, x: 10, y: 7)])])
        #expect(front.parts["body"]?.layers[1].clip?.count == 1)
        #expect(front.parts["body"]?.layers[2].clip?.count == 2)
    }

    @Test func rejectsBrokenRigs() {
        #expect(throws: CharacterRigError.unsupportedFormat(2)) {
            try Self.rig(Self.json.replacingOccurrences(of: "\"format\": 1", with: "\"format\": 2"))
        }
        #expect(throws: CharacterRigError.invalidColor("red")) {
            try Self.rig(Self.json.replacingOccurrences(of: "\"#26262c\"", with: "\"red\""))
        }
        // 少了手：哈囉會動它，一定要有
        #expect(throws: CharacterRigError.missingPart("arm")) {
            try Self.rig(Self.json.replacingOccurrences(of: "\"arm\": {", with: "\"wing\": {")
                .replacingOccurrences(of: "\"body\", \"arm\", \"head\"", with: "\"body\", \"wing\", \"head\""))
        }
        // drawOrder 沒有剛好列出每個部件
        #expect(throws: CharacterRigError.invalidDirection("front")) {
            try Self.rig(Self.json.replacingOccurrences(of: "\"body\", \"arm\", \"head\"", with: "\"body\", \"head\""))
        }
        // 路徑不是 M 開頭
        #expect(throws: (any Error).self) {
            try Self.rig(Self.json.replacingOccurrences(of: "[[\"M\", 8, 7], ", with: "["))
        }
        // 裁切有一組是空的
        #expect(throws: CharacterRigError.missingPart("body")) {
            try Self.rig(Self.json.replacingOccurrences(of: "\"clip\": [[{\"ellipse\": [10, 14, 6, 4]}]]", with: "\"clip\": [[]]"))
        }
    }

    @Test func rejectsBrokenObliques() {
        // 斜向少了怎麼走
        #expect(throws: CharacterRigError.invalidDirection("backLeft")) {
            try Self.rig(Self.walkingJSON.replacingOccurrences(of: "\"leftFoot\": \"nearFoot\"", with: "\"leftFoot\": \"wing\""))
        }
        // 翻轉的來源不存在
        #expect(throws: CharacterRigError.invalidDirection("backRight")) {
            try Self.rig(Self.walkingJSON.replacingOccurrences(of: "\"of\": \"backLeft\"", with: "\"of\": \"back\""))
        }
        // 翻轉的方向不能是正面
        #expect(throws: CharacterRigError.invalidDirection("backRight")) {
            try Self.rig(Self.walkingJSON.replacingOccurrences(of: "\"of\": \"backLeft\"", with: "\"of\": \"front\""))
        }
    }

    // MARK: - 正面的姿勢

    static func apply(_ t: Affine2D?, _ x: Double, _ y: Double) -> (x: Double, y: Double) {
        (t ?? .identity).apply(x, y)
    }

    @Test func restMovesNothing() throws {
        let transforms = try Self.rig().front.frontTransforms(.rest)
        #expect(Set(transforms.keys) == ["body", "arm", "head"])
        for t in transforms.values { #expect(t == .identity) }
    }

    @Test func partsTurnAroundTheirPivots() throws {
        let front = try Self.rig().front
        let t = front.frontTransforms(RigPose(headDegrees: -9, armDegrees: -140, squash: 1))
        let shoulder = Self.apply(t["arm"], 15, 12), neck = Self.apply(t["head"], 10, 10)
        #expect(abs(shoulder.x - 15) < 1e-12 && abs(shoulder.y - 12) < 1e-12)
        #expect(abs(neck.x - 10) < 1e-12 && abs(neck.y - 10) < 1e-12)
        // 手往畫面右上舉：手的中心（肩膀下方 2）轉 -140 度（逆時針）後在肩膀右上方
        let hand = Self.apply(t["arm"], 15, 14)
        #expect(hand.x > 15 && hand.y < 12)
    }

    @Test func squashKeepsFeetAndMovesHeadAndArm() throws {
        let front = try Self.rig().front
        let t = front.frontTransforms(RigPose(headDegrees: 0, armDegrees: 0, squash: 0.9))
        let feet = Self.apply(t["body"], 10, 18)
        #expect(abs(feet.x - 10) < 1e-12 && abs(feet.y - 18) < 1e-12)       // 腳底不動
        let neck = Self.apply(t["head"], 10, 10)
        #expect(abs(neck.y - (10 + (18 - 10) * 0.1)) < 1e-12)                // 身體變矮，頭往下（不取整數）
        let shoulder = Self.apply(t["arm"], 15, 12)
        #expect(abs(shoulder.x - (15 + (15 - 10) * (1 / 0.9 - 1))) < 1e-12)  // 身體變寬，手往外
    }

    // MARK: - 斜向的姿勢

    @Test func eachObliqueHasALook() throws {
        let rig = try Self.rig(Self.walkingJSON)
        #expect(rig.look("frontLeft")?.mirror == nil && rig.look("frontLeft")?.source == "frontLeft")
        let right = try #require(rig.look("frontRight"))
        #expect(right.source == "frontLeft" && right.drawOrder.suffix(2) == ["hat", "head"])   // 帽子畫在頭後面
        #expect(rig.walk("backRight")?.armSide == -1)                                          // 用來源的走法
        #expect(try Self.rig().look("frontLeft") == nil)                                       // 沒有斜向的角色包
    }

    @Test func obliqueRestMovesNothing() throws {
        let rig = try Self.rig(Self.walkingJSON)
        let frame = try #require(rig.frame(.oblique(.frontLeft, .rest)))
        #expect(Set(frame.transforms.keys) == Set(frame.look.drawOrder))
        for t in frame.transforms.values { #expect(t == .identity) }
    }

    @Test func mirroredFacingFlipsAroundTheFeet() throws {
        let rig = try Self.rig(Self.walkingJSON)
        let t = try #require(rig.frame(.oblique(.frontRight, .rest))).transforms
        let body = Self.apply(t["body"], 11, 14)
        #expect(abs(body.x - 9) < 1e-12 && abs(body.y - 14) < 1e-12)           // 以腳底 x = 10 翻轉
        let hat = Self.apply(t["hat"], 13, 3)
        #expect(abs(hat.x - (20 - (13 - 4))) < 1e-12)                           // 先往左挪 4 再翻
        #expect((t["head"]?.a ?? 1) == -1)
    }

    @Test func walkingSwaysTheUpperBodyAndOpensTheArm() throws {
        let rig = try Self.rig(Self.walkingJSON)
        var pose = VectorWalkPose(swayDegrees: 10, dip: 0.5, armOpenDegrees: 20, armDy: 0.25)
        pose.feet["nearFoot"] = .init(dx: -1, dy: 0.5)
        let t = try #require(rig.frame(.oblique(.frontLeft, pose))).transforms
        let base = Self.apply(t["body"], 11, 18)
        #expect(abs(base.x - 11) < 1e-12 && abs(base.y - 18.5) < 1e-12)       // 軸不動，只往下沉
        let top = Self.apply(t["head"], 11, 3)
        #expect(top.x > 11 + 2)                                                  // 順時針傾斜：上面往右
        let swayOnly = Self.apply(t["body"], 16, 14)
        let hand = Self.apply(t["arm"], 16, 14)
        #expect(hand.x > swayOnly.x)                                             // 手在右側，往外是往右
        let foot = Self.apply(t["nearFoot"], 13, 18)
        #expect(foot.x == 12 && foot.y == 18.5)                                  // 腳只平移
        #expect(t["farFoot"] == .identity)
    }

    @Test func gaitPoseIsSmoothAndLandsAtTheRightTime() throws {
        let walk = try #require(try Self.rig(Self.walkingJSON).walk("frontLeft"))
        for gait in Gait.all {
            var last = gait.vectorPose(at: 0, walk: walk)
            #expect(abs(last.dip - Double(gait.dip)) < 1e-12)                    // 換腳落地時最低
            for k in 1...1000 {
                let pose = gait.vectorPose(at: gait.cycle * Double(k) / 1000, walk: walk)
                // 不再整格跳：相鄰兩個時間點只差一點點
                #expect(abs(pose.swayDegrees - last.swayDegrees) < 0.1 && abs(pose.dip - last.dip) < 0.05)
                for (name, o) in pose.feet {
                    let p = try #require(last.feet[name])
                    #expect(abs(o.dx - p.dx) < 0.05 && abs(o.dy - p.dy) < 0.05, "\(gait.name) \(name) at \(k)")
                }
                last = pose
            }
            // 四分之一個循環：身體往右傾到底，畫面左邊的腳抬起、在前後的正中間
            let quarter = gait.vectorPose(at: gait.cycle / 4, walk: walk)
            #expect(abs(quarter.swayDegrees - (gait.sway - gait.lean)) < 1e-9)   // 往左走，前傾是往左
            #expect(abs((quarter.feet["farFoot"]?.dy ?? 0) + Double(gait.lift)) < 1e-9)
        }
    }

    // MARK: - 畫成貼圖

    /// 某一點（角色畫布的單位）在圖上的 RGBA。
    static func pixel(_ bitmap: PixelBitmap, _ bounds: CGRect, _ ppu: Double, _ x: Double, _ y: Double) -> [UInt8] {
        let px = Int((x - bounds.minX) * ppu), py = Int((y - bounds.minY) * ppu)
        let i = (py * bitmap.width + px) * 4
        return Array(bitmap.rgba[i..<i + 4])
    }

    @Test func rasterizesEachPartInDrawOrder() throws {
        let ppu = 4.0
        let parts = VectorRasterizer.rasterize(try Self.rig(), facing: "front", pixelsPerUnit: ppu)
        #expect(parts.map(\.name) == ["body", "arm", "head"])
        let body = parts[0], b = body.bounds
        // 範圍是整數單位，蓋住外形、外框、每一層（肚子到 y = 20）與 1 單位的邊
        #expect(b.minX == 2 && b.minY == 8 && b.maxX == 18 && b.maxY == 21)
        #expect(body.fill.width == 64 && body.fill.height == 52 && body.outline.width == 64)
        // 顏色：身體邊上是藍，肚子是米白；肚子超出身體的部分被裁掉
        #expect(Self.pixel(body.fill, b, ppu, 5, 14) == [0xba, 0xcc, 0xdc, 255])
        #expect(Self.pixel(body.fill, b, ppu, 10, 16) == [0xf6, 0xf0, 0xe2, 255])
        #expect(Self.pixel(body.fill, b, ppu, 10, 18.6)[3] == 0)
        // 好幾組裁切取交集：陰影只在身體與肚子都有的地方
        #expect(Self.pixel(body.fill, b, ppu, 10, 17.3) == [0xe2, 0xd9, 0xc6, 255])
        // 外框：形狀外面 0.75 單位內是外框色，再外面是透明
        #expect(Self.pixel(body.outline, b, ppu, 3.6, 14) == [0x52, 0x5e, 0x70, 255])
        #expect(Self.pixel(body.outline, b, ppu, 10, 14) == [0x52, 0x5e, 0x70, 255])
        #expect(Self.pixel(body.outline, b, ppu, 3.1, 9.1)[3] == 0)
        #expect(body.byteCount == 64 * 52 * 4 * 2)
    }

    /// 記憶體預算的測試用算的（不真的畫），要和真的畫出來的圖一樣大。
    @Test func textureBytesMatchTheRasterizedImages() throws {
        let rig = try Self.rig(Self.walkingJSON)
        let drawn = rig.facings.keys.reduce(0) { total, facing in
            VectorRasterizer.rasterize(rig, facing: facing, pixelsPerUnit: 4).reduce(total) { $0 + $1.byteCount * 4 / 3 }
        }
        #expect(drawn > 0 && VectorRasterizer.textureBytes(rig, pixelsPerUnit: 4) == drawn)
    }

    // MARK: - 角色包

    @Test func packLoadsVectorWhenPresentAndSkipsBrokenOne() throws {
        let root = try PenguinDisplayTests.makeRoot(["a": RigCompositorTests.fakeJSON, "b": RigCompositorTests.fakeJSON,
                                                     "c": RigCompositorTests.fakeJSON])
        try Data(Self.json.utf8).write(to: root.appending(path: "a/vector.json"))
        try Data("{ not json".utf8).write(to: root.appending(path: "b/vector.json"))
        let family = CharacterPackLibrary.loadFamily(in: root)
        #expect(family.map { $0?.id } == ["a", "c"])         // b 的向量造型壞掉：整個角色包不用
        #expect(family[0]?.vector?.front.canvas == VectorRig.Size(width: 20, height: 20))
        #expect(family[1]?.vector == nil)                     // 沒有 vector.json：只有像素造型
    }
}
