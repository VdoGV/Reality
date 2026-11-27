import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var store: SessionStore
    @State private var showLogoutConfirm = false

    var body: some View {
        List {
            Section("账号") {
                if let session = store.session {
                    LabeledContent("用户", value: session.userName)
                    LabeledContent("服务器", value: session.serverURL)
                }
            }

            Section("播放") {
                Text("iOS 只能直连 mp4/mov + H.264/HEVC + AAC 一类音频。其他格式（MKV、AVI、字幕内嵌 ASS 等）会自动转为 HLS 由服务端实时转码。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Text("播放进度每 10 秒回传一次，退出、切后台或播放结束时会立即上报，所以「继续观看」在多台设备间是同步的。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section("关于") {
                LabeledContent("客户端", value: "Reality 1.0")
                LabeledContent("构建方式", value: "GitHub Actions · 未签名 IPA")
                Text("本项目只做客户端，需要你自己的 Emby 服务器与账号。它不携带任何服务器地址或凭证。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section {
                Button(role: .destructive) {
                    showLogoutConfirm = true
                } label: {
                    Text("退出登录")
                }
            }
        }
        .navigationTitle("设置")
        .navigationBarTitleDisplayMode(.large)
        .confirmationDialog("确定退出当前账号？", isPresented: $showLogoutConfirm, titleVisibility: .visible) {
            Button("退出登录", role: .destructive) {
                EmbyClient.shared.logout()
            }
            Button("取消", role: .cancel) {}
        }
    }
}
