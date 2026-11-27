import Foundation

// MARK: - 会话

struct EmbySession: Codable, Equatable {
    var serverURL: String
    var accessToken: String
    var userId: String
    var userName: String
    var deviceId: String
}

struct EmbyAuthResult: Decodable {
    let AccessToken: String
    let User: EmbyUser
    let ServerId: String?
}

struct EmbyUser: Decodable, Identifiable {
    let Id: String
    let Name: String
    var PrimaryImageTag: String?
}

// MARK: - 用户数据

struct UserData: Decodable {
    var PlaybackPositionTicks: Int64?
    var PlayCount: Int?
    var Played: Bool?
    var IsFavorite: Bool?
}

// MARK: - 媒体流 / 媒体源

struct MediaStream: Decodable, Identifiable {
    let Index: Int
    var Type: String          // Video / Audio / Subtitle / EmbeddedImage
    var Codec: String?
    var Language: String?
    var DisplayTitle: String?
    var IsDefault: Bool?
    var IsExternal: Bool?
    var IsTextSubtitleStream: Bool?

    var id: Int { Index }

    var title: String {
        if let display = DisplayTitle, !display.isEmpty { return display }
        return Language ?? Codec ?? "轨道 \(Index)"
    }
}

struct MediaSource: Decodable, Identifiable {
    let Id: String
    var Name: String?
    var Container: String?
    var RunTimeTicks: Int64?
    var SupportsDirectPlay: Bool?
    var SupportsDirectStream: Bool?
    var TranscodingUrl: String?
    var MediaStreams: [MediaStream]?

    var videoStream: MediaStream? { MediaStreams?.first { $0.Type == "Video" } }
    var audioStreams: [MediaStream] { MediaStreams?.filter { $0.Type == "Audio" } ?? [] }
    var subtitleStreams: [MediaStream] { MediaStreams?.filter { $0.Type == "Subtitle" } ?? [] }
}

// MARK: - 条目

struct EmbyItem: Decodable, Identifiable {
    let Id: String
    let Name: String
    var Type: String?
    var Overview: String?
    var ProductionYear: Int?
    var RunTimeTicks: Int64?
    var IndexNumber: Int?
    var ParentIndexNumber: Int?
    var SeriesName: String?
    var SeriesId: String?
    var SeasonId: String?
    var ParentId: String?
    var CollectionType: String?
    var ImageTags: [String: String]?
    var BackdropImageTags: [String]?
    var UserData: UserData?
    var MediaSources: [MediaSource]?
    var OfficialRating: String?
    var CommunityRating: Double?
    var ChildCount: Int?
    var RecursiveItemCount: Int?

    var isFolderLike: Bool {
        ["Series", "Season", "BoxSet", "Folder", "CollectionFolder", "UserView"].contains(Type ?? "")
    }

    var resolvedRunTimeTicks: Int64? { RunTimeTicks ?? MediaSources?.first?.RunTimeTicks }

    /// 续播位置，没有则返回 0
    var resumeTicks: Int64 { UserData?.PlaybackPositionTicks ?? 0 }

    var hasResume: Bool { resumeTicks > 5 * 10_000_000 }
}

struct ItemsResponse: Decodable {
    var Items: [EmbyItem]?
    var TotalRecordCount: Int?
}

struct PlaybackInfoResponse: Decodable {
    var MediaSources: [MediaSource]?
    var PlaySessionId: String?
}
