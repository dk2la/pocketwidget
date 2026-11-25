import Foundation

/// The music apps Pocket drives end to end: it reads them, controls them and
/// can start a remembered song in them again. Everything else (browsers,
/// VLC, …) is only shown while it plays.
enum MusicProvider: String, CaseIterable, Identifiable, Sendable {
    case spotify
    case appleMusic

    var id: String { rawValue }

    var bundleID: String {
        switch self {
        case .spotify: "com.spotify.client"
        case .appleMusic: "com.apple.Music"
        }
    }

    /// Where to get it when missing. Apple Music ships with macOS, so it
    /// has none — a missing one is shown disabled.
    var downloadURL: URL? {
        switch self {
        case .spotify: URL(string: "https://www.spotify.com/download/mac/")
        case .appleMusic: nil
        }
    }

    var displayName: String {
        switch self {
        case .spotify: "Spotify"
        case .appleMusic: "Apple Music"
        }
    }

    init?(bundleID: String) {
        guard let match = Self.allCases.first(where: { $0.bundleID == bundleID }) else { return nil }
        self = match
    }
}

/// Where a provider stands on this Mac, as the provider chooser shows it.
enum MusicProviderStatus: Equatable {
    case notInstalled
    /// Automation was declined — only System Settings can turn it back on.
    case needsPermission
    case notRunning
    case ready

    static func of(installed: Bool, running: Bool, automationDenied: Bool) -> MusicProviderStatus {
        if !installed { return .notInstalled }
        if automationDenied { return .needsPermission }
        return running ? .ready : .notRunning
    }
}

/// What the Music panel leads with.
enum MusicPanelContent: Equatable {
    /// The current track's card; `withProviders` adds the chooser below
    /// when the track comes from a browser and no music app is usable.
    case player(withProviders: Bool)
    /// Nothing playing and no music app usable: pick one.
    case providers
    /// A music app is there but silent.
    case idle

    static func decide(hasTrack: Bool, hasProviderSource: Bool) -> MusicPanelContent {
        if hasTrack { return .player(withProviders: !hasProviderSource) }
        return hasProviderSource ? .idle : .providers
    }
}

/// One remembered track: what played, how often, and how to start it again.
struct PlayHistoryEntry: Codable, Identifiable, Equatable {
    /// Title and artist — the same song from any player is one entry.
    var id: String
    var title: String
    var artist: String
    /// `MediaSourceKind.id` of the player it was last heard in.
    var sourceID: String
    /// Player-specific handle to start it again (Spotify URI, Music
    /// persistent ID); `nil` when the player gave none.
    var playID: String?
    var playCount: Int
    var lastPlayed: Date
    /// File name of the cached cover in the artwork folder.
    var artworkFile: String?

    static func key(title: String, artist: String) -> String {
        "\(title)\u{1F}\(artist)"
    }
}

/// History keeps only what a click can start again — a cover that does
/// nothing is worse than no cover.
enum ReplayableHistory {
    /// Browser and other client plays are never remembered: they cannot be
    /// replayed. A provider play is, even before its handle arrives.
    static func shouldRecord(sourceID: String) -> Bool {
        MusicProvider(bundleID: sourceID) != nil
    }

    /// Entries heard in a usable provider that left a play handle. Older
    /// stores may still hold client entries; they are dropped here.
    static func filter(_ entries: [PlayHistoryEntry], usableSourceIDs: Set<String>) -> [PlayHistoryEntry] {
        entries.filter { entry in
            entry.playID != nil && shouldRecord(sourceID: entry.sourceID) && usableSourceIDs.contains(entry.sourceID)
        }
    }
}
