import Foundation

extension VectorRig {
    /// 灰色剪影的顏色：身體與外框。
    nonisolated static let placeholderFill = "#a3a3a3"
    nonisolated static let placeholderOutline = "#5e5e5e"

    /// 名單上同物種都沒有角色包（例如公開 repo 乾淨 clone）時的占位：不像任何玩偶的灰色剪影。
    ///
    /// 只有正面：圓頭、橢圓身體，手藏在身體裡，哈囉時才轉出來揮（`CharacterMotions.placeholder`）。
    /// 沒有斜向，走路時面向鏡頭平移。
    nonisolated static let placeholder: VectorRig = {
        func part(_ pivot: (Double, Double), _ e: [Double]) -> String {
            let shape = "{\"ellipse\": [\(e.map { "\($0)" }.joined(separator: ", "))]}"
            return "{\"pivot\": {\"x\": \(pivot.0), \"y\": \(pivot.1)}, \"silhouette\": [\(shape)], "
                + "\"layers\": [{\"fill\": \"\(placeholderFill)\", \"shapes\": [\(shape)]}]}"
        }
        let json = """
        {"format": 1, "outline": {"color": "\(placeholderOutline)", "width": 0.75},
         "facings": {"front": {"canvas": {"width": 31, "height": 36}, "feet": {"x": 15.5, "y": 35},
           "drawOrder": ["body", "arm", "head"],
           "parts": {"body": \(part((15.5, 35), [15.5, 24, 12, 10.5])),
                     "arm": \(part((24, 20), [24, 23, 1.5, 3])),
                     "head": \(part((15.5, 18), [15.5, 10, 8, 8]))}}}}
        """
        // 寫死在程式裡的資料，測試會確認讀得進來
        return try! VectorRig.decode(Data(json.utf8))
    }()

    /// 替身（作者 2026-11-19 決定；ADR 0009 只借同物種的）：名單上有一隻沒有角色包時，借同物種那隻的形狀，
    /// 整隻塗成和灰色剪影一樣的灰。
    ///
    /// 方向、姿勢、部件、轉軸都不變，所以那隻的動作片段可以直接用；每個部件只剩一層，用外形填滿灰色，
    /// 只看得到輪廓與外框（手腳在輪廓邊緣動），不會被當成那隻的分身。貼圖另外畫一份，記憶體算進預算。
    nonisolated func graySilhouette() -> VectorRig {
        func gray(_ facing: Facing) -> Facing {
            Facing(canvas: facing.canvas, feet: facing.feet, drawOrder: facing.drawOrder,
                   parts: facing.parts.mapValues { part in
                       Part(pivot: part.pivot, silhouette: part.silhouette,
                            layers: [Layer(fill: Self.placeholderFill, stroke: nil, width: nil,
                                           shapes: part.silhouette, clip: nil)], hidden: part.hidden)
                   }, shadow: facing.shadow, touch: facing.touch)
        }
        return VectorRig(format: format, outline: Outline(color: Self.placeholderOutline, width: outline.width),
                         facings: facings.mapValues(gray), mirrors: mirrors, postures: postures.mapValues(gray))
    }
}

extension CharacterMotions {
    /// 灰色剪影的動作：哈囉是程式裡寫好的幾個關鍵影格，只要看得出在打招呼（ADR 0009）。
    /// 長度和作者定案的企鵝哈囉一樣（舉手 0.35 秒、揮 1.4 秒、放下 0.35 秒、站好停 0.7 秒）：手舉起來上下各揮 8 度、
    /// 每秒 4 下，頭歪 9 度。走路照預設的速度，沒有斜向，所以不動手腳。
    nonisolated static let placeholder: CharacterMotions = {
        let raise = 0.35, wave = 1.4, lower = 0.35, settle = 0.7
        let waveEnd = raise + wave, lowerEnd = waveEnd + lower
        func key(_ t: Double, rotate: Double) -> MotionClip.Key { .init(time: t, pose: PartPose(rotate: rotate)) }
        // 揮手：每四分之一下一個關鍵影格（中間、最上、中間、最下）
        let quarter = 1.0 / (4 * 4)
        let waves = (0...Int((wave / quarter).rounded(.down))).map { k in
            key(raise + Double(k) * quarter, rotate: -140 + [0.0, 8, 0, -8][k % 4])
        }
        let arm = [key(0, rotate: 0)] + waves + [key(lowerEnd, rotate: 0)]
        let head = [key(0, rotate: 0), key(raise, rotate: -9), key(waveEnd, rotate: -9), key(lowerEnd, rotate: 0)]
        let hello = Motion(duration: raise + wave + lower + settle, facing: .front,
                           clips: ["front": MotionClip(tracks: ["arm": arm, "head": head])])
        return CharacterMotions(motions: ["hello": hello], gaits: defaultGaits)
    }()
}
