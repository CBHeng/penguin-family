import QuartzCore
import SwiftUI

/// 角色的屬性條（作者 2026-11-27 要求）：畫面角落的面板，台上每一隻一列，列出牠的屬性（例如睏意、耐心）與門檻線。
///
/// 不寫死有幾隻、有哪些屬性：照模擬的快照（`SimulationSnapshot.Character.meters`）畫，之後加角色、加屬性都不用改這裡。
/// 名字顯示名單上的 id（角色包的資料夾名稱，只在執行時出現在手機上）。可以收合。
/// 每秒更新 4 次：快照記的是「某一刻的值與每秒變多少」，這裡照現在的模擬時間往前推算，模擬停下來時也看得到在變。
///
/// 還沒 release，所以每個版本都顯示；上架前關掉（`isEnabled`，作者 2026-11-27 決定）。
struct AttributePanel: View {
    /// 要不要顯示。上架前改成 false（TASKS 的「小待辦」有記）。
    static let isEnabled = true

    let runner: SimulationRunner
    @State private var expanded = true

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button {
                expanded.toggle()
            } label: {
                Label("屬性", systemImage: expanded ? "chevron.up" : "chevron.down")
                    .font(.caption.bold())
            }
            .accessibilityLabel(expanded ? "收起屬性" : "展開屬性")
            if expanded {
                TimelineView(.periodic(from: .now, by: 0.25)) { _ in
                    let latest = runner.latest
                    let time = CACurrentMediaTime() - latest.epoch
                    ScrollView {
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(latest.current.characters, id: \.id) { character in
                                CharacterRow(character: character, time: time)
                            }
                        }
                    }
                    .frame(maxHeight: 260)
                    .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .foregroundStyle(.white)
        .padding(10)
        .frame(width: 190, alignment: .leading)
        .background(.black.opacity(0.45), in: RoundedRectangle(cornerRadius: 10))
    }

    /// 一隻：名字，再一個屬性一行。
    private struct CharacterRow: View {
        let character: SimulationSnapshot.Character
        let time: Double

        var body: some View {
            VStack(alignment: .leading, spacing: 3) {
                Text(character.id.rawValue)
                    .font(.caption.bold())
                if character.meters.isEmpty {
                    Text("沒有屬性").font(.caption2).opacity(0.7)
                }
                ForEach(character.meters, id: \.id) { meter in
                    MeterRow(meter: meter, level: meter.level(at: time))
                }
            }
        }
    }

    /// 一個屬性：名稱、條（標門檻線）、數字。
    private struct MeterRow: View {
        let meter: SimulationSnapshot.Meter
        let level: Double

        var body: some View {
            HStack(spacing: 6) {
                Text(meter.label)
                    .font(.caption2)
                    .frame(width: 28, alignment: .leading)
                MeterBar(meter: meter, level: level)
                    .frame(height: 8)
                Text("\(Int(level.rounded()))")
                    .font(.caption2.monospacedDigit())
                    .frame(width: 26, alignment: .trailing)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(meter.label) \(Int(level.rounded()))")
        }
    }

    /// 條：底、填滿的部分、門檻線（從那隻的資料讀）。
    private struct MeterBar: View {
        let meter: SimulationSnapshot.Meter
        let level: Double

        private func fraction(_ value: Double) -> Double {
            let span = meter.range.upperBound - meter.range.lowerBound
            return span > 0 ? min(max((value - meter.range.lowerBound) / span, 0), 1) : 0
        }

        var body: some View {
            GeometryReader { proxy in
                let width = proxy.size.width
                ZStack(alignment: .leading) {
                    Capsule().fill(.white.opacity(0.2))
                    Capsule().fill(.white.opacity(0.85))
                        .frame(width: width * fraction(level))
                    ForEach(meter.marks, id: \.value) { mark in
                        Rectangle()
                            .fill(Color.orange)
                            .frame(width: 2)
                            .offset(x: width * fraction(mark.value) - 1)
                    }
                }
            }
        }
    }
}
