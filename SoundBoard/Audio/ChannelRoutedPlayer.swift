#if os(macOS)
import AVFoundation
import AudioToolbox
import CoreAudio
import OSLog

enum ChannelRoutingError: Error {
    case noAudioUnit
    case invalidChannelOffset(offset: Int, deviceChannelCount: Int)
    case coreAudio(OSStatus, context: String)
}

/// Plays a single sound file through a specific output device, landing its stereo
/// signal on a specific channel pair of that device (e.g. channels 3/4 of an 8-channel
/// interface) rather than the device's default first pair.
///
/// Each instance owns its own `AVAudioEngine` bound to one hardware device via AUHAL's
/// `kAudioOutputUnitProperty_CurrentDevice`; the channel placement is done with
/// `kAudioOutputUnitProperty_ChannelMap`, which lets the HAL unit scatter our 2-channel
/// stream into an otherwise-silent N-channel hardware frame without the engine itself
/// having to render all N channels.
final class ChannelRoutedPlayer: @unchecked Sendable {
    private static let logger = Logger(subsystem: "SoundBoard", category: "Audio")

    let device: AudioOutputDevice
    let channelOffset: Int

    private let engine = AVAudioEngine()
    private let playerNode = AVAudioPlayerNode()
    private var file: AVAudioFile?

    private(set) var duration: TimeInterval = 0
    private var targetVolume: Float = 1.0
    /// Serializes every player-node mutation. In particular, `stop()` must not run
    /// synchronously on the user-interactive UI thread because AVFAudio may wait for
    /// its lower-priority render thread while clearing scheduled events.
    private let controlQueue = DispatchQueue(label: "SoundBoard.ChannelRoutedPlayer.control", qos: .default)
    private var fadeTimer: DispatchSourceTimer?
    private var fadeOutTriggerTimer: DispatchSourceTimer?
    private var isLooping = false
    private var onFinishedPlaying: (@Sendable () -> Void)?

    /// - Parameters:
    ///   - device: target output device, as returned by `AudioDeviceManager`.
    ///   - channelOffset: 0-based index of the first of the two consecutive device
    ///     channels the stereo signal should be routed to (e.g. `2` for channels 3/4).
    init(device: AudioOutputDevice, channelOffset: Int) throws {
        self.device = device
        self.channelOffset = channelOffset

        guard channelOffset >= 0, channelOffset + 1 < device.outputChannelCount else {
            throw ChannelRoutingError.invalidChannelOffset(offset: channelOffset, deviceChannelCount: device.outputChannelCount)
        }

        engine.attach(playerNode)
        engine.connect(playerNode, to: engine.mainMixerNode, format: nil)

        try bindToDevice()
        try applyChannelMap()
    }

    /// Builds a player from a button's saved config, resolving its stored device UID
    /// back to a currently-connected device (falling back to the system default).
    convenience init(config: SoundButtonConfig) throws {
        let resolvedDevice: AudioOutputDevice
        if let uid = config.outputDeviceUID, let match = AudioDeviceManager.device(withUID: uid) {
            resolvedDevice = match
        } else if let defaultDevice = AudioDeviceManager.defaultOutputDevice() {
            resolvedDevice = defaultDevice
        } else {
            throw ChannelRoutingError.noAudioUnit
        }

        try self.init(device: resolvedDevice, channelOffset: config.outputChannelOffset)
        try load(url: URL(fileURLWithPath: config.soundFilePath))
        setVolume(config.volume)
    }

    func load(url: URL) throws {
        let audioFile = try AVAudioFile(forReading: url)
        file = audioFile
        duration = audioFile.processingFormat.sampleRate > 0
            ? Double(audioFile.length) / audioFile.processingFormat.sampleRate
            : 0
    }

    var isPlaying: Bool { playerNode.isPlaying }

    /// Elapsed playback time of the current scheduled segment, in seconds.
    var elapsedTime: TimeInterval {
        guard let nodeTime = playerNode.lastRenderTime, nodeTime.isSampleTimeValid,
              let playerTime = playerNode.playerTime(forNodeTime: nodeTime) else { return 0 }
        return Double(playerTime.sampleTime) / playerTime.sampleRate
    }

