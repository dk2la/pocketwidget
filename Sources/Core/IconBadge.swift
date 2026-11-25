import Foundation

/// A live indicator on a strip icon: the Timer icon carries the remaining
/// time while the countdown runs, the Music icon a pulse while a track plays.
/// They replace the capsule's compact idle mode. Time stays in seconds here;
/// the view formats it like the Timer module does.
enum IconBadge: Equatable {
    case timer(remaining: TimeInterval)
    case musicPlaying

    enum TimerState: Equatable {
        case idle
        case running(remaining: TimeInterval)
        case paused(remaining: TimeInterval)
        case finished

        /// `TimerService` resets a finished countdown to its full length,
        /// so finished reads as idle from its fields.
        init(isRunning: Bool, remaining: TimeInterval, duration: TimeInterval) {
            if isRunning {
                self = .running(remaining: remaining)
            } else if remaining < duration {
                self = .paused(remaining: remaining)
            } else {
                self = .idle
            }
        }
    }

    enum PlaybackState: Equatable {
        case playing
        case paused
        case none
    }

    /// Only a running timer and playing music are live; a disabled module
    /// shows nothing, and there is no setting for it.
    static func badge(
        for module: ModuleTab, enabled: Bool, timer: TimerState, playback: PlaybackState
    ) -> IconBadge? {
        guard enabled else { return nil }
        switch module {
        case .timer:
            if case .running(let remaining) = timer { return .timer(remaining: remaining) }
            return nil
        case .media:
            return playback == .playing ? .musicPlaying : nil
        default:
            return nil
        }
    }
}
