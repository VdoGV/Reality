import SwiftUI

struct ProfileView: View {
    @EnvironmentObject private var store: SessionStore

    @State private var libraryCount: Int?
    @State private var resumeCount: Int?
    @State private var showLogoutConfirm = false

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                header
                stats
                accountCard

                Button(role: .destructive) {
                    showLogoutConfirm = true
                } label: {
                    Text("退出登录")
                        .font(.subheadline.weight(.medium))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(.quaternary, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .padding(.horizontal, 16)
            }
            .padding(.vertical, 16)
            .padding(.bottom, 30)
        }
        .navigationTitle("我的")
        .navigationBarTitleDisplayMode(.large)
        .task { await loadStats() }
        .confirmationDialog("退出当前账号？", isPresented: $showLogoutConfirm, titleVisibility: .visible) {
            Button("退出登录", role: .destructive) {
                EmbyClient.shared.logout()
                libraryCount = nil
                resumeCount = nil
            }
            Button("取消", role: .cancel) {}
        }
    }

    // MARK: - 头部

    private var header: some View {
        VStack(spacing: 10) {
            Group {
                if let url = avatarURL {
                    AsyncImage(url: url) { phase in
                        if case .success(let image) = phase {
                            image.resizable().scaledToFill()
                        } else {
                            avatarFallback
                        }
                    }
                } else {
                    avatarFallback
                }
            }
            .frame(width: 76, height: 76)
            .clipShape(Circle())

            Text(store.session?.userName ?? "未登录")
                .font(.title3.bold())

            Text(store.session == nil ? "还没有连接媒体服务器" : (store.session?.serverURL ?? ""))
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .padding(.horizontal, 30)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 8)
    }

    private var avatarFallback: some View {
        ZStack {
            LinearGradient(
                colors: [Color.accentColor.opacity(0.65), Color.accentColor.opacity(0.25)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            Text(String((store.session?.userName ?? "?").prefix(1)).uppercased())
                .font(.title.bold())
                .foregroundStyle(.white)
        }
    }

    // MARK: - 统计

    private var stats: some View {
        HStack(spacing: 12) {
            statCard(title: "媒体库", value: libraryCount.map { "\($0)" } ?? "—")
            statCard(title: "待续播", value: resumeCount.map { "\($0)" } ?? "—")
        }
        .padding(.horizontal, 16)
    }

    private func statCard(title: String, value: String) -> some View {
        VStack(spacing: 6) {
            Text(value)
                .font(.title3.bold())
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 18)
        .background(.quaternary.opacity(0.6), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    // MARK: - 账号信息

    private var accountCard: some View {
        VStack(spacing: 0) {
            row("服务器", store.session?.serverURL ?? "未连接")
            Divider().padding(.leading, 16)
            row("用户", store.session?.userName ?? "未登录")
            Divider().padding(.leading, 16)
            row("客户端", "Reality 1.0")

            if store.session == nil {
                Divider().padding(.leading, 16)
                Text("在「媒体库」里添加资源库即可开始使用。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
            }
        }
        .background(.quaternary.opacity(0.6), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .padding(.horizontal, 16)
    }

    private func row(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer(minLength: 12)
            Text(value)
                .font(.subheadline)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
    }

    private var avatarURL: URL? {
        guard let session = store.session else { return nil }
        return EmbyClient.shared.userImageURL(userId: session.userId)
    }

    private func loadStats() async {
        guard store.session != nil else { return }
        if libraryCount == nil, let views = try? await EmbyClient.shared.views() {
            libraryCount = views.filter { ($0.CollectionType ?? "") != "playlists" }.count
        }
        if resumeCount == nil, let items = try? await EmbyClient.shared.resumeItems(limit: 100) {
            resumeCount = items.count
        }
    }
}