    func setVolume(_ volume: Float) {
        controlQueue.async { [weak self] in
            guard let self else { return }
            self.targetVolume = volume
            if self.fadeTimer == nil {
                self.playerNode.volume = volume
            }
        }
    }

    /// Starts playback. If `loop` is set, the file is automatically rescheduled every
    /// time it finishes. `onFinished` fires once when playback ends on its own
    /// (naturally, without looping) — not when stopped manually.
    ///
    /// When `fadeOutDuration > 0` and `loop` is false, the volume ramp to 0 is timed
    /// to finish exactly as the file's natural end is reached (based on `duration`),
    /// so non-looping playback fades out instead of cutting off abruptly — mirroring
    /// what `requestStop(fadeOutDuration:)` already does for a manual stop.
    func play(loop: Bool = false, fadeInDuration: TimeInterval = 0, fadeOutDuration: TimeInterval = 0, onFinished: (@Sendable () -> Void)? = nil) throws {
        guard let file else { return }
        if !engine.isRunning {
            try startEngineWithRetry()
        }

        controlQueue.async { [weak self] in
            guard let self else { return }
            self.isLooping = loop
            self.onFinishedPlaying = onFinished
            self.scheduleAndPlay(file: file)

            if fadeInDuration > 0 {
                self.ramp(from: 0, to: self.targetVolume, over: fadeInDuration)
            } else {
                self.cancelFadeTimer()
                self.playerNode.volume = self.targetVolume
            }

            self.scheduleFadeOutTrigger(loop: loop, fadeInDuration: fadeInDuration, fadeOutDuration: fadeOutDuration)
        }
    }

    /// Starting a freshly device-bound engine can occasionally race with CoreAudio
    /// reconfiguring its HAL I/O graph — especially while another `ChannelRoutedPlayer`
    /// is already actively rendering to a different device — and throw a transient
    /// error on the first attempt. A couple of short retries clear this up silently;
    /// without them, a button could fail to produce any output with no visible cause.
    private func startEngineWithRetry() throws {
        var lastError: Error?
        for attempt in 1...3 {
            do {
                try engine.start()
                return
            } catch {
                lastError = error
                Self.logger.error("engine.start() failed for \(self.device.name, privacy: .public) (attempt \(attempt)/3): \(String(describing: error), privacy: .public)")
                if attempt < 3 {
                    Thread.sleep(forTimeInterval: 0.03)
                }
            }
        }
        throw lastError!
    }

    /// Arms a one-shot timer that starts the fade-to-zero ramp `fadeOutDuration`
    /// seconds before the file's natural end, so it reaches 0 right as playback
    /// would otherwise stop dead. No-op while looping, since there is no natural end.
    private func scheduleFadeOutTrigger(loop: Bool, fadeInDuration: TimeInterval, fadeOutDuration: TimeInterval) {
        cancelFadeOutTriggerTimer()
        guard !loop, fadeOutDuration > 0, duration > 0 else { return }

        let delay = max(fadeInDuration, duration - fadeOutDuration, 0)
        let timer = DispatchSource.makeTimerSource(queue: controlQueue)
        timer.schedule(deadline: .now() + delay)
        timer.setEventHandler { [weak self] in
            guard let self else { return }
            self.fadeOutTriggerTimer = nil
            self.ramp(from: self.playerNode.volume, to: 0, over: fadeOutDuration)
        }
        fadeOutTriggerTimer = timer
        timer.resume()
    }

    /// Stops playback, ramping the volume down first if `fadeOutDuration > 0`.
    func requestStop(fadeOutDuration: TimeInterval = 0, completion: (@Sendable () -> Void)? = nil) {
        controlQueue.async { [weak self] in
            guard let self else { return }
            self.isLooping = false
            self.cancelFadeOutTriggerTimer()
            guard fadeOutDuration > 0 else {
                self.stopImmediatelyOnQueue()
                completion?()
                return
            }
            self.ramp(from: self.playerNode.volume, to: 0, over: fadeOutDuration) { [weak self] in
                self?.stopImmediatelyOnQueue()
                completion?()
            }
        }
    }

