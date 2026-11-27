import SwiftUI

struct HomeView: View {
    @EnvironmentObject private var store: SessionStore

    @State private var libraries: [EmbyItem] = []
    @State private var resumeItems: [EmbyItem] = []
    @State private var latestByLibrary: [String: [EmbyItem]] = [:]
    @State private var loading = false
    @State private var errorText: String?
    @State private var playing: EmbyItem?

    var body: some View {
        TabView {
            NavigationStack {
                ScrollView {
                    content
                }
                .navigationTitle(store.session?.userName ?? "媒体库")
                .navigationBarTitleDisplayMode(.large)
                .navigationDestination(for: ItemRoute.self) { route in
                    DetailView(itemId: route.id)
                }
                .navigationDestination(for: LibraryRoute.self) { route in
                    LibraryView(libraryId: route.id, title: route.name)
                }
                .refreshable { await loadAll() }
            }
            .tabItem { Label("媒体库", systemImage: "rectangle.stack.fill") }

            NavigationStack {
                SearchView()
            }
            .tabItem { Label("搜索", systemImage: "magnifyingglass") }

            NavigationStack {
                SettingsView()
            }
            .tabItem { Label("设置", systemImage: "gearshape.fill") }
        }
        .fullScreenCover(item: $playing) { item in
            PlayerScreen(item: item)
        }
        .task {
            if libraries.isEmpty { await loadAll() }
        }
    }

    @ViewBuilder
    private var content: some View {
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
                                NavigationLink(value: LibraryRoute(id: library.Id, name: library.Name)) {
                                    VStack(spacing: 8) {
                                        Image(systemName: "square.grid.2x2")
                                            .font(.title2)
                                        Text("查看全部").font(.caption2)
                                    }
                                    .frame(width: 112, height: 112 * 1.46)
                                    .background(Color.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                                    .foregroundStyle(.secondary)
                                }
                                .buttonStyle(.plain)
                            }
                            .padding(.horizontal, 16)
                        }
                    }
                }
            }

            if !loading && !libraries.isEmpty && latestByLibrary.isEmpty {
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
