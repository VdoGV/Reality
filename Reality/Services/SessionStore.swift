import Foundation

final class SessionStore: ObservableObject {
    static let shared = SessionStore()

    private let storageKey = "emby.session.v1"
    private let deviceKey = "emby.deviceId.v1"

    @Published private(set) var session: EmbySession?

    private init() {
        if let data = UserDefaults.standard.data(forKey: storageKey) {
            session = try? JSONDecoder().decode(EmbySession.self, from: data)
        }
    }

    var deviceId: String {
        if let id = UserDefaults.standard.string(forKey: deviceKey), !id.isEmpty { return id }
        let id = UUID().uuidString
        UserDefaults.standard.set(id, forKey: deviceKey)
        return id
    }

    func save(_ newSession: EmbySession) {
        session = newSession
        if let data = try? JSONEncoder().encode(newSession) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
    }

    func clear() {
        session = nil
        UserDefaults.standard.removeObject(forKey: storageKey)
    }
}
