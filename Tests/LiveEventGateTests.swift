import XCTest

/// When a live event may slide out of the strip: never over an open module
/// panel or the lock screen; folding the widget away does not hide events.
/// Which modules are enabled is not an input at all — "timer finished"
/// shows even with the Timer module off.
final class LiveEventGateTests: XCTestCase {
    private let events: [LiveEvent] = [
        .charging(percent: 100, plugged: true),
        .audioDevice(name: "AirPods Pro"),
        .volume(level: 0.4),
        .timerFinished,
        .playbookRan(name: "Morning"),
    ]

    func testShowsEveryEventOnAnIdleStrip() {
        for event in events {
            XCTAssertTrue(LiveEventGate.shouldShow(event, panelOpen: false, locked: false, minimized: false), "\(event)")
        }
    }

    func testShowsWhenMinimized() {
        for event in events {
            XCTAssertTrue(LiveEventGate.shouldShow(event, panelOpen: false, locked: false, minimized: true), "\(event)")
        }
    }

    func testSkipsWhileAPanelIsOpen() {
        for event in events {
            XCTAssertFalse(LiveEventGate.shouldShow(event, panelOpen: true, locked: false, minimized: false), "\(event)")
        }
    }

    func testSkipsWhileLocked() {
        for event in events {
            XCTAssertFalse(LiveEventGate.shouldShow(event, panelOpen: false, locked: true, minimized: false), "\(event)")
            XCTAssertFalse(LiveEventGate.shouldShow(event, panelOpen: false, locked: true, minimized: true), "\(event)")
        }
    }
}
