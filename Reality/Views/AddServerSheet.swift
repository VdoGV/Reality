import SwiftUI

struct AddServerSheet: View {
    var onDone: (() -> Void)?

    @Environment(\.dismiss) private var dismiss
    @State private var server = ""
    @State private var username = ""
    @State private var password = ""
    @State private var connecting = false
    @State private var errorText: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    VStack(spacing: 10) {
                        Image(systemName: "play.rectangle.fill")
                            .font(.system(size: 40))
                            .foregroundStyle(Color.accentColor)
                        Text("连接 Emby 服务器")
                            .font(.headline)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .listRowBackground(Color.clear)
                }

                Section {
                    TextField("http://192.168.1.10:8096", text: $server)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    TextField("用户名", text: $username)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    SecureField("密码", text: $password)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                } header: {
                    Text("服务器")
                } footer: {
                    Text("要带 http:// 或 https:// 和端口，例如 http://192.168.1.10:8096。局域网直接用内网 IP 即可。")
                }

                Section {
                    Button(action: connect) {
                        HStack {
                            Spacer()
                            if connecting {
                                ProgressView().padding(.trailing, 6)
                            }
                            Text(connecting ? "连接中…" : "连接")
                                .fontWeight(.semibold)
                            Spacer()
                        }
                    }
                    .disabled(connecting || server.isEmpty || username.isEmpty)
                }

                if let errorText {
                    Section {
                        Label(errorText, systemImage: "exclamationmark.triangle")
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                }

                Section {
                    Text("只支持服务器地址 + 账号登录，不支持 Emby Connect 云账号。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("添加资源库")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
            }
        }
    }

    private func connect() {
        errorText = nil
        connecting = true
        let serverValue = server
        let userValue = username
        let passwordValue = password

        Task {
            do {
                _ = try await EmbyClient.shared.login(server: serverValue, username: userValue, password: passwordValue)
                connecting = false
                onDone?()
                dismiss()
            } catch {
                errorText = error.localizedDescription
                connecting = false
            }
        }
    }
}
