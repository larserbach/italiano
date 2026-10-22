import SwiftUI

/// Ten arc segments showing a verb chip's level (0…10), with the number in the middle.
struct VerbRing: View {
    let level: Int

    private let segments = ProgressStore.maxLevel
    /// Degrees left open between two segments.
    private let gap = 8.0

    var body: some View {
        ZStack {
            ForEach(0..<segments, id: \.self) { index in
                segment(index)
                    .stroke(index < level ? Theme.gold : Theme.line,
                            style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
            }
            Text("\(level)")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(Theme.ink)
        }
        .frame(width: 26, height: 26)
        .accessibilityElement()
        .accessibilityLabel("Level \(level) von \(segments)")
    }

    private func segment(_ index: Int) -> Path {
        let step = 360.0 / Double(segments)
        // −90° puts the first segment at 12 o'clock.
        let start = Double(index) * step + gap / 2 - 90
        let end = Double(index + 1) * step - gap / 2 - 90
        var path = Path()
        path.addArc(center: CGPoint(x: 13, y: 13), radius: 10,
                    startAngle: .degrees(start), endAngle: .degrees(end), clockwise: false)
        return path
    }
}

/// Progress of a group or irregular verb toward performing well: the arc fills with the share of Good
/// answers against the bar and turns green once it has made it. The share stays in the middle, so a
/// drop after that shows too.
struct ProgressRing: View {
    let progress: LearningPool.Progress

    var body: some View {
        ZStack {
            Circle().stroke(Theme.line, lineWidth: 2.5)
            Circle()
                .trim(from: 0, to: progress.fraction)
                .stroke(progress.passed ? Theme.olive : Theme.gold, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Text(progress.share.map { "\(Int(($0 * 100).rounded()))" } ?? "–")
                .font(.system(size: 8.5, weight: .semibold))
                .foregroundStyle(progress.passed ? Theme.olive : Theme.ink)
        }
        .frame(width: 26, height: 26)
        .accessibilityElement()
        .accessibilityLabel((progress.passed ? "geschafft, " : "")
                            + "\(progress.share.map { DaysText.percent($0) } ?? "noch keine Antworten") gut, \(progress.answers) von \(Curriculum.windowSize) Antworten")
    }
}
