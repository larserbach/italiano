import SwiftUI
import UIKit

/// Colors from the prototype, with the same dark-mode variants.
enum Theme {
    static let paper = Color(light: 0xFAF6EC, dark: 0x1C2128)
    static let paperRaised = Color(light: 0xF2EBDA, dark: 0x262C35)
    static let ink = Color(light: 0x22303F, dark: 0xEDE7D9)
    static let inkSoft = Color(light: 0x5C6B78, dark: 0xA8AFB8)
    static let gold = Color(light: 0xB9902E, dark: 0xD4B45E)
    static let goldSoft = Color(light: 0xE4D2A0, dark: 0x4A4126)
    static let olive = Color(light: 0x5B7553, dark: 0x8FB07F)
    static let oliveBackground = Color(light: 0xE4ECDE, dark: 0x2A3527)
    static let brick = Color(light: 0xA6483A, dark: 0xD98A7C)
    static let brickBackground = Color(light: 0xF3DFDA, dark: 0x3D2825)
    static let line = Color(light: 0xDAD0B8, dark: 0x3A3F47)

    static func display(_ size: CGFloat, weight: Font.Weight = .medium) -> Font {
        .system(size: size, weight: weight, design: .serif)
    }
}

extension Color {
    init(light: UInt32, dark: UInt32) {
        self.init(uiColor: UIColor { traits in
            UIColor(rgb: traits.userInterfaceStyle == .dark ? dark : light)
        })
    }
}

private extension UIColor {
    convenience init(rgb: UInt32) {
        self.init(red: CGFloat((rgb >> 16) & 0xFF) / 255,
                  green: CGFloat((rgb >> 8) & 0xFF) / 255,
                  blue: CGFloat(rgb & 0xFF) / 255,
                  alpha: 1)
    }
}

struct PrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 16, weight: .medium))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 15)
            .foregroundStyle(Theme.paper)
            .background(Theme.ink, in: RoundedRectangle(cornerRadius: 10))
            .opacity(isEnabled ? (configuration.isPressed ? 0.85 : 1) : 0.4)
    }
}

struct GhostButtonStyle: ButtonStyle {
    var fullWidth = true

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 15, weight: .medium))
            .frame(maxWidth: fullWidth ? .infinity : nil)
            .padding(.vertical, 13)
            .padding(.horizontal, fullWidth ? 0 : 16)
            .foregroundStyle(Theme.inkSoft)
            .background(RoundedRectangle(cornerRadius: 10).stroke(Theme.line))
            .contentShape(Rectangle())
            .opacity(configuration.isPressed ? 0.6 : 1)
    }
}

struct ChipStyle: ButtonStyle {
    var active: Bool
    var accent: Color? = nil

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 14, weight: active ? .medium : .regular))
            .foregroundStyle(Theme.ink)
            .padding(.vertical, 7)
            .padding(.horizontal, 12)
            .background(active ? Theme.goldSoft : Theme.paperRaised, in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(accent ?? (active ? Theme.gold : Theme.line)))
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}

extension View {
    func card() -> some View {
        padding(20)
            .frame(maxWidth: .infinity)
            .background(Theme.paperRaised, in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.line))
    }

    func screenBackground() -> some View {
        frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background(Theme.paper.ignoresSafeArea())
            .foregroundStyle(Theme.ink)
    }
}

struct ControlLabel: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(.system(size: 12.5))
            .foregroundStyle(Theme.inkSoft)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct ScreenHeader: View {
    let title: String
    let lede: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(Theme.display(34))
            if !lede.isEmpty {
                Text(lede)
                    .font(.system(size: 15))
                    .foregroundStyle(Theme.inkSoft)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
