import AVFoundation

/// Reads an Italian form aloud. Tests replace it with a silent fake.
protocol AnswerSpeaking: AnyObject {
    /// Calls `completion` on the main queue once the text is spoken or speaking was stopped.
    func speak(_ text: String, completion: @escaping () -> Void)
    func stop()
}

/// The system's on-device speech with the best Italian voice installed. Enhanced and premium voices can be
/// downloaded under Settings › Accessibility › Spoken Content › Voices › Italian.
final class AnswerSpeaker: NSObject, AnswerSpeaking, AVSpeechSynthesizerDelegate {
    static let shared = AnswerSpeaker()

    private let synthesizer = AVSpeechSynthesizer()
    private var completions: [ObjectIdentifier: () -> Void] = [:]
    private var sessionReady = false

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    func speak(_ text: String, completion: @escaping () -> Void) {
        prepareSession()
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = Self.bestItalianVoice()
        // A little slower than normal, so each syllable can be heard.
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate * 0.9
        completions[ObjectIdentifier(utterance)] = completion
        synthesizer.speak(utterance)
    }

    func stop() {
        synthesizer.stopSpeaking(at: .immediate)
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        finish(utterance)
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        finish(utterance)
    }

    private func finish(_ utterance: AVSpeechUtterance) {
        let id = ObjectIdentifier(utterance)
        DispatchQueue.main.async { [weak self] in
            self?.completions.removeValue(forKey: id)?()
        }
    }

    /// Ambient: silent when the ring switch is off, and mixed with music instead of stopping it.
    private func prepareSession() {
        guard !sessionReady else { return }
        try? AVAudioSession.sharedInstance().setCategory(.ambient, mode: .spokenAudio)
        sessionReady = true
    }

    /// Looked up each time, so a voice downloaded while the app runs is used right away.
    private static func bestItalianVoice() -> AVSpeechSynthesisVoice? {
        let voices = AVSpeechSynthesisVoice.speechVoices().filter {
            $0.language == "it-IT"
                && !$0.voiceTraits.contains(.isNoveltyVoice)
                && !$0.voiceTraits.contains(.isPersonalVoice)
        }
        return voices.max { $0.quality.rawValue < $1.quality.rawValue } ?? AVSpeechSynthesisVoice(language: "it-IT")
    }
}
