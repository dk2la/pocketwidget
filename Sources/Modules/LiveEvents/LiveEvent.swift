import Foundation

/// Transient system events, shown in the event pill beside the widget strip.
enum LiveEvent: Equatable {
    case charging(percent: Int, plugged: Bool)
    case audioDevice(name: String)
    case volume(level: Double)
    case timerFinished
    case playbookRan(name: String)
}
