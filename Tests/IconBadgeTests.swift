import XCTest

/// A running timer shows its remaining time on the Timer icon and playing
/// music a live indicator on the Music icon. Anything else shows nothing.
final class IconBadgeTests: XCTestCase {
    // MARK: - Timer

    func testRunningTimerShowsRemainingTime() {
        let badge = IconBadge.badge(for: .timer, enabled: true, timer: .running(remaining: 754), playback: .none)
        XCTAssertEqual(badge, .timer(remaining: 754))
    }

    func testPausedTimerShowsNothing() {
        let badge = IconBadge.badge(for: .timer, enabled: true, timer: .paused(remaining: 754), playback: .none)
        XCTAssertNil(badge)
    }

    func testFinishedTimerShowsNothing() {
        XCTAssertNil(IconBadge.badge(for: .timer, enabled: true, timer: .finished, playback: .none))
        XCTAssertNil(IconBadge.badge(for: .timer, enabled: true, timer: .idle, playback: .none))
    }

    func testDisabledTimerShowsNothing() {
        let badge = IconBadge.badge(for: .timer, enabled: false, timer: .running(remaining: 754), playback: .none)
        XCTAssertNil(badge)
    }

    // MARK: - Music

    func testPlayingMusicShowsLiveIndicator() {
        let badge = IconBadge.badge(for: .media, enabled: true, timer: .idle, playback: .playing)
        XCTAssertEqual(badge, .musicPlaying)
    }

    func testPausedMusicShowsNothing() {
        XCTAssertNil(IconBadge.badge(for: .media, enabled: true, timer: .idle, playback: .paused))
        XCTAssertNil(IconBadge.badge(for: .media, enabled: true, timer: .idle, playback: .none))
    }

    func testDisabledMusicShowsNothing() {
        XCTAssertNil(IconBadge.badge(for: .media, enabled: false, timer: .idle, playback: .playing))
    }

    // MARK: - Other modules

    func testOtherModulesNeverShowLiveBadges() {
        for tab in [ModuleTab.notes, .email, .calendar] {
            XCTAssertNil(IconBadge.badge(for: tab, enabled: true, timer: .running(remaining: 60), playback: .playing))
        }
    }

    // MARK: - Timer state from the service's fields

    func testTimerStateFromServiceFields() {
        XCTAssertEqual(IconBadge.TimerState(isRunning: true, remaining: 900, duration: 1500), .running(remaining: 900))
        XCTAssertEqual(IconBadge.TimerState(isRunning: false, remaining: 900, duration: 1500), .paused(remaining: 900))
        // A finished countdown resets to its full length, the same as idle.
        XCTAssertEqual(IconBadge.TimerState(isRunning: false, remaining: 1500, duration: 1500), .idle)
    }
}
