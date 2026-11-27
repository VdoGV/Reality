import AVKit
import Combine
import Foundation

@MainActor
final class PlaybackModel: ObservableObject {
    let player = AVPlayer()

    @Published var item: EmbyItem?
    @Published var isLoading = true
    @Published var errorMessage: String?
    @Published var playMethod = ""
    @Published var ended = false
    @Published var nextEpisode: EmbyItem?
    @Published var audioTracks: [MediaStream] = []
    @Published var subtitleTracks: [MediaStream] = []
    @Published var selectedAudio: Int?
    @Published var selectedSubtitle: Int?

    private var plan: PlaybackPlan?
    private var currentSource: MediaSource?
    private var progressTask: Task<Void, Never>?
    private var endObserver: NSObjectProtocol?
    private var started = false

    // MARK: - 载入

    func load(item: EmbyItem) async {
        self.item = item
        isLoading = true
        errorMessage = nil
        ended = false

        do {
            let requestedStart = item.resumeTicks
            let info = try await EmbyClient.shared.playbackInfo(itemId: item.Id, startTicks: requestedStart)
            guard let source = info.MediaSources?.first else { throw EmbyError.noPlayableSource }

            currentSource = source
            audioTracks = source.audioStreams
            subtitleTracks = source.subtitleStreams
            selectedAudio = source.audioStreams.first(where: { $0.IsDefault == true })?.Index ?? source.audioStreams.first?.Index

            let playSession = info.PlaySessionId ?? UUID().uuidString
            let plan = try EmbyClient.shared.buildPlan(
                item: item,
                source: source,
                startTicks: requestedStart,
                playSessionId: playSession
            )
            self.plan = plan
            playMethod = plan.playMethod

            configureAudioSession()
            attach(url: plan.url)

            isLoading = false
            try? await EmbyClient.shared.reportPlaying(item: item, plan: plan, positionTicks: requestedStart)
            started = true
            startProgressLoop()
            await loadNextEpisode(for: item)
        } catch {
            errorMessage = error.localizedDescription
            isLoading = false
        }
    }

    private func attach(url: URL) {
        let asset = AVURLAsset(url: url)
        let playerItem = AVPlayerItem(asset: asset)
        playerItem.preferredForwardBufferDuration = 10
        player.replaceCurrentItem(with: playerItem)
        observeEnd(playerItem)
        player.play()
    }

    private func configureAudioSession() {
        let audioSession = AVAudioSession.sharedInstance()
        try? audioSession.setCategory(.playback, mode: .moviePlayback)
        try? audioSession.setActive(true)
    }

    // MARK: - 进度

    private func startProgressLoop() {
        progressTask?.cancel()
        progressTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 10 * 1_000_000_000)
                guard let self, !Task.isCancelled else { return }
                await self.pushProgress()
            }
        }
    }

    private func pushProgress() async {
        guard started, let item, let plan, !ended else { return }
        let ticks = currentTicks()
        let isPaused = player.timeControlStatus != .playing
        try? await EmbyClient.shared.reportProgress(item: item, plan: plan, positionTicks: ticks, isPaused: isPaused)
        if shouldMarkPlayed(ticks: ticks) {
            try? await EmbyClient.shared.markPlayed(itemId: item.Id)
        }
    }

    private func shouldMarkPlayed(ticks: Int64) -> Bool {
        guard let total = resolvedDurationTicks(), total > 0 else { return false }
        return ticks >= total - 40 * 10_000_000
    }

    private func resolvedDurationTicks() -> Int64? {
        if let runtime = item?.resolvedRunTimeTicks, runtime > 0 { return runtime }
        if let sourceRuntime = currentSource?.RunTimeTicks, sourceRuntime > 0 { return sourceRuntime }
        let seconds = player.currentItem?.duration.seconds ?? .nan
        if seconds.isFinite, seconds > 0 { return Int64(seconds * 10_000_000) }
        return nil
    }

    func currentTicks() -> Int64 {
        let seconds = player.currentTime().seconds
        guard seconds.isFinite, seconds > 0 else { return 0 }
        return Int64(seconds * 10_000_000)
    }

    // MARK: - 结束与下一集

    private func observeEnd(_ playerItem: AVPlayerItem) {
        if let observer = endObserver {
            NotificationCenter.default.removeObserver(observer)
        }
        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: playerItem,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.ended = true
                self.progressTask?.cancel()
                if let item = self.item, let plan = self.plan {
                    try? await EmbyClient.shared.reportStopped(item: item, plan: plan, positionTicks: self.currentTicks())
                    try? await EmbyClient.shared.markPlayed(itemId: item.Id)
                }
            }
        }
    }

    private func loadNextEpisode(for item: EmbyItem) async {
        guard item.kind == "Episode", let seriesId = item.SeriesId else {
            nextEpisode = nil
            return
        }
        do {
            let episodes = try await EmbyClient.shared.episodes(seriesId: seriesId, seasonId: item.SeasonId)
            if let index = episodes.firstIndex(where: { $0.Id == item.Id }), index + 1 < episodes.count {
                nextEpisode = episodes[index + 1]
            } else {
                nextEpisode = nil
            }
        } catch {
            nextEpisode = nil
        }
    }

    func playNext() async {
        guard let next = nextEpisode else { return }
        await stop()
        plan = nil
        started = false
        ended = false
        await load(item: next)
    }

    func replay() async {
        guard let item = item else { return }
        _ = await player.seek(to: .zero)
        player.play()
        ended = false
        startProgressLoop()
        if let plan = plan {
            try? await EmbyClient.shared.reportPlaying(item: item, plan: plan, positionTicks: 0)
        }
    }

    // MARK: - 轨道切换

    func switchAudio(to index: Int) async {
        selectedAudio = index
        await restartStreams()
    }

    func switchSubtitle(to index: Int?) async {
        selectedSubtitle = index
        await restartStreams()
    }

    private func restartStreams() async {
        guard let item, let source = currentSource, started else { return }
        let ticks = currentTicks()
        do {
            let playSession = UUID().uuidString
            let newPlan = try EmbyClient.shared.buildPlan(
                item: item,
                source: source,
                startTicks: ticks,
                playSessionId: playSession,
                audioIndex: selectedAudio,
                subtitleIndex: selectedSubtitle
            )
            plan = newPlan
            playMethod = newPlan.playMethod
            attach(url: newPlan.url)
            try? await EmbyClient.shared.reportPlaying(item: item, plan: newPlan, positionTicks: ticks)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - 收尾

    func stop() async {
        progressTask?.cancel()
        progressTask = nil
        guard started, let item, let plan else {
            player.pause()
            return
        }
        started = false
        try? await EmbyClient.shared.reportStopped(item: item, plan: plan, positionTicks: currentTicks())
        player.pause()
        player.replaceCurrentItem(with: nil)
        if let observer = endObserver {
            NotificationCenter.default.removeObserver(observer)
            endObserver = nil
        }
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}
