import AVKit
import SwiftUI

// MARK: - 播放器容器

struct PlayerHost: UIViewControllerRepresentable {
    let player: AVPlayer

    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let controller = AVPlayerViewController()
        controller.player = player
        controller.showsPlaybackControls = true
        controller.allowsPictureInPicturePlayback = true
        controller.canStartPictureInPictureAutomaticallyFromInline = true
        controller.updatesNowPlayingInfoCenter = true
        controller.videoGravity = .resizeAspect
        return controller
    }

    func updateUIViewController(_ controller: AVPlayerViewController, context: Context) {
        if controller.player !== player {
            controller.player = player
        }
    }
}

// MARK: - 播放页

struct PlayerScreen: View {
    let item: EmbyItem

    @StateObject private var model = PlaybackModel()
    @Environment(\.dismiss) private var dismiss
    @State private var showTracks = false

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            PlayerHost(player: model.player)
                .ignoresSafeArea()

            if model.isLoading {
                VStack(spacing: 14) {
                    ProgressView().tint(.white)
                    Text("正在准备播放…")
                        .font(.footnote)
                        .foregroundStyle(.white.opacity(0.7))
                }
            }

            if let message = model.errorMessage {
                errorCard(message)
            }

            topBar

            if model.ended {
                endedCard
            }
        }
        .statusBarHidden(true)
        .task { await model.load(item: item) }
        .onDisappear {
            Task { await model.stop() }
        }
        .sheet(isPresented: $showTracks) {
            TrackSheet(model: model)
                .presentationDetents([.medium, .large])
        }
    }

    // MARK: - 顶部条

    private var topBar: some View {
        VStack {
            HStack(alignment: .top, spacing: 12) {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 15, weight: .bold))
                        .frame(width: 34, height: 34)
                        .background(.black.opacity(0.55), in: Circle())
                        .foregroundStyle(.white)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(displayTitle)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    if !model.playMethod.isEmpty {
                        Text(model.playMethod == "DirectPlay" ? "直接播放" : "服务器转码")
                            .font(.caption2)
                            .foregroundStyle(.white.opacity(0.6))
                    }
                }

                Spacer(minLength: 0)

                Button {
                    showTracks = true
                } label: {
                    Image(systemName: "captions.bubble")
                        .font(.system(size: 15, weight: .semibold))
                        .frame(width: 34, height: 34)
                        .background(.black.opacity(0.55), in: Circle())
                        .foregroundStyle(.white)
                }
                .disabled(model.audioTracks.isEmpty && model.subtitleTracks.isEmpty)
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)

            Spacer()
        }
    }

    private var displayTitle: String {
        if item.kind == "Episode" {
            var parts: [String] = []
            if let season = item.ParentIndexNumber, let index = item.IndexNumber {
                parts.append(String(format: "S%02dE%02d", season, index))
            }
            if let series = item.SeriesName { parts.append(series) }
            parts.append(item.Name)
            return parts.joined(separator: " · ")
        }
        return item.Name
    }

    // MARK: - 结束卡片

    private var endedCard: some View {
        VStack(spacing: 16) {
            Text("播放结束")
                .font(.title3.bold())
                .foregroundStyle(.white)

            if let next = model.nextEpisode {
                Button {
                    Task { await model.playNext() }
                } label: {
                    Label("播放下一集 · \(next.Name)", systemImage: "forward.end.fill")
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 18)
                        .padding(.vertical, 11)
                        .background(Color.accentColor, in: Capsule())
                        .foregroundStyle(.white)
                }
            }

            HStack(spacing: 12) {
                Button {
                    Task { await model.replay() }
                } label: {
                    Label("重播", systemImage: "arrow.counterclockwise")
                        .font(.subheadline)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(.white.opacity(0.14), in: Capsule())
                        .foregroundStyle(.white)
                }

                Button {
                    dismiss()
                } label: {
                    Text("关闭")
                        .font(.subheadline)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(.white.opacity(0.14), in: Capsule())
                        .foregroundStyle(.white)
                }
            }
        }
        .padding(24)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .padding(32)
    }

    private func errorCard(_ message: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.largeTitle)
                .foregroundStyle(.orange)
            Text(message)
                .font(.footnote)
                .multilineTextAlignment(.center)
                .foregroundStyle(.white.opacity(0.85))
            HStack(spacing: 12) {
                Button("重试") {
                    Task { await model.load(item: item) }
                }
                .buttonStyle(.borderedProminent)
                Button("返回") { dismiss() }
                    .buttonStyle(.bordered)
            }
        }
        .padding(24)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .padding(28)
    }
}

// MARK: - 音轨 / 字幕

struct TrackSheet: View {
    @ObservedObject var model: PlaybackModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section("音轨") {
                    if model.audioTracks.isEmpty {
                        Text("没有可选音轨").foregroundStyle(.secondary)
                    }
                    ForEach(model.audioTracks) { track in
                        Button {
                            Task { await model.switchAudio(to: track.Index) }
                        } label: {
                            HStack {
                                Text(track.title)
                                Spacer()
                                if model.selectedAudio == track.Index {
                                    Image(systemName: "checkmark").foregroundStyle(Color.accentColor)
                                }
                            }
                        }
                        .foregroundStyle(.primary)
                    }
                }

                Section {
                    Button {
                        Task { await model.switchSubtitle(to: nil) }
                    } label: {
                        HStack {
                            Text("关闭字幕")
                            Spacer()
                            if model.selectedSubtitle == nil {
                                Image(systemName: "checkmark").foregroundStyle(Color.accentColor)
                            }
                        }
                    }
                    .foregroundStyle(.primary)

                    ForEach(model.subtitleTracks) { track in
                        Button {
                            Task { await model.switchSubtitle(to: track.Index) }
                        } label: {
                            HStack {
                                Text(track.title)
                                Spacer()
                                if model.selectedSubtitle == track.Index {
                                    Image(systemName: "checkmark").foregroundStyle(Color.accentColor)
                                }
                            }
                        }
                        .foregroundStyle(.primary)
                    }
                } header: {
                    Text("字幕")
                } footer: {
                    Text("切换轨道会从当前位置重新拉流，需要几秒缓冲。图形字幕（PGS/VobSub）由服务端压入画面。")
                }
            }
            .navigationTitle("声音与字幕")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("完成") { dismiss() }
                }
            }
        }
    }
}
