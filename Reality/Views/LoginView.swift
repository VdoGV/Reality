import SwiftUI

struct LoginView: View {
    @State private var server = ""
    @State private var username = ""
    @State private var password = ""
    @State private var connecting = false
    @State private var errorText: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    VStack(spacing: 14) {
                        Image(systemName: "play.rectangle.fill")
                            .font(.system(size: 46))
                            .foregroundStyle(Color.accentColor)
                        Text("Reality")
                            .font(.title2.bold())
                        Text("连接你自己的 Emby 服务器")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 18)
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
                    Text("地址要带 http:// 或 https:// 以及端口号，例如 http://192.168.1.10:8096。局域网可直接用内网 IP。")
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
            }
            .navigationTitle("连接 Emby")
            .navigationBarTitleDisplayMode(.inline)
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
            } catch {
                errorText = error.localizedDescription
            }
            connecting = false
        }
    }
}
