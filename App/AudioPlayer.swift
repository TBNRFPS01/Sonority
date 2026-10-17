import SwiftUI
import AVFoundation
import MediaPlayer
import SonorityCore

private final class LevelMeter: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Float = 0
    func set(_ newValue: Float) { lock.lock(); value = newValue; lock.unlock() }
    func get() -> Float { lock.lock(); defer { lock.unlock() }; return value }
}

@MainActor
final class AudioPlayer: ObservableObject {
    @Published private(set) var current: Track?
    @Published private(set) var isPlaying = false
    @Published private(set) var position = 0.0
    @Published private(set) var duration = 0.0
    @Published private(set) var queue = PlaybackQueue()
    @Published private(set) var level: Float = 0
    @Published var error: String?
    @Published private(set) var routeName = "iPad"
    @Published private(set) var routeType = "Built-in output"
    @Published private(set) var sampleRate = 0.0
    @Published private(set) var outputChannels = 0
    @Published private(set) var outputLatency = 0.0
    @Published private(set) var spatialAudioReported = false
    @Published var profile = SoundProfile(name: "Reference") { didSet { applyEQ() } }
    private let engine = AVAudioEngine()
    private let node = AVAudioPlayerNode()
    private let eq = AVAudioUnitEQ(numberOfBands: 6)
    private let meter = LevelMeter()
    private var file: AVAudioFile?
    private var offset = 0.0
    private var generation = UUID()
    private var timer: Timer?
    private var observers: [NSObjectProtocol] = []
    private var remoteTargets: [(MPRemoteCommand, Any)] = []
    private var listenedSince: Date?
    private var resumeAfterInterruption = false
    private var lastSessionWrite = Date.distantPast
    private let store: LibraryStore

