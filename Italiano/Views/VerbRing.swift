import SwiftUI

/// Ten arc segments showing a verb's mastery level, with the level number in the middle.
struct VerbRing: View {
    let level: Int
    var mistake = false

    private let segments = ProgressStore.maxLevel
    private let gap = 8.0

    var body: some View {
        ZStack {
            ForEach(0..<segments, id: \.self) { index in
                segment(index)
                    .stroke(index < level ? (mistake ? Theme.brick : Theme.gold) : Theme.line,
                            style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
            }
            Text("\(level)")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(mistake ? Theme.brick : Theme.ink)
        }
        .frame(width: 26, height: 26)
        .accessibilityElement()
        .accessibilityLabel("Level \(level) von \(segments)")
    }

    private func segment(_ index: Int) -> Path {
        let step = 360.0 / Double(segments)
        let start = Double(index) * step + gap / 2 - 90
        let end = Double(index + 1) * step - gap / 2 - 90
        var path = Path()
        path.addArc(center: CGPoint(x: 13, y: 13), radius: 10,
                    startAngle: .degrees(start), endAngle: .degrees(end), clockwise: false)
        return path
    }
}
