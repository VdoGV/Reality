import SwiftUI

struct SearchView: View {
    @State private var query = ""
    @State private var results: [EmbyItem] = []
    @State private var total = 0
    @State private var searching = false
    @State private var errorText: String?
    @State private var searchTask: Task<Void, Never>?

    private var columns: [GridItem] {
        [GridItem(.adaptive(minimum: 100, maximum: 130), spacing: 14, alignment: .top)]
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                if searching {
                    ProgressView().padding(.top, 40)
                } else if results.isEmpty {
                    if query.isEmpty {
                        VStack(spacing: 10) {
                            Image(systemName: "magnifyingglass")
                                .font(.largeTitle)
                                .foregroundStyle(.secondary)
                            Text("搜索电影、剧集、单集")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.top, 90)
                    } else {
                        Text("没有找到「\(query)」")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .padding(.top, 60)
                    }
                } else {
                    LazyVGrid(columns: columns, spacing: 18) {
                        ForEach(results) { item in
                            NavigationLink(value: ItemRoute(id: item.Id)) {
                                PosterCard(item: item, width: 108)
                            }
                            .buttonStyle(.plain)
                            .onAppear {
                                if item.Id == results.last?.Id { Task { await loadMore() } }
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                }

                if let errorText {
                    Text(errorText).font(.footnote).foregroundStyle(.red)
                }
            }
            .padding(.vertical, 12)
            .padding(.bottom, 30)
        }
        .navigationTitle("搜索")
        .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "片名、剧名")
        .onChange(of: query) { newValue in
            scheduleSearch(newValue)
        }
    }

    private func scheduleSearch(_ text: String) {
        searchTask?.cancel()
        let keyword = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !keyword.isEmpty else {
            results = []
            total = 0
            searching = false
            errorText = nil
            return
        }
        searching = true
        searchTask = Task {
            try? await Task.sleep(nanoseconds: 400 * 1_000_000)
            guard !Task.isCancelled else { return }
            await performSearch(keyword, reset: true)
        }
    }

    private func loadMore() async {
        guard !searching else { return }
        let keyword = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !keyword.isEmpty, results.count < total else { return }
        await performSearch(keyword, reset: false)
    }

    private func performSearch(_ keyword: String, reset: Bool) async {
        if reset { searching = true }
        do {
            let response = try await EmbyClient.shared.items(
                includeTypes: ["Movie", "Series", "Episode"],
                sortBy: "SortName",
                descending: false,
                startIndex: reset ? 0 : results.count,
                limit: 60,
                searchTerm: keyword
            )
            let newItems = response.Items ?? []
            if reset {
                results = newItems
                total = response.TotalRecordCount ?? newItems.count
            } else {
                results.append(contentsOf: newItems)
            }
            errorText = nil
        } catch {
            if reset { errorText = error.localizedDescription }
        }
        if reset { searching = false }
    }
}
