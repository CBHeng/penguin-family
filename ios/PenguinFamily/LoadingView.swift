import SwiftUI

/// 載入畫面：和箱庭外面同一個底色，中間三個小方塊輪流亮起。
///
/// 暫時的樣子，不放企鵝、不放台詞（台詞只能由作者寫）；之後可以換成正式的圖。
struct LoadingView: View {
    /// 方塊邊長（pt）：箱庭最大倍率（每單位 3pt）時的 3 個單位。
    private static let dot: CGFloat = 3 * 3
    /// 每隔多久換下一個方塊亮（秒）。
    private static let step = 0.3

    var body: some View {
        ZStack {
            GameView.outsideColor
                .ignoresSafeArea()
            TimelineView(.periodic(from: .now, by: Self.step)) { context in
                let lit = Int(context.date.timeIntervalSinceReferenceDate / Self.step) % 3
                HStack(spacing: Self.dot) {
                    ForEach(0..<3, id: \.self) { i in
                        Rectangle()
                            .fill(.white.opacity(i == lit ? 0.9 : 0.3))
                            .frame(width: Self.dot, height: Self.dot)
                    }
                }
            }
        }
        .accessibilityElement()
        .accessibilityLabel("載入中")
    }
}

#Preview {
    LoadingView()
}
