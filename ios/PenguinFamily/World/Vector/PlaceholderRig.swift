import Foundation

extension VectorRig {
    /// 沒有角色包（例如公開 repo 乾淨 clone）或第二隻的美術還沒好時的占位：不像任何玩偶的灰色剪影。
    ///
    /// 只有正面：圓頭、橢圓身體，手藏在身體裡，哈囉時才轉出來揮。沒有斜向，走路時面向鏡頭平移。
    nonisolated static let placeholder: VectorRig = {
        let gray = "#a3a3a3"
        func part(_ pivot: (Double, Double), _ e: [Double]) -> String {
            let shape = "{\"ellipse\": [\(e.map { "\($0)" }.joined(separator: ", "))]}"
            return "{\"pivot\": {\"x\": \(pivot.0), \"y\": \(pivot.1)}, \"silhouette\": [\(shape)], "
                + "\"layers\": [{\"fill\": \"\(gray)\", \"shapes\": [\(shape)]}]}"
        }
        let json = """
        {"format": 1, "outline": {"color": "#5e5e5e", "width": 0.75},
         "facings": {"front": {"canvas": {"width": 31, "height": 36}, "feet": {"x": 15.5, "y": 35}, "neckY": 18,
           "drawOrder": ["body", "arm", "head"],
           "parts": {"body": \(part((15.5, 35), [15.5, 24, 12, 10.5])),
                     "arm": \(part((24, 20), [24, 23, 1.5, 3])),
                     "head": \(part((15.5, 18), [15.5, 10, 8, 8]))}}}}
        """
        // 寫死在程式裡的資料，測試會確認讀得進來
        return try! VectorRig.decode(Data(json.utf8))
    }()
}
