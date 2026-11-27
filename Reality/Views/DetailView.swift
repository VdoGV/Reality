import SwiftUI

struct DetailView: View {
    let itemId: String

    @State private var item: EmbyItem?
    @State private var seasons: [EmbyItem] = []
    @State private var episodes: [EmbyItem] = []
    @State private var selectedSeasonId: String?
    @State private var loading = true
    @State private var errorText: String?
    @State private var playing: EmbyItem?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if let item {
                    header(item)
                    actionBar(item)

                    if let overview = item.Overview, !overview.isEmpty {
                        Text(overview)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 16)
                    }

                    if !seasons.isEmpty {
                        seasonStrip
                    }

                    if !episodes.isEmpty {
                        episodeList
                    }
                } else if loading {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .padding(.top, 90)
                }

                if let errorText {
                    Label(errorText, systemImage: "exclamationmark.triangle")
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .padding(.horizontal, 16)
                }
            }
            .padding(.bottom, 40)
        }
        .navigationTitle(item?.Name ?? "详情")
        .navigationBarTitleDisplayMode(.inline)
        .fullScreenCover(item: $playing) { target in
            PlayerScreen(item: target)
        }
        .task { await load() }
    }

    // MARK: - 头部

    private func header(_ item: EmbyItem) -> some View {
        ZStack(alignment: .bottomLeading) {
            RemoteImage(url: backdropURL(item))
                .frame(height: 250)
                .clipped()

            LinearGradient(
                colors: [.clear, .black.opacity(0.9)],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 250)

            VStack(alignment: .leading, spacing: 6) {
                Text(item.Name)
                    .font(.title2.bold())
                    .lineLimit(3)
                Text(metaLine(item))
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.8))
            }
            .padding(16)
        }
        .frame(height: 250)
    }

    private func backdropURL(_ item: EmbyItem) -> URL? {
        if let tag = item.BackdropImageTags?.first {
            return EmbyClient.shared.imageURL(itemId: item.Id, tag: tag, type: "Backdrop", maxWidth: 900)
        }
        if item.kind == "Episode", let seriesId = item.SeriesId {
            return EmbyClient.shared.imageURL(itemId: seriesId, tag: nil, type: "Backdrop", maxWidth: 900)
        }
        return EmbyClient.shared.imageURL(itemId: item.Id, tag: item.ImageTags?["Primary"], type: "Primary", maxWidth: 900)
    }

    private func metaLine(_ item: EmbyItem) -> String {
        var parts: [String] = []
        if let type = item.kind {
            switch type {
            case "Movie": parts.append("电影")
            case "Series": parts.append("剧集")
            case "Episode": parts.append("单集")
            case "Season": parts.append("季")
            default: break
            }
        }
        if let year = item.ProductionYear { parts.append("\(year)") }
        if let rating = item.OfficialRating { parts.append(rating) }
        if let runtime = item.resolvedRunTimeTicks, runtime > 0, item.kind != "Series" {
            parts.append(runtime.durationText)
        }
        if let seasonsCount = item.ChildCount, item.kind == "Series" {
            parts.append("\(seasonsCount) 季")
        }
        if let score = item.CommunityRating {
            parts.append(String(format: "%.1f 分", score))
        }
        return parts.joined(separator: " · ")
    }

    // MARK: - 操作区

    private func actionBar(_ item: EmbyItem) -> some View {
        HStack(spacing: 12) {
            Button {
                if let target = primaryTarget(item) { playing = target }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "play.fill")
                    Text(primaryButtonTitle(item))
                        .lineLimit(1)
                }
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 13)
                .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .foregroundStyle(.white)
            }

            if item.isFolderLike, item.kind != "Season" {
                Button {
                    if let first = episodes.first { playing = first }
                } label: {
                    Image(systemName: "shuffle")
                        .font(.headline)
                        .frame(width: 48, height: 48)
                        .background(Color(.secondarySystemFill), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .disabled(episodes.isEmpty)
            }
        }
        .padding(.horizontal, 16)
    }

    private func primaryTarget(_ item: EmbyItem) -> EmbyItem? {
        if item.kind == "Series" || item.kind == "Season" {
            return episodes.first
        }
        return item
    }

    private func primaryButtonTitle(_ item: EmbyItem) -> String {
        guard let target = primaryTarget(item) else { return "暂无内容" }
        if item.kind == "Series" || item.kind == "Season" {
            return target.hasResume ? "继续观看" : "播放第一集"
        }
        return target.hasResume ? "继续播放" : "播放"
    }

    // MARK: - 季 / 集

    private var seasonStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(seasons) { season in
                    let isSelected = (selectedSeasonId ?? seasons.first?.Id) == season.Id
                    Button {
                        selectedSeasonId = season.Id
                        Task { await loadEpisodes(seasonId: season.Id) }
                    } label: {
                        Text(season.Name)
                            .font(.footnote.weight(.medium))
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(
                                isSelected ? Color.accentColor : Color(.secondarySystemFill),
                                in: Capsule()
                            )
                            .foregroundStyle(isSelected ? Color.white : Color.secondary)
                    }
                }
            }
            .padding(.horizontal, 16)
        }
    }

    private var episodeList: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(episodes) { episode in
                Button {
                    playing = episode
                } label: {
                    episodeRow(episode)
                }
                .buttonStyle(.plain)
                Divider().padding(.leading, 16)
            }
        }
    }

    private func episodeRow(_ episode: EmbyItem) -> some View {
        HStack(alignment: .top, spacing: 12) {
            RemoteImage(url: EmbyClient.shared.imageURL(itemId: episode.Id, tag: episode.ImageTags?["Primary"], maxWidth: 320))
                .frame(width: 116, height: 66)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    if let index = episode.IndexNumber {
                        Text("\(index)")
                            .font(.caption.bold())
                            .foregroundStyle(.secondary)
                    }
                    Text(episode.Name)
                        .font(.subheadline.weight(.medium))
                        .lineLimit(2)
                    if episode.UserData?.Played == true {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.caption)
                            .foregroundStyle(.green)
                    }
                }
                if let runtime = episode.resolvedRunTimeTicks, runtime > 0 {
                    Text(runtime.durationText)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                if let overview = episode.Overview, !overview.isEmpty {
                    Text(overview)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                if episode.hasResume, let runtime = episode.resolvedRunTimeTicks, runtime > 0 {
                    ThinProgressBar(progress: Double(episode.resumeTicks) / Double(runtime))
                        .padding(.top, 2)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
    }

    // MARK: - 数据

    private func load() async {
        guard item == nil else { return }
        do {
            let detail = try await EmbyClient.shared.detail(id: itemId)
            item = detail

            if detail.kind == "Series" {
                let seasonList = try await EmbyClient.shared.seasons(seriesId: detail.Id)
                seasons = seasonList
                let first = seasonList.first(where: { ($0.IndexNumber ?? 0) != 0 }) ?? seasonList.first
                selectedSeasonId = first?.Id
                if let seasonId = first?.Id {
                    episodes = try await EmbyClient.shared.episodes(seriesId: detail.Id, seasonId: seasonId)
                }
            } else if detail.kind == "Season", let seriesId = detail.SeriesId {
                seasons = (try? await EmbyClient.shared.seasons(seriesId: seriesId)) ?? []
                selectedSeasonId = detail.Id
                episodes = try await EmbyClient.shared.episodes(seriesId: seriesId, seasonId: detail.Id)
            }
            loading = false
        } catch {
            errorText = error.localizedDescription
            loading = false
        }
    }

    private func loadEpisodes(seasonId: String) async {
        guard let seriesId = item?.Id else { return }
        do {
            episodes = try await EmbyClient.shared.episodes(seriesId: seriesId, seasonId: seasonId)
        } catch {
            errorText = error.localizedDescription
        }
    }
}
