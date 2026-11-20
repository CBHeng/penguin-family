import Foundation

extension VectorRig {
    /// 灰色剪影的顏色：身體與外框。
    nonisolated static let placeholderFill = "#a3a3a3"
    nonisolated static let placeholderOutline = "#5e5e5e"

    /// 一家都沒有角色包（例如公開 repo 乾淨 clone）時的占位：不像任何玩偶的灰色剪影。
    ///
    /// 只有正面：圓頭、橢圓身體，手藏在身體裡，哈囉時才轉出來揮。沒有斜向，走路時面向鏡頭平移。
    nonisolated static let placeholder: VectorRig = {
        func part(_ pivot: (Double, Double), _ e: [Double]) -> String {
            let shape = "{\"ellipse\": [\(e.map { "\($0)" }.joined(separator: ", "))]}"
            return "{\"pivot\": {\"x\": \(pivot.0), \"y\": \(pivot.1)}, \"silhouette\": [\(shape)], "
                + "\"layers\": [{\"fill\": \"\(placeholderFill)\", \"shapes\": [\(shape)]}]}"
        }
        let json = """
        {"format": 1, "outline": {"color": "\(placeholderOutline)", "width": 0.75},
         "facings": {"front": {"canvas": {"width": 31, "height": 36}, "feet": {"x": 15.5, "y": 35}, "neckY": 18,
           "drawOrder": ["body", "arm", "head"],
           "parts": {"body": \(part((15.5, 35), [15.5, 24, 12, 10.5])),
                     "arm": \(part((24, 20), [24, 23, 1.5, 3])),
                     "head": \(part((15.5, 18), [15.5, 10, 8, 8]))}}}}
        """
        // 寫死在程式裡的資料，測試會確認讀得進來
        return try! VectorRig.decode(Data(json.utf8))
    }()

    /// 替身（作者 2026-11-19 決定）：一家有一隻沒有角色包時，借這隻的形狀，整隻塗成和灰色剪影一樣的灰。
    ///
    /// 方向、部件、轉軸、走法都不變，所以斜向與走路和這隻一樣；每個部件只剩一層，用外形填滿灰色，
    /// 只看得到輪廓與外框（手腳在輪廓邊緣動），不會被當成這隻的分身。貼圖另外畫一份，記憶體算進預算。
    nonisolated func graySilhouette() -> VectorRig {
        func gray(_ facing: Facing) -> Facing {
            Facing(canvas: facing.canvas, feet: facing.feet, neckY: facing.neckY, walk: facing.walk,
                   drawOrder: facing.drawOrder,
                   parts: facing.parts.mapValues { part in
                       Part(pivot: part.pivot, silhouette: part.silhouette,
                            layers: [Layer(fill: Self.placeholderFill, stroke: nil, width: nil,
                                           shapes: part.silhouette, clip: nil)])
                   })
        }
        return VectorRig(format: format, outline: Outline(color: Self.placeholderOutline, width: outline.width),
                         facings: facings.mapValues(gray), mirrors: mirrors)
    }
}
