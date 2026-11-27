import SwiftUI

// MARK: - 路由

struct ItemRoute: Hashable {
    let id: String
}

struct LibraryRoute: Hashable {
    let id: String
    let name: String
}

// MARK: - 时间格式

extension Int64 {
    var secondsValue: Double { Double(self) / 10_000_000 }

    var playTimeText: String {
        let total = Int(secondsValue)
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, total % 60)
        }
        return String(format: "%d:%02d", minutes, total % 60)
    }

    var durationText: String {
        let minutes = Int(secondsValue / 60)
        if minutes >= 60 {
            return "\(minutes / 60) 小时 \(minutes % 60) 分"
        }
        return "\(minutes) 分钟"
    }
}

// MARK: - 远程图片

struct RemoteImage: View {
    let url: URL?

    var body: some View {
        AsyncImage(url: url, transaction: Transaction(animation: .easeOut(duration: 0.25))) { phase in
            switch phase {
            case .success(let image):
                image.resizable().scaledToFill()
            case .failure:
                placeholder
            default:
                placeholder
            }
        }
    }

    private var placeholder: some View {
        ZStack {
            Color(white: 0.14)
            Image(systemName: "film")
                .font(.title3)
                .foregroundStyle(.white.opacity(0.35))
        }
    }
}

// MARK: - 进度条

struct ThinProgressBar: View {
    let progress: Double
    var height: CGFloat = 3

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(0.3))
                Capsule()
                    .fill(Color.accentColor)
                    .frame(width: max(2, geo.size.width * min(max(progress, 0), 1)))
            }
        }
        .frame(height: height)
    }
}

// MARK: - 海报卡片

struct PosterCard: View {
    let item: EmbyItem
    var width: CGFloat = 112

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ZStack(alignment: .bottom) {
                RemoteImage(url: posterURL)
                    .frame(width: width, height: width * 1.46)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay(alignment: .topTrailing) {
                        if item.hasResume {
                            Text("已看 \(Int(min(1, resumeProgress) * 100))%")
                                .font(.system(size: 9, weight: .semibold))
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                                .background(.black.opacity(0.65), in: Capsule())
                                .foregroundStyle(.white)
                                .padding(6)
                        }
                    }
                if item.hasResume {
                    ThinProgressBar(progress: resumeProgress)
                        .padding(.horizontal, 6)
                        .padding(.bottom, 7)
                }
            }
            Text(item.Name)
                .font(.caption)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
                .foregroundStyle(.primary)
            if let subtitleText {
                Text(subtitleText)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .frame(width: width, alignment: .leading)
    }

    private var resumeProgress: Double {
        guard let runtime = item.resolvedRunTimeTicks, runtime > 0 else { return 0 }
        return Double(item.resumeTicks) / Double(runtime)
    }

    private var posterURL: URL? {
        if item.kind == "Episode", let seriesId = item.SeriesId {
            return EmbyClient.shared.imageURL(itemId: seriesId, tag: nil, maxWidth: 400)
        }
        return EmbyClient.shared.imageURL(itemId: item.Id, tag: item.ImageTags?["Primary"], maxWidth: 400)
    }

    private var subtitleText: String? {
        if item.kind == "Episode" {
            var parts: [String] = []
            if let season = item.ParentIndexNumber, let index = item.IndexNumber {
                parts.append(String(format: "S%02dE%02d", season, index))
            }
            if let name = item.SeriesName { parts.append(name) }
            return parts.joined(separator: " · ")
        }
        if let year = item.ProductionYear { return "\(year)" }
        if let count = item.RecursiveItemCount, count > 0 { return "\(count) 项" }
        return nil
    }
}

// MARK: - 横向卡片行

struct MediaRow: View {
    let title: String
    let items: [EmbyItem]
    var onSelect: ((EmbyItem) -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.headline)
                .padding(.horizontal, 16)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 14) {
                    ForEach(items) { item in
                        if let onSelect {
                            Button { onSelect(item) } label: {
                                PosterCard(item: item)
                            }
                            .buttonStyle(.plain)
                        } else {
                            NavigationLink(value: ItemRoute(id: item.Id)) {
                                PosterCard(item: item)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(.horizontal, 16)
            }
        }
    }
}
