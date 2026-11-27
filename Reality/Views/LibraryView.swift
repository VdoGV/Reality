import SwiftUI

enum LibrarySort: String, CaseIterable, Identifiable {
    case name
    case dateAdded
    case year

    var id: String { rawValue }

    var title: String {
        switch self {
        case .name: return "名称"
        case .dateAdded: return "最近添加"
        case .year: return "年份"
        }
    }

    var sortBy: String {
        switch self {
        case .name: return "SortName"
        case .dateAdded: return "DateCreated"
        case .year: return "ProductionYear,SortName"
        }
    }

    var descending: Bool {
        switch self {
        case .name: return false
        case .dateAdded: return true
        case .year: return true
        }
    }
}

struct LibraryView: View {
    let libraryId: String
    let title: String

    @State private var items: [EmbyItem] = []
    @State private var totalCount = 0
    @State private var includeTypes: [String] = ["Movie", "Series", "Video"]
    @State private var sort: LibrarySort = .name
    @State private var loading = false
    @State private var errorText: String?

    private let pageSize = 60

    private var columns: [GridItem] {
        [GridItem(.adaptive(minimum: 100, maximum: 130), spacing: 14, alignment: .top)]
    }

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 18) {
                ForEach(items) { item in
                    NavigationLink(value: ItemRoute(id: item.Id)) {
                        PosterCard(item: item, width: 108)
                    }
                    .buttonStyle(.plain)
                    .onAppear {
                        if item.Id == items.last?.Id { Task { await loadMore() } }
                    }
                }
            }
            .padding(16)

            if let errorText {
                Text(errorText)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .padding()
            }

            if loading {
                ProgressView().padding(.bottom, 30)
            } else if items.isEmpty {
                Text("这个媒体库还没有内容")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.top, 60)
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Menu {
                    Picker("排序", selection: $sort) {
                        ForEach(LibrarySort.allCases) { option in
                            Text(option.title).tag(option)
                        }
                    }
                } label: {
                    Image(systemName: "arrow.up.arrow.down")
                }
            }
        }
        .onChange(of: sort) { _ in
            Task { await reload() }
        }
        .task {
            await prepare()
        }
    }

    // MARK: - 加载

    private func prepare() async {
        guard items.isEmpty else { return }
        if let detail = try? await EmbyClient.shared.detail(id: libraryId) {
            includeTypes = Self.types(for: detail.CollectionType)
        }
        await reload()
    }

    static func types(for collectionType: String?) -> [String] {
        switch collectionType {
        case "movies": return ["Movie"]
        case "tvshows": return ["Series"]
        case "music": return ["MusicAlbum", "Audio"]
        case "homevideos": return ["Video"]
        case "photos": return ["Photo"]
        case "books": return ["Book"]
        default: return ["Movie", "Series", "Video"]
        }
    }

    private func reload() async {
        items = []
        totalCount = 0
        await loadMore(reset: true)
    }

    private func loadMore(reset: Bool = false) async {
        guard !loading else { return }
        loading = true
        if reset { errorText = nil }

        do {
            let response = try await EmbyClient.shared.items(
                parentId: libraryId,
                includeTypes: includeTypes,
                sortBy: sort.sortBy,
                descending: sort.descending,
                startIndex: reset ? 0 : items.count,
                limit: pageSize
            )
            let newItems = response.Items ?? []
            if reset {
                items = newItems
            } else {
                items.append(contentsOf: newItems)
            }
            totalCount = response.TotalRecordCount ?? items.count
        } catch {
            errorText = error.localizedDescription
        }
        loading = false
    }
}
