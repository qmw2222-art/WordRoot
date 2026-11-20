import AVFoundation
import CryptoKit
import Observation

@MainActor
@Observable
final class SpeechPlayer: NSObject, AVAudioPlayerDelegate {
    @ObservationIgnored private let recordings = LessonAudio()
    @ObservationIgnored private var player: AVAudioPlayer?
    @ObservationIgnored private var remaining: ArraySlice<(player: AVAudioPlayer, pauseBefore: TimeInterval)> = []
    @ObservationIgnored private var usesPlaybackSession = false
    private(set) var activeID: String?
    private(set) var speakingID: String?
    private(set) var segmentIndex: Int?
    private(set) var lastCompletedID: String?
    @ObservationIgnored private var recordedIndex = 0
    // Isolated UI tests advance the real player without making sound in the room.
    private static let runVolume: Float = {
        #if DEBUG
        if let run = ProcessInfo.processInfo.environment["WORDROOT_UI_TEST_RUN"],
           UUID(uuidString: run) != nil { return ProcessInfo.processInfo.environment["WORDROOT_TEST_AUDIBLE"] == "1" ? 1 : 0 }
        #endif
        return 1
    }()

    static let auditionID = "settings.voice.audition"

    override init() {
        super.init()
        UserDefaults.standard.removeObject(forKey: "wordroot.englishVoice")
        NotificationCenter.default.addObserver(self, selector: #selector(interrupted(_:)),
                                               name: AVAudioSession.interruptionNotification, object: nil)
    }

    @discardableResult
    func toggle(id: String, text: String, pronunciation: String? = nil) -> Bool {
        if activeID == id { stop(id: id); return true }
        guard let clip = recordings.recording(text, pronunciation: pronunciation) else { return false }
        LessonPlaybackTrace.note("route \(id) \(clip.source)")
        return startRecordings(id: id, data: [clip.bytes])
    }

    @discardableResult
    func toggle(id: String, dialogue: [String]) -> Bool {
        toggleGuide(id: id, lines: dialogue.enumerated().map { index, text in
            .english(text, pauseBefore: index == 0 ? 0 : 0.25)
        })
    }

    @discardableResult
    func toggleGuide(id: String, lines: [GuideSpeech]) -> Bool {
        if activeID == id { stop(id: id); return true }
        guard !lines.isEmpty else { return false }
        var clips: [Data] = []
        for (index, line) in lines.enumerated() {
            let clip: Data?
            switch line {
            case .mandarin(let text): clip = recordings.mandarin(text)
            case let .english(text, ipa, _):
                let english = recordings.recording(text, pronunciation: ipa)
                clip = english?.bytes
                if let english { LessonPlaybackTrace.note("route \(id) \(index) \(english.source)") }
            }
            guard let clip else { return false }
            clips.append(clip)
        }
        return startRecordings(id: id, data: clips, pauses: lines.map(\.pauseBefore))
    }

    func stop(id: String) {
        guard activeID == id else { return }
        player?.stop()
        remaining = []
        player = nil
        clearPlayback()
        releaseSession()
    }

    private func startRecordings(id: String, data: [Data], pauses: [TimeInterval] = []) -> Bool {
        if let activeID { stop(id: activeID) }
        do {
            let players = try data.map { try AVAudioPlayer(data: $0, fileTypeHint: AVFileType.mp3.rawValue) }
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .spokenAudio, options: [.mixWithOthers])
            try session.setActive(true)
            usesPlaybackSession = true
            remaining = players.enumerated().map { index, player in
                (player, pauses.isEmpty ? 0 : pauses[index])
            }[...]
            lastCompletedID = nil
            activeID = id
            recordedIndex = 0
            return playNext()
        } catch {
            releaseSession()
            return false
        }
    }

    private func playNext() -> Bool {
        guard let next = remaining.popFirst() else {
            player = nil
            clearPlayback()
            releaseSession()
            return true
        }
        player = next.player
        next.player.volume = Self.runVolume
        if recordedIndex == 0, let id = activeID {
            LessonPlaybackTrace.note("output-gain \(id) \(next.player.volume)")
        }
        next.player.delegate = self
        let started = next.pauseBefore > 0
            ? next.player.play(atTime: next.player.deviceCurrentTime + next.pauseBefore)
            : next.player.play()
        guard started else {
            if let activeID { stop(id: activeID) }
            return false
        }
        #if DEBUG
        if LessonPlaybackTrace.isEnabled, let id = activeID, let bytes = next.player.data {
            let digest = SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
            LessonPlaybackTrace.note("played \(id) \(recordedIndex) \(digest)")
        }
        #endif
        segmentIndex = recordedIndex
        if let id = activeID { LessonPlaybackTrace.note("start \(id) \(recordedIndex)") }
        recordedIndex += 1
        speakingID = activeID
        return true
    }

    private func releaseSession() {
        guard usesPlaybackSession else { return }
        usesPlaybackSession = false
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    @objc nonisolated private func interrupted(_ notification: Notification) {
        guard notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt ==
                AVAudioSession.InterruptionType.began.rawValue else { return }
        Task { @MainActor [weak self] in
            if let self, let activeID { stop(id: activeID) }
        }
    }

    nonisolated func audioPlayerDidFinishPlaying(_ finished: AVAudioPlayer, successfully flag: Bool) {
        let identity = ObjectIdentifier(finished)
        Task { @MainActor [weak self] in
            guard let self, let player, ObjectIdentifier(player) == identity, let activeID else { return }
            if flag {
                if self.remaining.isEmpty { self.lastCompletedID = activeID }
                if let segmentIndex { LessonPlaybackTrace.note("finish \(activeID) \(segmentIndex)") }
                _ = playNext()
            } else { stop(id: activeID) }
        }
    }

    nonisolated func audioPlayerDecodeErrorDidOccur(_ failed: AVAudioPlayer, error: Error?) {
        let identity = ObjectIdentifier(failed)
        Task { @MainActor [weak self] in
            guard let self, let player, ObjectIdentifier(player) == identity, let activeID else { return }
            stop(id: activeID)
        }
    }

    private func clearPlayback() {
        activeID = nil
        speakingID = nil
        segmentIndex = nil
    }
}
