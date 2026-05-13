import SwiftUI

/// Mini HRV sparkline with a baseline band.
struct HRVSparkline: View {
    let values: [Double]     // recent RMSSD readings (newest last)
    let baseline: Double     // personal baseline

    private var minVal: Double { (values.min() ?? 0).clamped(to: 0...999) }
    private var maxVal: Double { max((values.max() ?? 1), minVal + 1) }
    private var range: Double { maxVal - minVal }

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let count = values.count

            if count < 2 {
                Text("Zu wenig Daten")
                    .font(.system(size: 9))
                    .foregroundStyle(DS.Colors.textFaint)
            } else {
                ZStack(alignment: .bottomLeading) {
                    // Baseline band (+/- 5ms)
                    let bandY = yPos(baseline, height: h)
                    let bandTop = yPos(baseline + 5, height: h)
                    let bandBot = yPos(baseline - 5, height: h)
                    Rectangle()
                        .fill(DS.Colors.teal.opacity(0.08))
                        .frame(height: max(1, bandBot - bandTop))
                        .offset(y: bandTop)

                    // Baseline line
                    Path { p in
                        p.move(to: CGPoint(x: 0, y: bandY))
                        p.addLine(to: CGPoint(x: w, y: bandY))
                    }
                    .stroke(DS.Colors.teal.opacity(0.35), style: StrokeStyle(lineWidth: 0.5, dash: [4, 3]))

                    // Sparkline
                    Path { p in
                        for (i, val) in values.enumerated() {
                            let x = w * CGFloat(i) / CGFloat(count - 1)
                            let y = yPos(val, height: h)
                            if i == 0 { p.move(to: CGPoint(x: x, y: y)) }
                            else       { p.addLine(to: CGPoint(x: x, y: y)) }
                        }
                    }
                    .stroke(
                        LinearGradient(colors: [DS.Colors.violet.opacity(0.6), DS.Colors.teal],
                                       startPoint: .leading, endPoint: .trailing),
                        style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round)
                    )

                    // Last dot
                    if let last = values.last {
                        let dotX = w - 3
                        let dotY = yPos(last, height: h) - 3
                        Circle()
                            .fill(DS.Colors.teal)
                            .frame(width: 6, height: 6)
                            .offset(x: dotX, y: dotY)
                    }
                }
            }
        }
    }

    private func yPos(_ val: Double, height: CGFloat) -> CGFloat {
        guard range > 0 else { return height / 2 }
        let norm = (val - minVal) / range
        return height * CGFloat(1 - norm)
    }
}

private extension Double {
    func clamped(to range: ClosedRange<Double>) -> Double {
        Swift.min(Swift.max(self, range.lowerBound), range.upperBound)
    }
}
