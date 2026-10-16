import Foundation

/// Numbers in German notation: days ("2,4 Tage") and shares ("71 %").
enum DaysText {
    static func number(_ days: Double) -> String {
        days.formatted(.number.precision(.fractionLength(1)).locale(Locale(identifier: "de_DE")))
    }

    static func of(_ days: Double) -> String { "\(number(days)) Tage" }

    /// A share as "71 %", with a space that does not break.
    static func percent(_ share: Double) -> String { "\(Int((share * 100).rounded()))\u{00A0}%" }
}