    /// Immediate, unconditional stop — used for the global Not-Stop control.
    func stopImmediately() {
        // Capture strongly so the engine and node are released only after the
        // queued stop has completed, on this default-QoS audio-control queue.
        controlQueue.async { [self] in
            stopImmediatelyOnQueue()
        }
    }

    private func stopImmediatelyOnQueue() {
        isLooping = false
        cancelFadeTimer()
        cancelFadeOutTriggerTimer()
        playerNode.stop()
    }

    // MARK: - Looping

    /// `onFinished` (and, for looping, the reschedule itself) run synchronously on
    /// whatever background audio-callback thread AVAudioPlayerNode invokes the
    /// completion handler on — hop to main yourself in the closure if you touch
    /// UI-facing state. Rescheduling directly here (instead of after a main-thread
    /// round trip) keeps looped playback gap-free.
    private func scheduleAndPlay(file: AVAudioFile) {
        playerNode.scheduleFile(file, at: nil, completionCallbackType: .dataPlayedBack) { [weak self] _ in
            guard let self else { return }
            self.controlQueue.async { [weak self] in
                guard let self else { return }
                if self.isLooping {
                    self.scheduleAndPlay(file: file)
                } else {
                    let completion = self.onFinishedPlaying
                    self.onFinishedPlaying = nil
                    completion?()
                }
            }
        }
        if !playerNode.isPlaying {
            playerNode.play()
        }
    }

    // MARK: - Volume ramping (fade in/out)

    private func ramp(from: Float, to: Float, over duration: TimeInterval, completion: (@Sendable () -> Void)? = nil) {
        cancelFadeTimer()
        playerNode.volume = from

        guard duration > 0 else {
            playerNode.volume = to
            completion?()
            return
        }

        let steps = max(Int(duration * 30), 1)
        let stepDuration = duration / Double(steps)
        var currentStep = 0

        let timer = DispatchSource.makeTimerSource(queue: controlQueue)
        timer.schedule(deadline: .now() + stepDuration, repeating: stepDuration)
        timer.setEventHandler { [weak self] in
            guard let self else { return }
            currentStep += 1
            let progress = Float(currentStep) / Float(steps)
            self.playerNode.volume = from + (to - from) * progress
            if currentStep >= steps {
                self.cancelFadeTimer()
                completion?()
            }
        }
        fadeTimer = timer
        timer.resume()
    }

    private func cancelFadeTimer() {
        fadeTimer?.setEventHandler {}
        fadeTimer?.cancel()
        fadeTimer = nil
    }

    private func cancelFadeOutTriggerTimer() {
        fadeOutTriggerTimer?.setEventHandler {}
        fadeOutTriggerTimer?.cancel()
        fadeOutTriggerTimer = nil
    }

    // MARK: - AUHAL configuration

    private func bindToDevice() throws {
        guard let audioUnit = engine.outputNode.audioUnit else {
            throw ChannelRoutingError.noAudioUnit
        }
        var deviceID = device.id
        let status = AudioUnitSetProperty(
            audioUnit,
            kAudioOutputUnitProperty_CurrentDevice,
            kAudioUnitScope_Global,
            0,
            &deviceID,
            UInt32(MemoryLayout<AudioDeviceID>.size))
        guard status == noErr else {
            throw ChannelRoutingError.coreAudio(status, context: "CurrentDevice")
        }
    }

    private func applyChannelMap() throws {
        guard let audioUnit = engine.outputNode.audioUnit else {
            throw ChannelRoutingError.noAudioUnit
        }

        var channelMap = [Int32](repeating: -1, count: device.outputChannelCount)
        channelMap[channelOffset] = 0
        channelMap[channelOffset + 1] = 1

        let status = channelMap.withUnsafeMutableBufferPointer { buffer -> OSStatus in
            AudioUnitSetProperty(
                audioUnit,
                kAudioOutputUnitProperty_ChannelMap,
                kAudioUnitScope_Output,
                0,
                buffer.baseAddress,
                UInt32(buffer.count * MemoryLayout<Int32>.size))
        }
        guard status == noErr else {
            throw ChannelRoutingError.coreAudio(status, context: "ChannelMap")
        }
    }
}
#endif
