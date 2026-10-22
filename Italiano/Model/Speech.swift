import AVFoundation
import SwiftUI

/// Reads Italian text aloud. Any screen can get one from the environment (`\.speech`); tests use a fake.
protocol Speaking: AnyObject {
    /// Calls `completion` on the main queue once the text is spoken, speaking was stopped, or speech is off.
    func speak(_ text: String, completion: @escaping () -> Void)
    func stop()
    /// Gets the audio ready ahead of the first answer, so its start isn't cut off.
    func warmUp()
}

extension Speaking {
    func warmUp() {}

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
///
/// The synthesizer only renders the audio (`write`); an audio engine plays it. The synthesizer's own
/// playback starts every utterance with an empty buffer and then underflows its AudioQueue ~80 ms later,
/// which is heard as a choppy start on a phone.
final class SystemSpeech: NSObject, Speaking, AVSpeechSynthesizerDelegate {
    /// Checked on every call, so the setting applies everywhere at once.
    private let isEnabled: () -> Bool
    private lazy var synthesizer: AVSpeechSynthesizer = {
        let synthesizer = AVSpeechSynthesizer()
        synthesizer.delegate = self
        return synthesizer
    }()
    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private var connectedFormat: AVAudioFormat?
    private var sessionReady = false
    /// Looking the voice up lists every installed voice, which is slow on a phone. Done when a lesson
    /// starts (`warmUp`) instead of on every answer, so a voice downloaded in between is still picked up.
    private var voice: AVSpeechSynthesisVoice?

    /// One spoken text, from the first rendered buffer until the last one has been played.
    private final class Playback {
        let utterance: AVSpeechUtterance
        let completion: () -> Void
        var scheduled = 0
        var played = 0
        /// The synthesizer has delivered everything it will deliver.
        var rendered = false
        var finished = false

        init(utterance: AVSpeechUtterance, completion: @escaping () -> Void) {
            self.utterance = utterance
            self.completion = completion
        }
    }
    /// All access is on the main queue.
    private var current: Playback?

    init(isEnabled: @escaping () -> Bool = { true }) {
        self.isEnabled = isEnabled
        super.init()
    }

    func speak(_ text: String, completion: @escaping () -> Void) {
        guard isEnabled() else {
            DispatchQueue.main.async(execute: completion)
            return
        }
        // A new text replaces whatever is still being read.
        stop()
        prepareAudio()
        if voice == nil { voice = Self.bestItalianVoice() }
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = voice
        // A little slower than normal, so each syllable can be heard.
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate * 0.9
        let playback = Playback(utterance: utterance, completion: completion)
        current = playback
        synthesizer.write(utterance) { [weak self] buffer in
            // Called on a background queue; the main queue keeps the buffers in order.
            DispatchQueue.main.async { self?.receive(buffer, for: playback) }
        }
    }

    /// Looks the voice up and starts the audio engine before the first answer, so neither is paid for
    /// while an answer is being read.
    func warmUp() {
        guard isEnabled() else { return }
        voice = Self.bestItalianVoice()
        prepareAudio()
    }

    func stop() {
        // Every new card stops speech; with nothing playing this keeps the synthesizer from being created.
        guard let playback = current else { return }
        current = nil
        synthesizer.stopSpeaking(at: .immediate)
        player.stop()
        finish(playback)
    }

    // MARK: - Playing the rendered audio

    private func receive(_ buffer: AVAudioBuffer, for playback: Playback) {
        // Late buffers of an utterance that was stopped or replaced.
        guard current === playback, let pcm = buffer as? AVAudioPCMBuffer else { return }
        guard pcm.frameLength > 0 else {
            // The synthesizer ends an utterance with an empty buffer.
            playback.rendered = true
            finishIfPlayed(playback)
            return
        }
        connect(format: pcm.format)
        playback.scheduled += 1
        player.scheduleBuffer(pcm, completionCallbackType: .dataPlayedBack) { [weak self] _ in
            DispatchQueue.main.async {
                playback.played += 1
                self?.finishIfPlayed(playback)
            }
        }
        if !player.isPlaying { player.play() }
    }

    private func finishIfPlayed(_ playback: Playback) {
        guard playback.rendered, playback.played == playback.scheduled, current === playback else { return }
        current = nil
        finish(playback)
    }

    /// The completion goes out on the main queue, after whatever called `stop` is done.
    private func finish(_ playback: Playback) {
        guard !playback.finished else { return }
        playback.finished = true
        DispatchQueue.main.async(execute: playback.completion)
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        DispatchQueue.main.async { [weak self] in
            guard let playback = self?.current, playback.utterance === utterance else { return }
            playback.rendered = true
            self?.finishIfPlayed(playback)
        }
    }

    // MARK: - Audio setup

    /// Playback: heard in silent mode too, since the setting is the way to switch it off. Mixed with music
    /// instead of stopping it. Also keeps the engine running; it stops after an interruption or route change.
    private func prepareAudio() {
        if !sessionReady {
            try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio, options: .mixWithOthers)
            engine.attach(player)
            sessionReady = true
        }
        if connectedFormat == nil, let format = AVAudioFormat(standardFormatWithSampleRate: 22_050, channels: 1) {
            connect(format: format)
        }
        if !engine.isRunning {
            engine.prepare()
            try? engine.start()
        }
    }

    /// The voice decides the format of its buffers; the player is connected to match.
    private func connect(format: AVAudioFormat) {
        guard connectedFormat != format else { return }
        player.stop()
        engine.connect(player, to: engine.mainMixerNode, format: format)
        connectedFormat = format
        if !engine.isRunning {
            engine.prepare()
            try? engine.start()
        }
    }

    private static func bestItalianVoice() -> AVSpeechSynthesisVoice? {
        let voices = AVSpeechSynthesisVoice.speechVoices().filter {
            $0.language == "it-IT"
                && !$0.voiceTraits.contains(.isNoveltyVoice)
                && !$0.voiceTraits.contains(.isPersonalVoice)
        }
        return voices.max { $0.quality.rawValue < $1.quality.rawValue } ?? AVSpeechSynthesisVoice(language: "it-IT")
    }
}