    init(store: LibraryStore) {
        self.store = store
        engine.attach(node); engine.attach(eq)
        engine.connect(node, to: eq, format: nil)
        engine.connect(eq, to: engine.mainMixerNode, format: nil)
        applyEQ(persist: false)
        let meter = self.meter
        engine.mainMixerNode.installTap(onBus: 0, bufferSize: 1024, format: nil) { buffer, _ in
            guard let channels = buffer.floatChannelData, buffer.frameLength > 0 else { return }
            var sum: Float = 0
            for frame in 0..<Int(buffer.frameLength) { let v = channels[0][frame]; sum += v * v }
            meter.set(min(1, sqrt(sum / Float(buffer.frameLength)) * 5))
        }
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: AVAudioSession.routeChangeNotification, object: nil, queue: .main) { [weak self] note in
            let reason = (note.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt) ?? 0
            Task { @MainActor in
                self?.refreshRoute()
                if reason == AVAudioSession.RouteChangeReason.oldDeviceUnavailable.rawValue { self?.pause() }
            }
        })
        observers.append(center.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) { [weak self] note in
            let type = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt
            let options = note.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0
            Task { @MainActor in self?.interrupted(type: type, options: options) }
        })
        observers.append(center.addObserver(forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.file != nil else { return }
                let resume = self.isPlaying
                self.pause(); self.schedule(at: self.position, play: resume)
            }
        })
        observers.append(center.addObserver(forName: AVAudioSession.mediaServicesWereResetNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.pause(); self?.error = "Audio services restarted. Please reopen Sonority to rebuild the audio engine." }
        })
        observers.append(center.addObserver(forName: AVAudioSession.spatialPlaybackCapabilitiesChangedNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.refreshRoute() }
        })
        configureRemote(); refreshRoute()
    }
    func play(_ track: Track, in tracks: [Track]? = nil) {
        flushListen(); generation = UUID(); node.stop(); isPlaying = false
        if let tracks { queue.replace(tracks.map(\.id), startingAt: track.id) }
        else if queue.current != track.id { queue.replace([track.id], startingAt: track.id) }
        do {
            file = try AVAudioFile(forReading: store.disk.audio(track))
            engine.stop()
            engine.disconnectNodeOutput(node)
            engine.disconnectNodeOutput(eq)
            engine.connect(node, to: eq, format: file!.processingFormat)
            engine.connect(eq, to: engine.mainMixerNode, format: file!.processingFormat)
            current = track; duration = Double(file!.length) / file!.processingFormat.sampleRate
            offset = 0; position = 0
            schedule(at: 0, play: true)
        } catch {
            file = nil; current = track; position = 0; duration = 0
            self.error = "This file is missing or cannot be decoded. Import it again from Files. \(error.localizedDescription)"
            updateNowPlaying()
        }
    }
    private func activate() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playback, mode: .default, policy: .longFormAudio)
        try session.setActive(true)
        if !engine.isRunning { try engine.start() }
        refreshRoute()
    }
    private func schedule(at seconds: Double, play: Bool) {
        guard let file else { return }
        flushListen(); generation = UUID(); node.stop()
        let rate = file.processingFormat.sampleRate
        let start = min(max(0, AVAudioFramePosition(seconds * rate)), file.length)
        offset = Double(start) / rate; position = offset
        let remaining = file.length - start
        guard remaining > 0 else { isPlaying = false; updateNowPlaying(); saveSession(); return }
        let token = generation
        let frameCount = AVAudioFrameCount(min(remaining, Int64(UInt32.max)))
        let segmentEnd = Double(start + Int64(frameCount)) / rate
        node.scheduleSegment(file, startingFrame: start, frameCount: frameCount, at: nil, completionCallbackType: .dataPlayedBack) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.generation == token else { return }
                self.flushListen(); self.isPlaying = false
                if segmentEnd + 0.001 < self.duration { self.schedule(at: segmentEnd, play: true); return }
                self.position = self.duration
                self.next(automatic: true)
            }
        }
        isPlaying = false
        if play {
            do { try activate(); node.play(); isPlaying = true; listenedSince = Date() }
            catch { self.error = "Audio output could not start: \(error.localizedDescription)" }
        }
        updateNowPlaying()
        saveSession()
    }
    func resume() {
        guard file != nil, !isPlaying else { return }
        if position >= duration { schedule(at: 0, play: true); return }
        do { try activate(); node.play(); isPlaying = true; listenedSince = Date(); updateNowPlaying() }
        catch { self.error = error.localizedDescription }
    }
    func pause() { tickPosition(); node.pause(); flushListen(); isPlaying = false; updateNowPlaying(); saveSession() }
    func toggle() { if isPlaying { pause() } else { resume() } }
    func seek(_ seconds: Double) { guard seconds.isFinite else { return }; schedule(at: min(max(0, seconds), duration), play: isPlaying) }
    func next(automatic: Bool = false) {
        for attempt in 0..<max(1, queue.ids.count) {
            guard let id = queue.next(automatic: automatic && attempt == 0) else { break }
            if let track = store.track(id) { play(track); return }
        }
        pause(); updateNowPlaying()
    }
    func previous() {
        if position > 3 { seek(0) }
        else if let id = queue.previous(), let track = store.track(id) { play(track) }
    }
    func enqueue(_ id: UUID) { queue.append(id); saveSession() }
    func playQueue(at index: Int) {
        if let id = queue.select(at: index), let track = store.track(id) { play(track) }
    }
    func removeQueue(_ index: Int) {
        let wasCurrent = index == queue.index
        queue.remove(at: index)
        if wasCurrent {
            if let track = store.track(queue.current) { play(track) }
            else { stop() }
        }
        saveSession()
    }
    func moveQueue(from: Int, to: Int) { queue.move(from: from, to: to); saveSession() }
    func shuffle() { queue.shuffleUpcoming(); saveSession() }
    func cycleRepeat() {
        switch queue.repeatMode { case .off: queue.repeatMode = .all; case .all: queue.repeatMode = .one; case .one: queue.repeatMode = .off }
        saveSession()
    }
    func stop() { pause(); generation = UUID(); node.stop(); file = nil; current = nil; duration = 0; position = 0; MPNowPlayingInfoCenter.default().nowPlayingInfo = nil; saveSession() }
    private func tickPosition() {
        if let render = node.lastRenderTime, let time = node.playerTime(forNodeTime: render), time.sampleRate > 0 {
            position = min(duration, max(0, offset + Double(time.sampleTime) / time.sampleRate))
        }
    }
    private func tick() {
        guard isPlaying else { level = 0; return }
        tickPosition(); level = meter.get()
        if let since = listenedSince, Date().timeIntervalSince(since) >= 15 { flushListen(); listenedSince = Date(); updateNowPlaying() }
        if Date().timeIntervalSince(lastSessionWrite) > 5 { saveSession() }
    }
    func flushListen() {
        if let since = listenedSince, let current { store.record(current.id, seconds: max(0, Date().timeIntervalSince(since))) }
        listenedSince = nil
    }
    func checkpoint() { flushListen(); if isPlaying { listenedSince = Date() }; saveSession() }
    private struct Session: Codable { var queue: PlaybackQueue; var trackID: UUID?; var position: Double }
    private func saveSession() {
        lastSessionWrite = Date()
        if let data = try? JSONEncoder().encode(Session(queue: queue, trackID: current?.id, position: position)) { UserDefaults.standard.set(data, forKey: "playbackSession") }
    }
    private func restoreSession() {
        guard let data = UserDefaults.standard.data(forKey: "playbackSession"), let session = try? JSONDecoder().decode(Session.self, from: data),
              let track = store.track(session.trackID), session.position.isFinite,
              let restoredFile = try? AVAudioFile(forReading: store.disk.audio(track)) else { return }
        queue = session.queue; current = track; file = restoredFile
        engine.disconnectNodeOutput(node); engine.disconnectNodeOutput(eq)
        engine.connect(node, to: eq, format: restoredFile.processingFormat)
        engine.connect(eq, to: engine.mainMixerNode, format: restoredFile.processingFormat)
        duration = Double(restoredFile.length) / restoredFile.processingFormat.sampleRate
        schedule(at: min(max(0, session.position), duration), play: false)
    }
    private func interrupted(type: UInt?, options: UInt) {
        if type == AVAudioSession.InterruptionType.began.rawValue { resumeAfterInterruption = isPlaying; pause() }
        else if resumeAfterInterruption && AVAudioSession.InterruptionOptions(rawValue: options).contains(.shouldResume) { resumeAfterInterruption = false; resume() }
    }
    func refreshRoute() {
        let session = AVAudioSession.sharedInstance()
        let outputs = session.currentRoute.outputs
        routeName = outputs.map(\.portName).joined(separator: ", ")
        routeType = outputs.map { $0.portType.rawValue }.joined(separator: ", ")
        sampleRate = session.sampleRate; outputChannels = session.outputNumberOfChannels; outputLatency = session.outputLatency
        spatialAudioReported = outputs.contains { $0.isSpatialAudioEnabled }
    }
    private func applyEQ(persist: Bool = true) {
        let frequencies: [Float] = [60, 230, 910, 3600, 14000]
        for index in 0..<5 {
            let band = eq.bands[index]; band.filterType = .parametric; band.frequency = frequencies[index]; band.bandwidth = 1
            band.gain = min(12, max(-12, profile.gains.indices.contains(index) ? profile.gains[index] : 0)); band.bypass = false
        }
        eq.bands[5].filterType = .lowShelf; eq.bands[5].frequency = 100
        eq.bands[5].gain = min(6, max(0, profile.bass)); eq.bands[5].bypass = false
        eq.globalGain = min(0, max(-24, profile.preamp))
        if persist, let data = try? JSONEncoder().encode(profile) { UserDefaults.standard.set(data, forKey: "soundProfile") }
    }
    func restoreProfile() {
        if let data = UserDefaults.standard.data(forKey: "soundProfile"), let saved = try? JSONDecoder().decode(SoundProfile.self, from: data), saved.gains.count == 5 { profile = saved }
        restoreSession()
    }
    private func updateNowPlaying() {
        guard let current else { return }
        var info: [String: Any] = [MPMediaItemPropertyTitle: current.title, MPMediaItemPropertyArtist: current.artist,
            MPMediaItemPropertyAlbumTitle: current.album, MPMediaItemPropertyPlaybackDuration: duration,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: position, MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? 1.0 : 0.0]
        if let image = store.artwork(current) { info[MPMediaItemPropertyArtwork] = MPMediaItemArtwork(boundsSize: image.size) { _ in image } }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }
    private func configureRemote() {
        let center = MPRemoteCommandCenter.shared()
        func add(_ command: MPRemoteCommand, _ action: @escaping @MainActor () -> Void) {
            command.isEnabled = true
            let target = command.addTarget { _ in Task { @MainActor in action() }; return .success }
            remoteTargets.append((command, target))
        }
        add(center.playCommand) { [weak self] in self?.resume() }
        add(center.pauseCommand) { [weak self] in self?.pause() }
        add(center.togglePlayPauseCommand) { [weak self] in self?.toggle() }
        add(center.nextTrackCommand) { [weak self] in self?.next() }
        add(center.previousTrackCommand) { [weak self] in self?.previous() }
        let target = center.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let event = event as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
            let seconds = event.positionTime; Task { @MainActor in self?.seek(seconds) }; return .success
        }
        remoteTargets.append((center.changePlaybackPositionCommand, target))
    }
}
