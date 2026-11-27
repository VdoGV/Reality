import SwiftUI

struct HomeTabView: View {
    @Binding var selectedTab: MainTab
    @EnvironmentObject private var store: SessionStore

    @State private var libraries: [EmbyItem] = []
    @State private var resumeItems: [EmbyItem] = []
    @State private var latestByLibrary: [String: [EmbyItem]] = [:]
    @State private var loading = false
    @State private var errorText: String?
    @State private var playing: EmbyItem?

    var body: some View {
        Group {
            if store.session == nil {
                welcome
            } else {
                feed
            }
        }
        .navigationTitle("主页")
        .navigationBarTitleDisplayMode(.large)
        .fullScreenCover(item: $playing) { item in
            PlayerScreen(item: item)
        }
        .task {
            if store.session != nil && libraries.isEmpty {
                await loadAll()
            }
        }
    }

    // MARK: - 未连接

    private var welcome: some View {
        VStack(spacing: 16) {
            Spacer()

            Image(systemName: "play.square.stack")
                .font(.system(size: 52, weight: .light))
                .foregroundStyle(.secondary.opacity(0.6))

            Text("还没有接入媒体服务器")
                .font(.headline)

            Text("连接 Emby 之后，这里会显示继续观看和最近更新。")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)

            Button {
                selectedTab = .library
            } label: {
                Text("去媒体库添加")
                    .font(.subheadline.weight(.semibold))
                    .padding(.horizontal, 22)
                    .padding(.vertical, 12)
                    .background(Color(.label), in: Capsule())
                    .foregroundStyle(Color(.systemBackground))
            }
            .padding(.top, 6)

            Spacer()
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - 内容

    @ViewBuilder
    private var feed: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 26) {
                if loading && libraries.isEmpty {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .padding(.top, 70)
                }

                if let errorText {
                    VStack(spacing: 10) {
                        Label("加载失败", systemImage: "exclamationmark.triangle.fill")
                            .font(.subheadline.bold())
                            .foregroundStyle(.orange)
                        Text(errorText)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                        Button("重试") { Task { await loadAll() } }
                            .buttonStyle(.bordered)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 24)
                }

                if !resumeItems.isEmpty {
                    MediaRow(title: "继续观看", items: resumeItems) { item in
                        playing = item
                    }
                }

                ForEach(libraries) { library in
                    if let items = latestByLibrary[library.Id], !items.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Text(library.Name)
                                    .font(.headline)
                                Spacer()
                                NavigationLink(value: LibraryRoute(id: library.Id, name: library.Name)) {
                                    HStack(spacing: 2) {
                                        Text("全部")
                                        Image(systemName: "chevron.right").font(.caption2)
                                    }
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                }
                            }
                            .padding(.horizontal, 16)

                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(alignment: .top, spacing: 14) {
                                    ForEach(items) { item in
                                        NavigationLink(value: ItemRoute(id: item.Id)) {
                                            PosterCard(item: item)
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                                .padding(.horizontal, 16)
                            }
                        }
                    }
                }

                if !loading && libraries.isEmpty {
                    Text("媒体库里还没有内容")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 40)
                }
            }
            .padding(.vertical, 12)
            .padding(.bottom, 30)
        }
        .refreshable { await loadAll() }
    }

    // MARK: - 数据

    private func loadAll() async {
        guard !loading else { return }
        loading = true
        errorText = nil
        do {
            async let resumeRequest = EmbyClient.shared.resumeItems()
            async let viewsRequest = EmbyClient.shared.views()
            let resume = try await resumeRequest
            let views = try await viewsRequest

            resumeItems = resume
            libraries = views.filter { ($0.CollectionType ?? "") != "playlists" }

            var latest: [String: [EmbyItem]] = [:]
            for library in libraries {
                if let items = try? await EmbyClient.shared.latest(parentId: library.Id, limit: 14), !items.isEmpty {
                    latest[library.Id] = items
                }
            }
            latestByLibrary = latest
        } catch {
            errorText = error.localizedDescription
        }
        loading = false
    }
}
