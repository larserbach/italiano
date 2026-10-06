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

/// Progress of a group or irregular verb toward performing well: the arc fills with the share of Good
/// answers against the bar, a check mark once it has made it.
struct ProgressRing: View {
    let progress: LearningPool.Progress

    var body: some View {
        ZStack {
            Circle().stroke(Theme.line, lineWidth: 2.5)
            Circle()
                .trim(from: 0, to: progress.fraction)
                .stroke(progress.passed ? Theme.olive : Theme.gold, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                .rotationEffect(.degrees(-90))
            if progress.passed {
                Image(systemName: "checkmark").font(.system(size: 9, weight: .bold)).foregroundStyle(Theme.olive)
            } else {
                Text(progress.share.map { "\(Int(($0 * 100).rounded()))" } ?? "–")
                    .font(.system(size: 8.5, weight: .semibold))
                    .foregroundStyle(Theme.ink)
            }
        }
        .frame(width: 26, height: 26)
        .accessibilityElement()
        .accessibilityLabel(progress.passed ? "geschafft"
                            : "\(progress.share.map { DaysText.percent($0) } ?? "noch keine Antworten") gut, \(progress.answers) von \(Curriculum.windowSize) Antworten")
    }
}
