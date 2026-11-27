import Foundation

enum EmbyError: LocalizedError {
    case notLoggedIn
    case badURL
    case http(Int, String?)
    case decode(String)
    case noPlayableSource

    var errorDescription: String? {
        switch self {
        case .notLoggedIn:
            return "尚未登录，请先连接 Emby 服务器"
        case .badURL:
            return "服务器地址无效"
        case .http(let code, let message):
            if let message, !message.isEmpty {
                return "服务器返回 \(code)：\(message)"
            }
            return "服务器返回 \(code)"
        case .decode(let detail):
            return "数据解析失败：\(detail)"
        case .noPlayableSource:
            return "服务器没有返回可播放的媒体源"
        }
    }
}

/// 播放计划：把“播什么、怎么播”固化成一条可直接交给 AVPlayer 的 URL
struct PlaybackPlan {
    let url: URL
    let playMethod: String          // DirectPlay / Transcode
    let playSessionId: String
    let mediaSourceId: String
}

final class EmbyClient {
    static let shared = EmbyClient()

    private let store = SessionStore.shared
    private let decoder = JSONDecoder()

    private lazy var urlSession: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 20
        config.timeoutIntervalForResource = 60
        config.waitsForConnectivity = true
        return URLSession(configuration: config)
    }()

    var session: EmbySession? { store.session }

    // MARK: - 登录

    func login(server: String, username: String, password: String) async throws -> EmbySession {
        let base = Self.normalizeServer(server)
        guard let url = URL(string: base + "/Users/AuthenticateByName") else { throw EmbyError.badURL }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(authHeader, forHTTPHeaderField: "X-Emby-Authorization")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["Username": username, "Pw": password])

        let (data, response) = try await urlSession.data(for: request)
        try Self.validate(response, data)

        let auth = try decoder.decode(EmbyAuthResult.self, from: data)
        let newSession = EmbySession(
            serverURL: base,
            accessToken: auth.AccessToken,
            userId: auth.User.Id,
            userName: auth.User.Name,
            deviceId: store.deviceId
        )
        await MainActor.run { store.save(newSession) }
        return newSession
    }

    func logout() {
        Task { @MainActor in store.clear() }
    }

    static func normalizeServer(_ raw: String) -> String {
        var value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return "" }
        let lower = value.lowercased()
        if !lower.hasPrefix("http://") && !lower.hasPrefix("https://") {
            value = "http://" + value
        }
        while value.hasSuffix("/") { value.removeLast() }
        return value
    }

    private var authHeader: String {
        "MediaBrowser Client=\"Reality\", Device=\"iPhone\", DeviceId=\"\(store.deviceId)\", Version=\"1.0.0\""
    }

    // MARK: - 基础请求

    private func requireSession() throws -> EmbySession {
        guard let current = store.session else { throw EmbyError.notLoggedIn }
        return current
    }

    private func makeURL(_ path: String, query: [String: String] = [:]) throws -> URL {
        let current = try requireSession()
        guard var components = URLComponents(string: current.serverURL + path) else { throw EmbyError.badURL }
        var items = components.queryItems ?? []
        for (key, value) in query {
            items.append(URLQueryItem(name: key, value: value))
        }
        items.append(URLQueryItem(name: "api_key", value: current.accessToken))
        components.queryItems = items
        guard let url = components.url else { throw EmbyError.badURL }
        return url
    }

    private func get<T: Decodable>(_ path: String, _ query: [String: String] = [:]) async throws -> T {
        let url = try makeURL(path, query: query)
        var request = URLRequest(url: url)
        if let token = store.session?.accessToken {
            request.setValue(token, forHTTPHeaderField: "X-Emby-Token")
        }
        let (data, response) = try await urlSession.data(for: request)
        try Self.validate(response, data)
        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            throw EmbyError.decode(String(describing: error))
        }
    }

    @discardableResult
    private func postJSON<T: Decodable>(_ path: String, body: Any, query: [String: String] = [:]) async throws -> T {
        let url = try makeURL(path, query: query)
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let token = store.session?.accessToken {
            request.setValue(token, forHTTPHeaderField: "X-Emby-Token")
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await urlSession.data(for: request)
        try Self.validate(response, data)
        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            throw EmbyError.decode(String(describing: error))
        }
    }

    private func postVoid(_ path: String, body: Any, query: [String: String] = [:]) async throws {
        let url = try makeURL(path, query: query)
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let token = store.session?.accessToken {
            request.setValue(token, forHTTPHeaderField: "X-Emby-Token")
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await urlSession.data(for: request)
        try Self.validate(response, data)
    }

    private static func validate(_ response: URLResponse, _ data: Data) throws {
        guard let http = response as? HTTPURLResponse else { return }
        guard (200..<300).contains(http.statusCode) else {
            let text = String(data: data, encoding: .utf8) ?? ""
            throw EmbyError.http(http.statusCode, text.isEmpty ? nil : String(text.prefix(300)))
        }
    }

    // MARK: - 浏览接口

    func views() async throws -> [EmbyItem] {
        let current = try requireSession()
        let response: ItemsResponse = try await get("/Users/\(current.userId)/Views")
        return response.Items ?? []
    }

    func resumeItems(limit: Int = 15) async throws -> [EmbyItem] {
        let current = try requireSession()
        let response: ItemsResponse = try await get(
            "/Users/\(current.userId)/Items/Resume",
            [
                "Limit": "\(limit)",
                "MediaTypes": "Video",
                "Recursive": "true",
                "Fields": "Overview,ProductionYear",
                "ImageTypeLimit": "1",
                "EnableImageTypes": "Primary,Thumb,Backdrop"
            ]
        )
        return response.Items ?? []
    }

    func latest(parentId: String, limit: Int = 16) async throws -> [EmbyItem] {
        let current = try requireSession()
        let items: [EmbyItem] = try await get(
            "/Users/\(current.userId)/Items/Latest",
            [
                "ParentId": parentId,
                "Limit": "\(limit)",
                "Fields": "Overview,ProductionYear",
                "ImageTypeLimit": "1",
                "EnableImageTypes": "Primary,Thumb"
            ]
        )
        return items
    }

    func items(
        parentId: String? = nil,
        includeTypes: [String]? = nil,
        sortBy: String = "SortName",
        descending: Bool = false,
        startIndex: Int = 0,
        limit: Int = 60,
        searchTerm: String? = nil
    ) async throws -> ItemsResponse {
        let current = try requireSession()
        var query: [String: String] = [
            "Recursive": "true",
            "SortBy": sortBy,
            "SortOrder": descending ? "Descending" : "Ascending",
            "StartIndex": "\(startIndex)",
            "Limit": "\(limit)",
            "Fields": "Overview,ProductionYear",
            "ImageTypeLimit": "1",
            "EnableImageTypes": "Primary,Thumb,Backdrop",
            "EnableTotalRecordCount": "true"
        ]
        if let parentId { query["ParentId"] = parentId }
        if let includeTypes { query["IncludeItemTypes"] = includeTypes.joined(separator: ",") }
        if let searchTerm, !searchTerm.isEmpty { query["SearchTerm"] = searchTerm }
        return try await get("/Users/\(current.userId)/Items", query)
    }

    func detail(id: String) async throws -> EmbyItem {
        let current = try requireSession()
        return try await get("/Items/\(id)", ["Fields": "Overview,MediaSources,ProductionYear,ChildCount", "UserId": current.userId])
    }

    func seasons(seriesId: String) async throws -> [EmbyItem] {
        let current = try requireSession()
        let response: ItemsResponse = try await get(
            "/Shows/\(seriesId)/Seasons",
            ["UserId": current.userId, "Fields": "Overview", "ImageTypeLimit": "1", "EnableImageTypes": "Primary"]
        )
        return response.Items ?? []
    }

    func episodes(seriesId: String, seasonId: String? = nil) async throws -> [EmbyItem] {
        let current = try requireSession()
        var query: [String: String] = [
            "UserId": current.userId,
            "Fields": "Overview",
            "ImageTypeLimit": "1",
            "EnableImageTypes": "Primary"
        ]
        if let seasonId { query["SeasonId"] = seasonId }
        let response: ItemsResponse = try await get("/Shows/\(seriesId)/Episodes", query)
        return response.Items ?? []
    }

    // MARK: - 图片

    func imageURL(itemId: String, tag: String?, type: String = "Primary", maxWidth: Int = 500) -> URL? {
        guard let session = store.session,
              var components = URLComponents(string: session.serverURL + "/Items/\(itemId)/Images/\(type)") else {
            return nil
        }
        var query = [
            URLQueryItem(name: "maxWidth", value: "\(maxWidth)"),
            URLQueryItem(name: "quality", value: "90")
        ]
        if let tag, !tag.isEmpty {
            query.append(URLQueryItem(name: "tag", value: tag))
        }
        query.append(URLQueryItem(name: "api_key", value: session.accessToken))
        components.queryItems = query
        return components.url
    }

    func userImageURL(userId: String, maxWidth: Int = 240) -> URL? {
        guard let session = store.session,
              var components = URLComponents(string: session.serverURL + "/Users/\(userId)/Images/Primary") else {
            return nil
        }
        components.queryItems = [
            URLQueryItem(name: "maxWidth", value: "\(maxWidth)"),
            URLQueryItem(name: "quality", value: "90"),
            URLQueryItem(name: "api_key", value: session.accessToken)
        ]
        return components.url
    }

    // MARK: - 播放

    func playbackInfo(itemId: String, startTicks: Int64) async throws -> PlaybackInfoResponse {
        let current = try requireSession()
        let body: [String: Any] = [
            "UserId": current.userId,
            "StartTimeTicks": max(0, startTicks),
            "IsPlayback": true,
            "AutoOpenLiveStream": true,
            "MaxStreamingBitrate": 120_000_000,
            "DeviceProfile": Self.deviceProfile
        ]
        return try await postJSON("/Items/\(itemId)/PlaybackInfo", body: body, query: ["UserId": current.userId])
    }

    static let deviceProfile: [String: Any] = [
        "Name": "Reality",
        "MaxStreamingBitrate": 120_000_000,
        "MaxStaticBitrate": 120_000_000,
        "DirectPlayProfiles": [
            [
                "Container": "mp4,m4v,mov",
                "Type": "Video",
                "VideoCodec": "h264,hevc",
                "AudioCodec": "aac,mp3,ac3,eac3,alac"
            ]
        ],
        "TranscodingProfiles": [
            [
                "Container": "ts",
                "Type": "Video",
                "VideoCodec": "h264",
                "AudioCodec": "aac",
                "Protocol": "hls",
                "Context": "Streaming",
                "MaxAudioChannels": "2",
                "MinSegments": "1",
                "BreakOnNonKeyFrames": true
            ]
        ],
        "CodecProfiles": [],
        "SubtitleProfiles": [
            ["Format": "vtt", "Method": "Hls"],
            ["Format": "srt", "Method": "External"],
            ["Format": "ass", "Method": "External"],
            ["Format": "pgssub", "Method": "Encode"],
            ["Format": "dvdsub", "Method": "Encode"],
            ["Format": "dvbsub", "Method": "Encode"]
        ],
        "ContainerProfiles": [],
        "ResponseProfiles": []
    ]

    /// 根据媒体源决定直连播放还是 HLS 转码，并拼出最终播放 URL
    func buildPlan(
        item: EmbyItem,
        source: MediaSource,
        startTicks: Int64,
        playSessionId: String,
        audioIndex: Int? = nil,
        subtitleIndex: Int? = nil
    ) throws -> PlaybackPlan {
        let current = try requireSession()
        let start = max(0, startTicks)

        if audioIndex == nil, subtitleIndex == nil,
           let direct = directPlayURL(item: item, source: source, session: current) {
            return PlaybackPlan(url: direct, playMethod: "DirectPlay", playSessionId: playSessionId, mediaSourceId: source.Id)
        }

        let url = try transcodeURL(
            item: item,
            source: source,
            session: current,
            startTicks: start,
            playSessionId: playSessionId,
            audioIndex: audioIndex,
            subtitleIndex: subtitleIndex
        )
        return PlaybackPlan(url: url, playMethod: "Transcode", playSessionId: playSessionId, mediaSourceId: source.Id)
    }

    /// iOS 的 AVPlayer 只认 mp4/mov 家族 + h264/hevc + aac 一类音频
    private func directPlayURL(item: EmbyItem, source: MediaSource, session: EmbySession) -> URL? {
        if source.SupportsDirectPlay == false { return nil }

        let containers = (source.Container ?? "")
            .lowercased()
            .split(separator: ",")
            .map { String($0).trimmingCharacters(in: .whitespaces) }
        let playableContainers: Set<String> = ["mp4", "m4v", "mov"]
        guard let ext = containers.first(where: { playableContainers.contains($0) }) else { return nil }

        guard let video = source.videoStream else { return nil }
        let videoCodec = (video.Codec ?? "").lowercased()
        guard ["h264", "hevc", "h265"].contains(videoCodec) else { return nil }

        let audioCodecs = Set(source.audioStreams.map { ($0.Codec ?? "").lowercased() })
        let playableAudio: Set<String> = ["aac", "mp3", "ac3", "eac3", "alac"]
        guard audioCodecs.isSubset(of: playableAudio) else { return nil }

        guard var components = URLComponents(string: session.serverURL + "/Videos/\(item.Id)/stream.\(ext)") else { return nil }
        components.queryItems = [
            URLQueryItem(name: "Static", value: "true"),
            URLQueryItem(name: "MediaSourceId", value: source.Id),
            URLQueryItem(name: "Container", value: ext),
            URLQueryItem(name: "DeviceId", value: session.deviceId),
            URLQueryItem(name: "api_key", value: session.accessToken)
        ]
        return components.url
    }

    private func transcodeURL(
        item: EmbyItem,
        source: MediaSource,
        session: EmbySession,
        startTicks: Int64,
        playSessionId: String,
        audioIndex: Int?,
        subtitleIndex: Int?
    ) throws -> URL {
        var query: [URLQueryItem] = [
            URLQueryItem(name: "MediaSourceId", value: source.Id),
            URLQueryItem(name: "PlaySessionId", value: playSessionId),
            URLQueryItem(name: "DeviceId", value: session.deviceId),
            URLQueryItem(name: "api_key", value: session.accessToken),
            URLQueryItem(name: "VideoCodec", value: "h264"),
            URLQueryItem(name: "AudioCodec", value: "aac"),
            URLQueryItem(name: "TranscodingContainer", value: "ts"),
            URLQueryItem(name: "TranscodingProtocol", value: "hls"),
            URLQueryItem(name: "MaxStreamingBitrate", value: "8000000"),
            URLQueryItem(name: "MaxAudioChannels", value: "2"),
            URLQueryItem(name: "SegmentContainer", value: "ts"),
            URLQueryItem(name: "MinSegments", value: "1"),
            URLQueryItem(name: "BreakOnNonKeyFrames", value: "true"),
            URLQueryItem(name: "AudioStreamIndex", value: "\(audioIndex ?? source.audioStreams.first?.Index ?? 0)")
        ]

        if let subtitleIndex {
            // 指定字幕：由服务端压进视频流
            query.append(URLQueryItem(name: "SubtitleStreamIndex", value: "\(subtitleIndex)"))
            query.append(URLQueryItem(name: "SubtitleMethod", value: "Encode"))
        } else {
            // 不指定：让 Emby 把文本字幕作为 HLS 轨道输出，用系统字幕菜单切换
            query.append(URLQueryItem(name: "EnableSubtitlesInManifest", value: "true"))
        }

        if startTicks > 0 {
            query.append(URLQueryItem(name: "StartTimeTicks", value: "\(startTicks)"))
        }

        guard var components = URLComponents(string: session.serverURL + "/Videos/\(item.Id)/master.m3u8") else {
            throw EmbyError.badURL
        }
        components.queryItems = query
        guard let url = components.url else { throw EmbyError.badURL }
        return url
    }

    // MARK: - 播放进度上报

    func reportPlaying(item: EmbyItem, plan: PlaybackPlan, positionTicks: Int64) async throws {
        try await postVoid("/Sessions/Playing", body: progressBody(item: item, plan: plan, positionTicks: positionTicks, isPaused: false))
    }

    func reportProgress(item: EmbyItem, plan: PlaybackPlan, positionTicks: Int64, isPaused: Bool) async throws {
        try await postVoid("/Sessions/Playing/Progress", body: progressBody(item: item, plan: plan, positionTicks: positionTicks, isPaused: isPaused))
    }

    func reportStopped(item: EmbyItem, plan: PlaybackPlan, positionTicks: Int64) async throws {
        try await postVoid("/Sessions/Playing/Stopped", body: progressBody(item: item, plan: plan, positionTicks: positionTicks, isPaused: false))
    }

    private func progressBody(item: EmbyItem, plan: PlaybackPlan, positionTicks: Int64, isPaused: Bool) -> [String: Any] {
        [
            "ItemId": item.Id,
            "MediaSourceId": plan.mediaSourceId,
            "PlaySessionId": plan.playSessionId,
            "PositionTicks": max(0, positionTicks),
            "IsPaused": isPaused,
            "IsMuted": false,
            "PlayMethod": plan.playMethod,
            "CanSeek": true,
            "RepeatMode": "RepeatNone"
        ]
    }

    func markPlayed(itemId: String) async throws {
        let current = try requireSession()
        try await postVoid("/Users/\(current.userId)/PlayedItems/\(itemId)", body: [:])
    }
}
