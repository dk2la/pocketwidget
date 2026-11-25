import AppKit
import SwiftUI
import Observation
import OSLog

extension PlayHistoryEntry {
    var source: MediaSourceKind {
        MediaSourceKind(bundleID: sourceID)
    }
}

/// What Pocket has heard play, kept on this Mac only: the last tracks with
/// a small cover each, and a play count that picks the "on repeat" track.
/// Stored as JSON plus JPEG thumbnails in Application Support; demo mode
/// swaps in a scripted list and never touches the disk.
@MainActor
@Observable
final class PlayHistory {
    /// Most recent first.
    private(set) var entries: [PlayHistoryEntry] = []
    /// Covers by entry id, loaded from disk on demand.
    private(set) var covers: [String: NSImage] = [:]

    @ObservationIgnored private var accents: [String: Color] = [:]
    @ObservationIgnored private var isDemo = false
    @ObservationIgnored private var savedEntries: [PlayHistoryEntry] = []
    @ObservationIgnored private var savedCovers: [String: NSImage] = [:]
    @ObservationIgnored private var saveTask: Task<Void, Never>?
    @ObservationIgnored private let log = Logger(subsystem: "com.dk2la.pocket", category: "play-history")

    static let limit = 40
    /// Plays older than this no longer count toward "on repeat".
    static let repeatWindow: TimeInterval = 14 * 24 * 3600

    @ObservationIgnored private static let folder: URL = {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return support
            .appendingPathComponent("Pocket", isDirectory: true)
            .appendingPathComponent("PlayHistory", isDirectory: true)
    }()

    private static var fileURL: URL { folder.appendingPathComponent("history.json") }

    init() {
        load()
    }

    // MARK: - Reading

    /// Recently played songs that can be started again in one of
    /// `usableSourceIDs`, without the track that is on right now.
    func recent(excluding current: MediaTrack?, usableSourceIDs: Set<String>) -> [PlayHistoryEntry] {
        let currentKey = current.map { PlayHistoryEntry.key(title: $0.title, artist: $0.artist) }
        return ReplayableHistory.filter(entries, usableSourceIDs: usableSourceIDs).filter { $0.id != currentKey }
    }

    /// The most played replayable track of the last two weeks, once
    /// something has been heard more than once.
    func onRepeat(usableSourceIDs: Set<String>) -> PlayHistoryEntry? {
        let since = Date().addingTimeInterval(-Self.repeatWindow)
        return ReplayableHistory.filter(entries, usableSourceIDs: usableSourceIDs)
            .filter { $0.lastPlayed >= since && $0.playCount > 1 }
            .max { ($0.playCount, $0.lastPlayed) < ($1.playCount, $1.lastPlayed) }
    }

    /// Average color of an entry's cover, computed once.
    func accent(for entry: PlayHistoryEntry) -> Color? {
        if let cached = accents[entry.id] { return cached }
        guard let color = cover(for: entry)?.averageColor else { return nil }
        accents[entry.id] = color
        return color
    }

    func cover(for entry: PlayHistoryEntry) -> NSImage? {
        if let image = covers[entry.id] { return image }
        guard !isDemo, let file = entry.artworkFile,
              let image = NSImage(contentsOf: Self.folder.appendingPathComponent(file))
        else { return nil }
        // Cached on first use; mutating here is deferred so a view body
        // never writes observable state while it is being evaluated.
        Task { @MainActor in self.covers[entry.id] = image }
        return image
    }

    // MARK: - Recording

    /// A new song started playing.
    func recordPlay(_ track: MediaTrack) {
        guard !track.title.isEmpty, ReplayableHistory.shouldRecord(sourceID: track.source.id) else { return }
        let key = PlayHistoryEntry.key(title: track.title, artist: track.artist)
        var entry = entries.first { $0.id == key } ?? PlayHistoryEntry(
            id: key, title: track.title, artist: track.artist, sourceID: track.source.id,
            playID: nil, playCount: 0, lastPlayed: Date(), artworkFile: nil
        )
        entry.playCount += 1
        entry.lastPlayed = Date()
        entry.sourceID = track.source.id
        if let playID = track.playID { entry.playID = playID }
        entries.removeAll { $0.id == key }
        entries.insert(entry, at: 0)
        trim()
        scheduleSave()
    }

