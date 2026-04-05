//
//  WaveformView.swift
//  D Scribe
//

import SwiftUI

struct WaveformView: View {
    let levels: [Float]
    let color: Color

    var body: some View {
        Canvas { context, size in
            let count = levels.count
            guard count > 0 else { return }
            let barWidth = size.width / CGFloat(count)
            let minHeight: CGFloat = 2

            for (i, level) in levels.enumerated() {
                let height = max(minHeight, CGFloat(level) * size.height)
                let x = CGFloat(i) * barWidth
                let y = (size.height - height) / 2
                let rect = CGRect(x: x, y: y, width: max(barWidth - 1, 1), height: height)
                context.fill(Path(roundedRect: rect, cornerRadius: 1), with: .color(color))
            }
        }
        .frame(width: 100, height: 24)
    }
}
