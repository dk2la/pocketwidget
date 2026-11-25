# Plan: Settings as a widget module, capsule removed

Decisions from the 2026-11-25 planning session, after release 0.3.0. No
release number is assigned yet. Tick an item when it is done and merged.

## Why

Pocket has two windows today. The capsule at the notch shows live events and
hosts Settings and the welcome tour. The modules live in a separate widget
docked to a screen edge. Opening Settings from the notch is not obvious, so
the capsule goes away and everything lives in the widget.

## Decisions

### Capsule

- [ ] Remove the capsule window completely. There is no switch to bring it
  back.
- [ ] Remove the capsule theme from Settings → Appearance. The widget material
  setting (light, dark, auto) stays.
- [ ] Remove the idle mode setting (invisible / compact) from Settings →
  General.

### Settings module

- [ ] Settings becomes a module with its own icon on the widget strip.
- [ ] It can be reordered like any module, but it cannot be switched off.
- [ ] Its panel opens and closes by the same rules as every other module. The
  close behaviour is not changed in this work.
- [ ] The panel keeps the current layout and the same seven pages: General,
  License, Appearance, Modules, Accounts, Playbooks, Hotkeys. The page list is
  on the left and the selected page fills the space on the right.
- [ ] The Settings panel has its own size, 720×520 by default. It is resized
  with the same grips as other modules and remembered separately from the
  shared module panel size.
- [ ] When the panel is narrower than 560, the page list moves to the top and
  becomes a single-row, scrollable strip of pages with icons and labels.
- [ ] ⌃⌥M and "Settings…" in the menu bar menu open the Settings module. If the
  widget is minimized, they restore it first.

### Welcome tour

- [ ] The tour opens in the widget panel, not in the capsule.
- [ ] It uses the Settings panel size, not a size of its own.

### Live events

The five events are charging, audio device, volume, timer finished and
playbook ran.

- [ ] An event shows as a small pill that slides out of the widget strip
  towards the centre of the screen for 2.5 seconds, with the same content the
  capsule shows today.
- [ ] The pill also shows when the widget is minimized.
- [ ] An event is skipped while a module panel is open.
- [ ] The pill does not depend on which modules are enabled. "Timer finished"
  shows even if the Timer module is off.

### Timer and music indicators

These replace the compact idle mode.

- [ ] A running timer shows the remaining time on the Timer icon.
- [ ] Playing music shows a small live indicator on the Music icon.
- [ ] The indicators show whenever the module is enabled. There is no setting
  for them, and a disabled module shows none.

## Postponed

- **Menu bar icon.** It is the system symbol `capsule.portrait.fill` today. A
  new, more interesting icon is wanted, but the design is not decided.

## Where the code is

- Capsule: `Sources/Core/Capsule*.swift`. `CapsulePanel` is also the window
  class of the widget, so it has to stay or be renamed.
- Widget: `Sources/Core/WidgetWindowController.swift`,
  `WidgetRootView.swift`, `WidgetGeometry.swift`.
- Modules: `Sources/Core/ModuleTab.swift`, `ModuleContentView.swift`.
- Settings pages: `Sources/Settings/SettingsView.swift`.
- Live events: `Sources/Modules/LiveEvents/`.
- Stored settings: `Sources/Core/AppSettings.swift`.
- Status item and hotkeys: `Sources/App/AppDelegate.swift`,
  `Sources/Services/HotkeyService.swift`.