    /// The cover for a song arrived (often a beat after the song itself).
    func attachArtwork(_ image: NSImage, to track: MediaTrack) {
        let key = PlayHistoryEntry.key(title: track.title, artist: track.artist)
        guard let index = entries.firstIndex(where: { $0.id == key }) else { return }
        let thumbnail = image.thumbnail(side: 160)
        covers[key] = thumbnail
        guard !isDemo, let data = thumbnail.jpegData() else { return }
        let file = Self.fileName(for: key)
        entries[index].artworkFile = file
        let url = Self.folder.appendingPathComponent(file)
        Task.detached(priority: .utility) {
            try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? data.write(to: url, options: .atomic)
        }
        scheduleSave()
    }

    func clear() {
        entries = []
        covers = [:]
        guard !isDemo else { return }
        try? FileManager.default.removeItem(at: Self.folder)
    }

    // MARK: - Demo

    func enterDemo(entries demoEntries: [PlayHistoryEntry], covers demoCovers: [String: NSImage]) {
        guard !isDemo else { return }
        isDemo = true
        saveTask?.cancel()
        savedEntries = entries
        savedCovers = covers
        entries = demoEntries
        covers = demoCovers
    }

    func exitDemo() {
        guard isDemo else { return }
        isDemo = false
        entries = savedEntries
        covers = savedCovers
        savedEntries = []
        savedCovers = [:]
    }

    // MARK: - Storage

    private func trim() {
        guard entries.count > Self.limit else { return }
        let dropped = entries[Self.limit...]
        entries.removeLast(entries.count - Self.limit)
        guard !isDemo else { return }
        for entry in dropped {
            covers[entry.id] = nil
            if let file = entry.artworkFile {
                try? FileManager.default.removeItem(at: Self.folder.appendingPathComponent(file))
            }
        }
    }

    private func load() {
        guard let data = try? Data(contentsOf: Self.fileURL) else { return }
        do {
            entries = try JSONDecoder().decode([PlayHistoryEntry].self, from: data)
        } catch {
            log.error("history unreadable: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Coalesces bursts (a track and its cover land together).
    private func scheduleSave() {
        guard !isDemo else { return }
        saveTask?.cancel()
        let snapshot = entries
        saveTask = Task { [log] in
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled, let data = try? JSONEncoder().encode(snapshot) else { return }
            do {
                try FileManager.default.createDirectory(at: Self.folder, withIntermediateDirectories: true)
                try data.write(to: Self.fileURL, options: .atomic)
            } catch {
                log.error("history not saved: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    private static func fileName(for key: String) -> String {
        var hash: UInt64 = 1469598103934665603
        for byte in key.utf8 {
            hash = (hash ^ UInt64(byte)) &* 1099511628211
        }
        return String(hash, radix: 16) + ".jpg"
    }
}

private extension NSImage {
    /// Square-cropped, downscaled copy for the history covers.
    func thumbnail(side: CGFloat) -> NSImage {
        let target = NSSize(width: side, height: side)
        return NSImage(size: target, flipped: false) { rect in
            let s = self.size
            let edge = min(s.width, s.height)
            let source = NSRect(x: (s.width - edge) / 2, y: (s.height - edge) / 2, width: edge, height: edge)
            self.draw(in: rect, from: source, operation: .copy, fraction: 1)
            return true
        }
    }

    func jpegData() -> Data? {
        guard let tiff = tiffRepresentation, let rep = NSBitmapImageRep(data: tiff) else { return nil }
        return rep.representation(using: .jpeg, properties: [.compressionFactor: 0.8])
    }
}
