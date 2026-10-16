import AVFoundation
import SwiftUI

/// Reads Italian text aloud. Any screen can get one from the environment (`\.speech`); tests use a fake.
protocol Speaking: AnyObject {
    /// Calls `completion` on the main queue once the text is spoken, speaking was stopped, or speech is off.
    func speak(_ text: String, completion: @escaping () -> Void)
    func stop()
}

extension Speaking {
    func speak(_ text: String) { speak(text) {} }

    /// Calls `completion` on the main queue once the text is spoken and at least `minimum` seconds have
    /// passed, so a right answer stays on screen for a moment even with speech off.
    func speak(_ text: String, atLeast minimum: TimeInterval, completion: @escaping () -> Void) {
        let wait = DispatchGroup()
        wait.enter()
        DispatchQueue.main.asyncAfter(deadline: .now() + minimum) { wait.leave() }
        wait.enter()
        speak(text) { wait.leave() }
        wait.notify(queue: .main, execute: completion)
    }
}

/// Says nothing; the default when no speech was set up.
final class SilentSpeech: Speaking {
    func speak(_ text: String, completion: @escaping () -> Void) { completion() }
    func stop() {}
}

extension EnvironmentValues {
    @Entry var speech: any Speaking = SilentSpeech()
}

/// The system's on-device speech with the best Italian voice installed. Enhanced and premium voices can be
/// downloaded under Settings › Accessibility › Spoken Content › Voices › Italian.
final class SystemSpeech: NSObject, Speaking, AVSpeechSynthesizerDelegate {
    /// Checked on every call, so the setting applies everywhere at once.
    private let isEnabled: () -> Bool
    private lazy var synthesizer: AVSpeechSynthesizer = {
        let synthesizer = AVSpeechSynthesizer()
        synthesizer.delegate = self
        return synthesizer
    }()
    /// One per utterance not finished yet, keyed by the utterance.
    private var completions: [ObjectIdentifier: () -> Void] = [:]
    private var sessionReady = false

    init(isEnabled: @escaping () -> Bool = { true }) {
        self.isEnabled = isEnabled
        super.init()
    }

    func speak(_ text: String, completion: @escaping () -> Void) {
        guard isEnabled() else {
            DispatchQueue.main.async(execute: completion)
            return
        }
        prepareSession()
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = Self.bestItalianVoice()
        // A little slower than normal, so each syllable can be heard.
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate * 0.9
        completions[ObjectIdentifier(utterance)] = completion
        synthesizer.speak(utterance)
    }

    func stop() {
        // Every new card stops speech; with nothing pending this keeps the synthesizer from being created.
        guard !completions.isEmpty else { return }
        synthesizer.stopSpeaking(at: .immediate)
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        finish(utterance)
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        finish(utterance)
    }

    /// The delegate may be called off the main queue; `Speaking` promises completions on it.
    private func finish(_ utterance: AVSpeechUtterance) {
        let id = ObjectIdentifier(utterance)
        DispatchQueue.main.async { [weak self] in
            self?.completions.removeValue(forKey: id)?()
        }
    }

    /// Playback: heard in silent mode too, since the setting is the way to switch it off. Mixed with music
    /// instead of stopping it.
    private func prepareSession() {
        guard !sessionReady else { return }
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio, options: .mixWithOthers)
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
