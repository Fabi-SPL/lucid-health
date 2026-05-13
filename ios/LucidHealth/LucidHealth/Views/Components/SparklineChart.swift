import SwiftUI
import Charts

/// 7-day branded sparkline using Swift Charts.
/// Shows data line + baseline ± 1σ band.
/// Violet→teal gradient line, muted baseline band.
struct SparklineChart: View {
    let values: [Double]        // newest last, max 7 values
    let baseline: Double        // personal mean
    var sigma: Double = 5.0     // 1 standard deviation band width (default ±5ms for HRV)
    var height: CGFloat = 56
    var accentColor: Color = DS.Colors.violet

    private var minY: Double {
        let lo = min(values.min() ?? 0, baseline - sigma * 1.5)
        return max(lo - 2, 0)
    }
    private var maxY: Double {
        let hi = max(values.max() ?? 1, baseline + sigma * 1.5)
        return hi + 2
    }

    // Build indexed data for Charts
    private var chartData: [(index: Int, value: Double)] {
        values.enumerated().map { (index: $0.offset, value: $0.element) }
    }

    var body: some View {
        Chart {
            // Baseline ± 1σ band (area mark)
            RectangleMark(
                xStart: .value("start", 0),
                xEnd: .value("end", max(values.count - 1, 1)),
                yStart: .value("low",  baseline - sigma),
                yEnd:   .value("high", baseline + sigma)
            )
            .foregroundStyle(DS.Colors.teal.opacity(0.08))

            // Baseline dashed line
            RuleMark(y: .value("Baseline", baseline))
                .lineStyle(StrokeStyle(lineWidth: 0.8, dash: [4, 3]))
                .foregroundStyle(DS.Colors.teal.opacity(0.40))

            // Data line with violet→teal gradient via LineMark + interpolation
            ForEach(chartData, id: \.index) { pt in
                LineMark(
                    x: .value("Day", pt.index),
                    y: .value("Value", pt.value)
                )
                .interpolationMethod(.catmullRom)
                .lineStyle(StrokeStyle(lineWidth: 2.0, lineCap: .round))
                .foregroundStyle(
                    LinearGradient(
                        colors: [DS.Colors.violet.opacity(0.8), DS.Colors.teal],
                        startPoint: .leading, endPoint: .trailing
                    )
                )

                // Last point dot
                if pt.index == chartData.indices.last {
                    PointMark(
                        x: .value("Day", pt.index),
                        y: .value("Value", pt.value)
                    )
                    .symbolSize(28)
                    .foregroundStyle(DS.Colors.teal)
                }
            }
        }
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .chartYScale(domain: minY...maxY)
        .chartXScale(domain: 0...(max(values.count - 1, 1)))
        .frame(height: height)
    }
}

#Preview {
    ZStack {
        MeshGradientBackground()
        VStack(spacing: 20) {
            SparklineChart(
                values: [42, 45, 39, 52, 48, 51, 55],
                baseline: 47,
                sigma: 5
            )
            .padding()
            .glassCard()
        }
        .padding()
    }
}
