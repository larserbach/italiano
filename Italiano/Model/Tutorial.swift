import Foundation

/// One-time coach marks. Each case has a "seen" flag in UserDefaults; views read it via
/// `@AppStorage(Tutorial.x.defaultsKey)`, so resetting updates open screens.
enum Tutorial: String, CaseIterable {
    case verbRing

    var defaultsKey: String { "tutorial-seen-\(rawValue)" }

    static func resetAll(_ defaults: UserDefaults = .standard) {
        for tutorial in allCases { defaults.removeObject(forKey: tutorial.defaultsKey) }
    }
}
