import CoreGraphics
import Foundation
import Testing
@testable import PenguinFamily

/// 向量角色包（ADR 0007）：讀檔與檢查、部件照姿勢動與翻轉（ADR 0009）、部件畫成貼圖、角色包一起載入。
/// 用一隻 20×20 的假角色：身體、手、頭各一個橢圓，肚子只畫在身體裡（肚子的陰影要在身體裡、也要在肚子裡），頭上有一條曲線。
/// `walkingJSON` 再加上斜向：左前、左後畫好，右前、右後翻轉。
struct VectorRigTests {
    static let json = """
    {"format": 1, "outline": {"color": "#525e70", "width": 0.75},
     "facings": {"front": {"canvas": {"width": 20, "height": 20}, "feet": {"x": 10, "y": 18},
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
    static func oblique() -> String {
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
         "drawOrder": ["farFoot", "nearFoot", "body", "arm", "head", "hat"], "parts": {\(parts)}}
        """
    }

    static let walkingJSON = String(json.dropLast(2)) + """
    , "frontLeft": \(oblique()),
       "backLeft": \(oblique())},
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
        #expect(throws: VectorRigError.unsupportedFormat(2)) {
            try Self.rig(Self.json.replacingOccurrences(of: "\"format\": 1", with: "\"format\": 2"))
        }
        #expect(throws: VectorRigError.invalidColor("red")) {
            try Self.rig(Self.json.replacingOccurrences(of: "\"#26262c\"", with: "\"red\""))
        }
        // 沒有正面
        #expect(throws: VectorRigError.invalidDirection("front")) {
            try Self.rig(Self.json.replacingOccurrences(of: "\"front\": {", with: "\"frontLeft\": {"))
        }
        // drawOrder 沒有剛好列出每個部件
        #expect(throws: VectorRigError.invalidDirection("front")) {
            try Self.rig(Self.json.replacingOccurrences(of: "\"body\", \"arm\", \"head\"", with: "\"body\", \"head\""))
        }
        // 路徑不是 M 開頭
        #expect(throws: (any Error).self) {
            try Self.rig(Self.json.replacingOccurrences(of: "[[\"M\", 8, 7], ", with: "["))
        }
        // 裁切有一組是空的
        #expect(throws: VectorRigError.missingPart("body")) {
            try Self.rig(Self.json.replacingOccurrences(of: "\"clip\": [[{\"ellipse\": [10, 14, 6, 4]}]]", with: "\"clip\": [[]]"))
        }
    }

    @Test func rejectsBrokenObliques() {
        // 不認得的方向名稱
        #expect(throws: VectorRigError.invalidDirection("left")) {
            try Self.rig(Self.walkingJSON.replacingOccurrences(of: "\"backLeft\": {", with: "\"left\": {"))
        }
        // 翻轉的來源不存在
        #expect(throws: VectorRigError.invalidDirection("backRight")) {
            try Self.rig(Self.walkingJSON.replacingOccurrences(of: "\"of\": \"backLeft\"", with: "\"of\": \"back\""))
        }
        // 翻轉的方向不能是正面
        #expect(throws: VectorRigError.invalidDirection("backRight")) {
            try Self.rig(Self.walkingJSON.replacingOccurrences(of: "\"of\": \"backLeft\"", with: "\"of\": \"front\""))
        }
    }

    // MARK: - 部件的姿勢（ADR 0009：不分物種，部件照姿勢以自己的轉軸動）

    static func apply(_ t: Affine2D?, _ x: Double, _ y: Double) -> (x: Double, y: Double) {
        (t ?? .identity).apply(x, y)
    }

    static func transforms(_ rig: VectorRig, _ facing: Facing, _ parts: [String: PartPose] = [:]) throws -> [String: Affine2D] {
        try #require(rig.frame(CharacterPose(facing: facing, parts: parts))).transforms
    }

    @Test func restMovesNothing() throws {
        let transforms = try Self.transforms(try Self.rig(), .front)
        #expect(Set(transforms.keys) == ["body", "arm", "head"])
        for t in transforms.values { #expect(t == .identity) }
    }

    @Test func partsTurnAroundTheirPivots() throws {
        let t = try Self.transforms(try Self.rig(), .front, ["arm": PartPose(rotate: -140), "head": PartPose(rotate: -9)])
        let shoulder = Self.apply(t["arm"], 15, 12), neck = Self.apply(t["head"], 10, 10)
        #expect(abs(shoulder.x - 15) < 1e-12 && abs(shoulder.y - 12) < 1e-12)
        #expect(abs(neck.x - 10) < 1e-12 && abs(neck.y - 10) < 1e-12)
        // 手往畫面右上舉：手的中心（肩膀下方 2）轉 -140 度（逆時針）後在肩膀右上方
        let hand = Self.apply(t["arm"], 15, 14)
        #expect(hand.x > 15 && hand.y < 12)
        #expect(t["body"] == .identity)                                          // 沒列到的部件在原位
    }

    @Test func scaleKeepsThePivotAndMoveIsAddedAfter() throws {
        let t = try Self.transforms(try Self.rig(), .front, [
            "body": PartPose(scaleX: 1 / 0.9, scaleY: 0.9),
            "head": PartPose(rotate: 90, x: 0, y: 0.8),
        ])
        let feet = Self.apply(t["body"], 10, 18)
        #expect(abs(feet.x - 10) < 1e-12 && abs(feet.y - 18) < 1e-12)           // 以轉軸（腳底）縮放：腳底不動
        let top = Self.apply(t["body"], 10, 8)
        #expect(abs(top.y - (18 - 10 * 0.9)) < 1e-12)                            // 身體變矮
        let neck = Self.apply(t["head"], 10, 10)
        #expect(abs(neck.x - 10) < 1e-12 && abs(neck.y - 10.8) < 1e-12)         // 先以轉軸轉，再往下移
    }

    @Test func anyPartNamesWork() throws {
        // 不分物種：部件叫什麼都可以（例如沒有手、有鰭）
        let finned = try Self.rig(Self.json.replacingOccurrences(of: "\"arm\"", with: "\"fin\""))
        #expect(finned.front.drawOrder == ["body", "fin", "head"])
        let t = try Self.transforms(finned, .front, ["fin": PartPose(rotate: 30)])
        #expect(t["fin"] != .identity && t["body"] == .identity)
    }

    // MARK: - 斜向與翻轉

    @Test func eachObliqueHasALook() throws {
        let rig = try Self.rig(Self.walkingJSON)
        #expect(rig.look("frontLeft")?.mirror == nil && rig.look("frontLeft")?.source == "frontLeft")
        let right = try #require(rig.look("frontRight"))
        #expect(right.source == "frontLeft" && right.drawOrder.suffix(2) == ["hat", "head"])   // 帽子畫在頭後面
        #expect(try Self.rig().look("frontLeft") == nil)                                       // 沒有斜向的角色包
    }

    @Test func obliqueRestMovesNothing() throws {
        let rig = try Self.rig(Self.walkingJSON)
        let frame = try #require(rig.frame(CharacterPose(facing: .frontLeft)))
        #expect(Set(frame.transforms.keys) == Set(frame.look.drawOrder))
        for t in frame.transforms.values { #expect(t == .identity) }
    }

    @Test func mirroredFacingFlipsAroundTheFeet() throws {
        let t = try Self.transforms(try Self.rig(Self.walkingJSON), .frontRight)
        let body = Self.apply(t["body"], 11, 14)
        #expect(abs(body.x - 9) < 1e-12 && abs(body.y - 14) < 1e-12)           // 以腳底 x = 10 翻轉
        let hat = Self.apply(t["hat"], 13, 3)
        #expect(abs(hat.x - (20 - (13 - 4))) < 1e-12)                           // 先往左挪 4 再翻
        #expect((t["head"]?.a ?? 1) == -1)
    }

    @Test func mirroredFacingUsesTheSourcePoseThenFlips() throws {
        // 翻轉的方向用來源的姿勢：右前的手 = 左前的手再以腳底翻轉
        let rig = try Self.rig(Self.walkingJSON)
        let pose: [String: PartPose] = ["arm": PartPose(rotate: 20, y: 0.5), "nearFoot": PartPose(x: -1, y: 0.5)]
        let left = try Self.transforms(rig, .frontLeft, pose), right = try Self.transforms(rig, .frontRight, pose)
        let flip = Affine2D(a: -1, b: 0, c: 0, d: 1, tx: 20, ty: 0)
        for name in ["arm", "nearFoot", "body"] {
            let want = flip * (left[name] ?? .identity), got = right[name] ?? .identity
            #expect(abs(got.a - want.a) < 1e-12 && abs(got.tx - want.tx) < 1e-12 && abs(got.ty - want.ty) < 1e-12, "\(name)")
        }
        let foot = Self.apply(left["nearFoot"], 13, 18)
        #expect(foot.x == 12 && foot.y == 18.5)                                  // 只有位移時就是平移
    }

    // MARK: - 畫成貼圖

    /// 某一點（角色畫布的單位）在圖上的 RGBA。
    static func pixel(_ bitmap: RGBABitmap, _ bounds: CGRect, _ ppu: Double, _ x: Double, _ y: Double) -> [UInt8] {
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

    // MARK: - 替身（作者 2026-11-19 決定：沒有角色包的那隻，借別隻的形狀塗灰）

    @Test func graySilhouetteKeepsTheShapesButPaintsThemGray() throws {
        let rig = try Self.rig(Self.walkingJSON)
        let gray = rig.graySilhouette()
        try gray.validate()
        #expect(gray.outline.color == VectorRig.placeholderOutline && gray.outline.width == rig.outline.width)
        #expect(Set(gray.facings.keys) == Set(rig.facings.keys) && Set(gray.mirrors.keys) == Set(rig.mirrors.keys))
        for (name, facing) in rig.facings {
            let g = try #require(gray.facings[name])
            #expect(g.canvas == facing.canvas && g.feet == facing.feet && g.drawOrder == facing.drawOrder)
            for (partName, part) in facing.parts {
                let p = try #require(g.parts[partName])
                #expect(p.pivot == part.pivot && p.silhouette == part.silhouette, "\(name).\(partName)")
                // 只剩一層：外形填滿灰色，裡面的顏色、肚子、描線都不畫
                #expect(p.layers.count == 1 && p.layers[0].fill == VectorRig.placeholderFill && p.layers[0].shapes == part.silhouette)
            }
        }
        // 畫出來整個身體都是灰色（肚子的位置也是）
        let body = try #require(VectorRasterizer.rasterize(gray, facing: "front", pixelsPerUnit: 4).first { $0.name == "body" })
        #expect(Self.pixel(body.fill, body.bounds, 4, 10, 17) == [0xa3, 0xa3, 0xa3, 255])
    }

    // MARK: - 角色包

    @Test func packLoadsItsVector() throws {
        let root = try CharacterDisplayTests.makeRoot(["a": Self.json])
        let family = CharacterPackLibrary.loadFamily(in: root)
        #expect(family[0].character?.vector.front.canvas == VectorRig.Size(width: 20, height: 20))
    }
}
