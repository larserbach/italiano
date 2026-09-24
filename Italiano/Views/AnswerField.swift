import SwiftUI
import UIKit

/// A text field that keeps the keyboard open when Return is pressed, so the
/// learner can type answer after answer without the keyboard bouncing.
struct AnswerField: UIViewRepresentable {
    @Binding var text: String
    var isEditable: Bool
    /// Change this value to (re)focus the field, e.g. after a sheet was dismissed.
    var focusToken: Int
    var onSubmit: () -> Void

    func makeUIView(context: Context) -> UITextField {
        let field = UITextField()
        field.delegate = context.coordinator
        field.font = .systemFont(ofSize: 18)
        field.textAlignment = .center
        field.placeholder = "deine Antwort"
        field.autocapitalizationType = .none
        field.autocorrectionType = .no
        field.spellCheckingType = .no
        field.smartQuotesType = .no
        field.smartDashesType = .no
        field.returnKeyType = .go
        field.enablesReturnKeyAutomatically = false
        field.setContentHuggingPriority(.defaultLow, for: .horizontal)
        field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        field.addTarget(context.coordinator, action: #selector(Coordinator.changed(_:)), for: .editingChanged)
        return field
    }

    func updateUIView(_ field: UITextField, context: Context) {
        context.coordinator.parent = self
        if field.text != text { field.text = text }
        field.textColor = UIColor(Theme.ink)
        if context.coordinator.focusedToken != focusToken {
            context.coordinator.focusedToken = focusToken
            DispatchQueue.main.async { field.becomeFirstResponder() }
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    final class Coordinator: NSObject, UITextFieldDelegate {
        var parent: AnswerField
        var focusedToken: Int?

        init(parent: AnswerField) { self.parent = parent }

        @objc func changed(_ field: UITextField) {
            parent.text = field.text ?? ""
        }

        func textField(_ textField: UITextField, shouldChangeCharactersIn range: NSRange, replacementString string: String) -> Bool {
            parent.isEditable
        }

        func textFieldShouldReturn(_ textField: UITextField) -> Bool {
            parent.onSubmit()
            return false
        }
    }
}
