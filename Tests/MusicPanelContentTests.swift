import XCTest

/// The Music panel never shows something the user cannot act on: history
/// lists only songs Pocket can start again, and with no music app usable it
/// offers the providers instead of an empty card.
final class MusicPanelContentTests: XCTestCase {
    private let spotify = MusicProvider.spotify.bundleID
    private let music = MusicProvider.appleMusic.bundleID
    private let chrome = "com.google.Chrome"

    private func entry(_ title: String, source: String, playID: String?) -> PlayHistoryEntry {
        PlayHistoryEntry(
            id: PlayHistoryEntry.key(title: title, artist: "A"), title: title, artist: "A",
            sourceID: source, playID: playID, playCount: 1, lastPlayed: Date(), artworkFile: nil
        )
    }

    // MARK: - History

    func testOnlyPlayerEntriesWithAHandleAreShown() {
        let entries = [
            entry("spotify", source: spotify, playID: "spotify:track:1"),
            entry("browser", source: chrome, playID: nil),
            entry("browser with id", source: chrome, playID: "x"),
            entry("spotify no id", source: spotify, playID: nil),
            entry("music", source: music, playID: "ABC123"),
        ]
        let shown = ReplayableHistory.filter(entries, usableSourceIDs: [spotify, music])
        XCTAssertEqual(shown.map(\.title), ["spotify", "music"])
    }

    func testEntriesOfAnUnusableProviderAreHidden() {
        let entries = [
            entry("spotify", source: spotify, playID: "spotify:track:1"),
            entry("music", source: music, playID: "ABC123"),
        ]
        let shown = ReplayableHistory.filter(entries, usableSourceIDs: [music])
        XCTAssertEqual(shown.map(\.title), ["music"])
    }

    func testOnlyProviderPlaysAreRecorded() {
        XCTAssertTrue(ReplayableHistory.shouldRecord(sourceID: spotify))
        XCTAssertTrue(ReplayableHistory.shouldRecord(sourceID: music))
        XCTAssertFalse(ReplayableHistory.shouldRecord(sourceID: chrome))
    }

    // MARK: - Panel

    func testATrackShowsThePlayer() {
        XCTAssertEqual(MusicPanelContent.decide(hasTrack: true, hasProviderSource: true), .player(withProviders: false))
    }

    func testABrowserTrackWithoutAProviderAlsoOffersProviders() {
        XCTAssertEqual(MusicPanelContent.decide(hasTrack: true, hasProviderSource: false), .player(withProviders: true))
    }

    func testNoTrackAndNoProviderShowsTheChooser() {
        XCTAssertEqual(MusicPanelContent.decide(hasTrack: false, hasProviderSource: false), .providers)
    }

    func testNoTrackWithAProviderIsIdle() {
        XCTAssertEqual(MusicPanelContent.decide(hasTrack: false, hasProviderSource: true), .idle)
    }

    // MARK: - Provider row

    func testProviderStatus() {
        XCTAssertEqual(MusicProviderStatus.of(installed: false, running: false, automationDenied: false), .notInstalled)
        XCTAssertEqual(MusicProviderStatus.of(installed: true, running: false, automationDenied: false), .notRunning)
        XCTAssertEqual(MusicProviderStatus.of(installed: true, running: true, automationDenied: false), .ready)
        XCTAssertEqual(MusicProviderStatus.of(installed: true, running: true, automationDenied: true), .needsPermission)
        XCTAssertEqual(MusicProviderStatus.of(installed: true, running: false, automationDenied: true), .needsPermission)
    }

    func testProviderBundleIDsRoundTrip() {
        for provider in MusicProvider.allCases {
            XCTAssertEqual(MusicProvider(bundleID: provider.bundleID), provider)
        }
        XCTAssertNil(MusicProvider(bundleID: chrome))
    }
}
