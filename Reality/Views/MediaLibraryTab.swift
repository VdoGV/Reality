import SwiftUI

struct MediaLibraryTab: View {
    @EnvironmentObject private var store: SessionStore

    @State private var libraries: [EmbyItem] = []
    @State private var loading = false
    @State private var errorText: String?
    @State private var showAddServer = false

    private let columns = [
        GridItem(.flexible(), spacing: 14),
        GridItem(.flexible(), spacing: 14)
    ]

    var body: some View {
        Group {
            if store.session == nil {
                emptyState
            } else {
                connectedContent
            }
        }
        .navigationTitle("媒体库")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            if store.session != nil {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Menu {
                        Button("刷新") { Task { await load(reset: true) } }
                        Button("重新添加服务器") { showAddServer = true }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
        }
        .sheet(isPresented: $showAddServer) {
            AddServerSheet { Task { await load(reset: true) } }
        }
        .task {
            if store.session != nil { await load(reset: true) }
        }
    }

    // MARK: - 空状态（未添加服务器）

    private var emptyState: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.96, green: 0.95, blue: 0.98),
                    Color(red: 0.99, green: 0.93, blue: 0.94)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(spacing: 14) {
                Spacer()

                Image(systemName: "rectangle.stack.badge.plus")
                    .font(.system(size: 52, weight: .regular))
                    .foregroundStyle(.gray.opacity(0.55))
                    .padding(.bottom, 6)

                Text("还没有媒体库")
                    .font(.title3.bold())

                Text("添加媒体服务器后，可以在这里集中浏览。")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 36)

                Button {
                    showAddServer = true
                } label: {
                    Text("添加资源库")
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 26)
                        .padding(.vertical, 13)
                        .background(Color(.label), in: Capsule())
                        .foregroundStyle(Color(.systemBackground))
                }
                .padding(.top, 10)

                Spacer()
                Spacer()
            }
        }
    }

    // MARK: - 已连接

    @ViewBuilder
    private var connectedContent: some View {
        if loading && libraries.isEmpty {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if libraries.isEmpty {
            emptyState
        } else {
            ScrollView {
                if let errorText {
                    Text(errorText)
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .padding(.top, 12)
                }

                LazyVGrid(columns: columns, spacing: 14) {
                    ForEach(libraries) { library in
                        NavigationLink(value: LibraryRoute(id: library.Id, name: library.Name)) {
                            LibraryCard(library: library)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(16)

                Button {
                    showAddServer = true
                } label: {
                    Label("添加资源库", systemImage: "plus")
                        .font(.footnote.weight(.medium))
                        .padding(.horizontal, 18)
                        .padding(.vertical, 11)
                        .background(.quaternary, in: Capsule())
                }
                .padding(.bottom, 30)
            }
            .refreshable { await load(reset: true) }
        }
    }

    // MARK: - 数据

    private func load(reset: Bool = false) async {
        guard store.session != nil, !loading else { return }
        loading = true
        if reset { errorText = nil }
        do {
            let views = try await EmbyClient.shared.views()
            libraries = views.filter { ($0.CollectionType ?? "") != "playlists" }
        } catch {
            errorText = error.localizedDescription
        }
        loading = false
    }
}

// MARK: - 媒体库卡片

struct LibraryCard: View {
    let library: EmbyItem

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            RemoteImage(url: EmbyClient.shared.imageURL(itemId: library.Id, tag: library.ImageTags?["Primary"], maxWidth: 500))
                .frame(height: 108)
                .frame(maxWidth: .infinity)
                .clipped()

            LinearGradient(
                colors: [.clear, .black.opacity(0.78)],
                startPoint: .top,
                endPoint: .bottom
            )

            VStack(alignment: .leading, spacing: 2) {
                Text(library.Name)
                    .font(.subheadline.bold())
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Text(subtitle)
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.75))
            }
            .padding(12)
        }
        .frame(height: 108)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var subtitle: String {
        if let count = library.RecursiveItemCount, count > 0 {
            return "\(count) 个项目"
        }
        switch library.CollectionType {
        case "movies": return "电影"
        case "tvshows": return "剧集"
        case "music": return "音乐"
        case "homevideos": return "视频"
        case "photos": return "照片"
        default: return "媒体库"
        }
    }
}
