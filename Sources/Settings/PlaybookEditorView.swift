import AppKit
import SwiftUI

/// Editor of a single playbook: name and icon on top, then the ordered list
/// of steps — one card each with its own fields, reorder and remove
/// controls — and an "Add step" menu. One editor for both places a playbook
/// is made: the Settings page and the Playbooks module's panel, which is
/// narrower and so gets the `panel` layout. It works on a draft; the store
/// changes only on Save and Delete.
struct PlaybookEditorView: View {
    /// How the editor is laid out for the place it is shown in.
    enum Layout {
        /// Settings: a wide page, labels beside the fields, actions in a
        /// row at the bottom.
        case page
        /// The module's panel, down to its smallest size: Back, Delete and Save
        /// pinned on top, everything else stacked in one scrolling column.
        case panel
    }

    var store: PlaybookStore
    var layout: Layout
    /// Called once the editor is finished with: saved, cancelled or deleted.
    let onDone: () -> Void

    @State private var draft: PlaybookDraft
    @State private var apps: [InstalledApp] = []
    @State private var shortcuts: [String] = []
    /// Re-read when the app comes back to front — the user may have just
    /// flipped the switch in System Settings.
    @State private var accessibilityTrusted = false
    /// Delete was clicked once and waits for the confirming click.
    @State private var confirmingDelete = false
    @State private var confirmTask: Task<Void, Never>?

    /// `existing == nil` means "create new".
    init(store: PlaybookStore, existing: Playbook?, layout: Layout = .page, onDone: @escaping () -> Void) {
        self.store = store
        self.layout = layout
        self.onDone = onDone
        _draft = State(initialValue: PlaybookDraft(editing: existing))
    }

    private static let icons = [
        "bolt.fill", "hammer.fill", "film.fill", "gamecontroller.fill",
        "book.fill", "moon.zzz.fill", "cup.and.saucer.fill", "paintbrush.fill",
    ]

    private var isPanel: Bool { layout == .panel }

    var body: some View {
        VStack(spacing: 0) {
            if isPanel {
                panelBar
                    .padding(.bottom, 10)
            }
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: isPanel ? 14 : 18) {
                    identitySection
                    stepsSection
                }
                // The panel already insets its module.
                .padding(isPanel ? 0 : 20)
            }
            if !isPanel {
                Hairline(color: Palette.hairline)
                actionRow
                    .padding(16)
            }
        }
        // Sized by the page or panel it fills, not by itself.
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Palette.panel)
        .task {
            apps = await AppCatalog.discover()
        }
        .task {
            shortcuts = await ShortcutsCatalog.installedShortcuts()
        }
        .onAppear {
            accessibilityTrusted = WindowLayoutService.isTrusted
            // An editor in the widget keeps its panel open: the cursor
            // wanders while typing, and granting access leads out to
            // System Settings. Unsaved input must not vanish with a panel
            // that shut by itself; the close button and the tabs still work.
            if isPanel { PanelHold.shared.begin() }
        }
        // Settings switches the layout live as its panel is resized.
        .onChange(of: isPanel) { _, nowPanel in
            if nowPanel { PanelHold.shared.begin() } else { PanelHold.shared.end() }
        }
        .onDisappear {
            if isPanel { PanelHold.shared.end() }
            confirmTask?.cancel()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            accessibilityTrusted = WindowLayoutService.isTrusted
        }
    }

    // MARK: - Name + icon

    @ViewBuilder
    private var identitySection: some View {
        if isPanel {
            // No room for a label column: the placeholder names the field.
            VStack(alignment: .leading, spacing: 8) {
                PaletteTextField(placeholder: L10n.t(.playName), text: $draft.playbook.name)
                iconChoices
            }
        } else {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 12) {
                    InstrumentLabel(L10n.t(.playName), color: Palette.ink40)
                        .frame(width: 60, alignment: .leading)
                    PaletteTextField(placeholder: L10n.t(.playName), text: $draft.playbook.name)
                }
                HStack(spacing: 12) {
                    InstrumentLabel(L10n.t(.playIcon), color: Palette.ink40)
                        .frame(width: 60, alignment: .leading)
                    iconChoices
                }
            }
        }
    }

    /// One row of symbols. In the panel the tiles share its whole width.
    private var iconChoices: some View {
        HStack(spacing: 6) {
            ForEach(Self.icons, id: \.self) { icon in
                let isActive = draft.playbook.icon == icon
                Button {
                    draft.playbook.icon = icon
                } label: {
                    Image(systemName: icon)
                        .font(Theme.iconSmallFont)
                        .foregroundStyle(isActive ? Palette.accent : Palette.ink60)
                        .frame(minWidth: 22, maxWidth: isPanel ? .infinity : 30, minHeight: 26, maxHeight: 26)
                        .paletteTile(isActive: isActive)
                }
                .buttonStyle(PressableStyle())
            }
        }
    }

    // MARK: - Steps

    private var stepsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            InstrumentLabel(L10n.t(.playSteps), color: Palette.ink40)
            if draft.playbook.steps.isEmpty {
                Text(L10n.t(.playNoSteps))
                    .font(Theme.subFont)
                    .foregroundStyle(Palette.ink40)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.vertical, 6)
            }
            ForEach($draft.playbook.steps) { $step in
                let index = draft.playbook.steps.firstIndex { $0.id == step.id } ?? 0
                PlaybookStepCard(
                    step: $step,
                    compact: isPanel,
                    apps: apps,
                    shortcuts: shortcuts,
                    accessibilityTrusted: accessibilityTrusted,
                    canMoveUp: index > 0,
                    canMoveDown: index < draft.playbook.steps.count - 1,
                    onMoveUp: { draft.moveStep(step.id, by: -1) },
                    onMoveDown: { draft.moveStep(step.id, by: 1) },
                    onRemove: { draft.removeStep(step.id) },
                    onGrantAccess: {
                        WindowLayoutService.requestAccess {
                            accessibilityTrusted = true
                        }
                    }
                )
            }
            addStepMenu
                .padding(.top, 2)
        }
    }

    private var addStepMenu: some View {
        Menu {
            ForEach(PlaybookStep.Kind.allCases, id: \.self) { kind in
                Button {
                    draft.playbook.steps.append(kind.makeStep())
                } label: {
                    Label(kind.title, systemImage: kind.icon)
                }
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "plus")
                    .font(.system(size: 10, weight: .semibold))
                Text(L10n.t(.playAddStep))
                    .font(Theme.subFont)
            }
            .foregroundStyle(Palette.accent)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Palette.accentWash, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            .contentShape(Rectangle())
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
    }

    // MARK: - Actions

    /// Panel layout: Back where the opened playbook has it, Save across
    /// from it. Both stay put while the fields scroll.
    private var panelBar: some View {
        HStack(spacing: 8) {
            // Back gives up its label while Delete shows one: all three do
            // not fit at the smallest panel size.
            ModuleButton(
                label: confirmingDelete ? nil : L10n.t(.playBack),
                systemName: "chevron.left",
                height: 28
            ) {
                onDone()
            }
            .help(L10n.t(.playBack))
            Spacer(minLength: 0)
            if !draft.isNew {
                // The same trash button the opened playbook carries.
                ModuleButton(
                    label: confirmingDelete ? L10n.t(.calDelete) : nil,
                    systemName: "trash",
                    height: 28,
                    tint: Theme.critical.opacity(0.9)
                ) {
                    deleteTapped()
                }
                .help(L10n.t(.calDelete))
                .accessibilityLabel(L10n.t(confirmingDelete ? .calConfirmDelete : .calDelete))
            }
            ModuleButton(label: L10n.t(.calSave), kind: .accent, height: 28, enabled: draft.canSave) {
                save()
            }
        }
        .animation(Theme.stateSpring, value: confirmingDelete)
    }

    /// Page layout: everything in one row under the fields.
    private var actionRow: some View {
        HStack(spacing: 10) {
            if !draft.isNew {
                deleteButton
            }
            Spacer(minLength: 0)
            PaletteButton(L10n.t(.mailCancel), color: Palette.ink60) {
                onDone()
            }
            .keyboardShortcut(.cancelAction)
            PaletteButton(L10n.t(.calSave), filled: true) {
                save()
            }
            .keyboardShortcut(.defaultAction)
            .disabled(!draft.canSave)
            .opacity(draft.canSave ? 1 : 0.4)
        }
    }

    /// Delete asks first: the first click turns it into "Confirm delete"
    /// (the trash button of the panel grows a label instead) for a few
    /// seconds, the second one deletes.
    private var deleteButton: some View {
        PaletteButton(
            confirmingDelete ? L10n.t(.calConfirmDelete) : L10n.t(.calDelete),
            color: Theme.critical.opacity(0.9)
        ) {
            deleteTapped()
        }
        .animation(Theme.stateSpring, value: confirmingDelete)
    }

    private func deleteTapped() {
        confirmTask?.cancel()
        guard confirmingDelete else {
            confirmingDelete = true
            confirmTask = Task {
                try? await Task.sleep(for: .seconds(3))
                guard !Task.isCancelled else { return }
                confirmingDelete = false
            }
            return
        }
        confirmingDelete = false
        draft.delete(from: store)
        onDone()
    }

    private func save() {
        guard draft.save(to: store) else { return }
        onDone()
    }
}

// MARK: - Step card

/// One step: kind label with move/remove controls on top, the kind's
/// fields underneath. Bindings into the enum payload are rebuilt per
/// field so the card never has to know the step's index.
private struct PlaybookStepCard: View {
    @Binding var step: PlaybookStep
    /// Narrow (panel) layout: rows that would not fit side by side stack.
    let compact: Bool
    let apps: [InstalledApp]
    let shortcuts: [String]
    let accessibilityTrusted: Bool
    let canMoveUp: Bool
    let canMoveDown: Bool
    let onMoveUp: () -> Void
    let onMoveDown: () -> Void
    let onRemove: () -> Void
    let onGrantAccess: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: step.kind.icon)
                    .font(Theme.iconSmallFont)
                    .foregroundStyle(Palette.accent)
                    .frame(width: 18)
                Text(step.kind.title)
                    .font(Theme.bodyFont)
                    .fontWeight(.medium)
                    .foregroundStyle(Palette.ink)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                control("chevron.up", enabled: canMoveUp, action: onMoveUp)
                control("chevron.down", enabled: canMoveDown, action: onMoveDown)
                control("xmark", enabled: true, action: onRemove)
            }
            fields
        }
        .padding(compact ? 10 : 12)
        .background(Palette.desk, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .stroke(Palette.hairline, lineWidth: 1)
        )
    }

    private func control(_ symbol: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Palette.ink60)
                .frame(width: 22, height: 22)
                .background(Palette.raised, in: RoundedRectangle(cornerRadius: 5))
                .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle())
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.3)
    }

    @ViewBuilder
    private var fields: some View {
        switch step {
        case .openApps:
            AppPickerView(apps: apps, selected: bundleIDs)
            layoutPicker
        case .closeOtherApps:
            EmptyView()
        case .runShortcut:
            shortcutPicker(shortcutName)
        case .setFocus:
            shortcutPicker(focusShortcutName)
        case .startTimer:
            HStack(spacing: 8) {
                PaletteTextField(placeholder: L10n.t(.playMinutes), text: minutesText)
                    .frame(width: 90)
                Text(L10n.t(.playMinutes).lowercased())
                    .font(Theme.subFont)
                    .foregroundStyle(Palette.ink40)
            }
        case .openURLs:
            urlsEditor
        }
    }

    // MARK: Layout

    private var layoutPicker: some View {
        VStack(alignment: .leading, spacing: 6) {
            if compact {
                // Caption over the tiles, which share the card's width.
                HStack(spacing: 10) {
                    layoutCaption
                }
                layoutTiles
            } else {
                HStack(spacing: 10) {
                    layoutCaption
                    layoutTiles
                }
            }
            if layout.wrappedValue != .none, !accessibilityTrusted {
                if compact {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            layoutHintIcon
                            layoutHintText
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        PaletteButton(L10n.t(.playGrantAccess), vPad: 4, action: onGrantAccess)
                    }
                } else {
                    HStack(spacing: 8) {
                        layoutHintIcon
                        layoutHintText
                            .lineLimit(1)
                            .truncationMode(.tail)
                        Spacer(minLength: 0)
                        PaletteButton(L10n.t(.playGrantAccess), action: onGrantAccess)
                    }
                }
            }
        }
    }

    /// "Layout" on the left, the chosen arrangement's name on the right.
    @ViewBuilder
    private var layoutCaption: some View {
        Text(L10n.t(.playLayout))
            .font(Theme.subFont)
            .foregroundStyle(Palette.ink60)
        Spacer(minLength: 0)
        Text(layout.wrappedValue.title)
            .font(Theme.subFont)
            .foregroundStyle(Palette.ink40)
            .lineLimit(1)
    }

    private var layoutTiles: some View {
        HStack(spacing: 4) {
            ForEach(WindowLayout.allCases) { option in
                let isActive = layout.wrappedValue == option
                Button {
                    layout.wrappedValue = option
                } label: {
                    Image(systemName: option.icon)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(isActive ? Palette.accent : Palette.ink60)
                        .frame(minWidth: 28, maxWidth: compact ? .infinity : 28, minHeight: 24, maxHeight: 24)
                        .paletteTile(isActive: isActive)
                }
                .buttonStyle(PressableStyle())
                .help(option.title)
            }
        }
    }

    private var layoutHintIcon: some View {
        Image(systemName: "exclamationmark.triangle")
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(Theme.selection)
    }

    private var layoutHintText: some View {
        Text(L10n.t(.playLayoutHint))
            .font(Theme.subFont)
            .foregroundStyle(Palette.ink60)
    }

    // MARK: Shortcut

    /// Menu over the installed shortcuts plus a free-text field — the CLI
    /// list can lag behind a shortcut created a moment ago.
    private func shortcutPicker(_ name: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Menu {
                if shortcuts.isEmpty {
                    Text("—")
                }
                ForEach(shortcuts, id: \.self) { shortcut in
                    Button(shortcut) {
                        name.wrappedValue = shortcut
                    }
                }
            } label: {
                HStack(spacing: 6) {
                    Text(name.wrappedValue.isEmpty ? L10n.t(.playChooseShortcut) : name.wrappedValue)
                        .font(Theme.bodyFont)
                        .foregroundStyle(name.wrappedValue.isEmpty ? Palette.ink40 : Palette.ink)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(Palette.ink40)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Palette.raised, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                .contentShape(Rectangle())
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
            PaletteTextField(placeholder: L10n.t(.playShortcutName), text: name)
        }
    }

    // MARK: URLs

    private var urlsEditor: some View {
        ZStack(alignment: .topLeading) {
            TextEditor(text: urlsText)
                .font(Theme.bodyFont)
                .foregroundStyle(Palette.ink)
                .scrollContentBackground(.hidden)
                .padding(.horizontal, 6)
                .padding(.vertical, 4)
                .frame(height: 84)
                .background(Palette.raised, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            if urlsText.wrappedValue.isEmpty {
                Text(L10n.t(.playURLsHint))
                    .font(Theme.bodyFont)
                    .foregroundStyle(Palette.ink40)
                    .padding(.horizontal, 11)
                    .padding(.vertical, 5)
                    .allowsHitTesting(false)
            }
        }
    }

    // MARK: Payload bindings

    /// Binding into one case's payload: `get` reads it (nil for another
    /// case), `set` rebuilds the step around the new value.
    private func payload<T>(
        _ fallback: T,
        get: @escaping (PlaybookStep) -> T?,
        set: @escaping (PlaybookStep, T) -> PlaybookStep?
    ) -> Binding<T> {
        Binding(get: { get(step) ?? fallback }, set: { if let next = set(step, $0) { step = next } })
    }

    private var bundleIDs: Binding<[String]> {
        payload([]) {
            if case .openApps(_, let ids, _) = $0 { ids } else { nil }
        } set: {
            if case .openApps(let id, _, let layout) = $0 { .openApps(id: id, bundleIDs: $1, layout: layout) } else { nil }
        }
    }

    private var layout: Binding<WindowLayout> {
        payload(.none) {
            if case .openApps(_, _, let layout) = $0 { layout } else { nil }
        } set: {
            if case .openApps(let id, let ids, _) = $0 { .openApps(id: id, bundleIDs: ids, layout: $1) } else { nil }
        }
    }

    private var shortcutName: Binding<String> {
        payload("") {
            if case .runShortcut(_, let name) = $0 { name } else { nil }
        } set: {
            if case .runShortcut(let id, _) = $0 { .runShortcut(id: id, name: $1) } else { nil }
        }
    }

    private var focusShortcutName: Binding<String> {
        payload("") {
            if case .setFocus(_, let name) = $0 { name } else { nil }
        } set: {
            if case .setFocus(let id, _) = $0 { .setFocus(id: id, shortcutName: $1) } else { nil }
        }
    }

    private var minutesText: Binding<String> {
        payload("") {
            if case .startTimer(_, let minutes) = $0, minutes > 0 { String(minutes) } else { nil }
        } set: {
            if case .startTimer(let id, _) = $0 { .startTimer(id: id, minutes: Int($1.filter(\.isNumber)) ?? 0) } else { nil }
        }
    }

    /// Lines map straight to entries; empties survive while typing and
    /// are dropped on save.
    private var urlsText: Binding<String> {
        payload("") {
            if case .openURLs(_, let urls) = $0 { urls.joined(separator: "\n") } else { nil }
        } set: {
            if case .openURLs(let id, _) = $0 { .openURLs(id: id, urls: $1.components(separatedBy: "\n")) } else { nil }
        }
    }
}

// MARK: - Shared controls

/// Plain text field in the settings "input box" look.
private struct PaletteTextField: View {
    let placeholder: String
    @Binding var text: String

    var body: some View {
        TextField(placeholder, text: $text)
            .textFieldStyle(.plain)
            .font(Theme.bodyFont)
            .foregroundStyle(Palette.ink)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Palette.raised, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
    }
}

/// Multi-select app picker: search, source filter chips, the list with
/// chosen apps floated to the top, and a bundle-ID escape hatch for
/// anything Spotlight cannot see.
private struct AppPickerView: View {
    let apps: [InstalledApp]
    @Binding var selected: [String]

    @State private var filter = ""
    @State private var manualBundleID = ""
    /// Empty means "no source filter" — show everything.
    @State private var sources: Set<AppSource> = []

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 11))
                    .foregroundStyle(Palette.ink40)
                TextField(L10n.t(.playSearchApps), text: $filter)
                    .textFieldStyle(.plain)
                    .font(Theme.bodyFont)
                    .foregroundStyle(Palette.ink)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Palette.raised, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            sourceChips
            if apps.isEmpty {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("…")
                        .font(Theme.subFont)
                        .foregroundStyle(Palette.ink40)
                }
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, 20)
            } else {
                ScrollView(.vertical) {
                    LazyVStack(alignment: .leading, spacing: 1) {
                        ForEach(filtered) { app in
                            row(app)
                        }
                    }
                    .padding(4)
                }
                .frame(height: 150)
                .background(Palette.raised.opacity(0.5), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                Text("\(filtered.count) / \(apps.count) · " + L10n.f(.playSelectedCount, selected.count))
                    .font(Theme.subFont)
                    .foregroundStyle(Palette.ink40)
                    .lineLimit(1)
            }
            HStack(spacing: 8) {
                PaletteTextField(placeholder: L10n.t(.playAddBundleID), text: $manualBundleID)
                    .onSubmit(addManual)
                Button(action: addManual) {
                    Image(systemName: "plus")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Palette.accent)
                        .frame(width: 26, height: 26)
                        .background(Palette.accentWash, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                        .contentShape(Rectangle())
                }
                .buttonStyle(PressableStyle())
                .disabled(manualBundleID.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
    }

    /// One row where it fits (Settings), two in the narrow panel.
    private var sourceChips: some View {
        let all = AppSource.allCases
        let half = (all.count + 1) / 2
        return ViewThatFits(in: .horizontal) {
            chipRow(all)
            VStack(alignment: .leading, spacing: 6) {
                chipRow(Array(all.prefix(half)))
                chipRow(Array(all.dropFirst(half)))
            }
        }
    }

    private func chipRow(_ shown: [AppSource]) -> some View {
        HStack(spacing: 6) {
            ForEach(shown) { source in
                let isOn = sources.contains(source)
                Button {
                    if isOn {
                        sources.remove(source)
                    } else {
                        sources.insert(source)
                    }
                } label: {
                    Text(source.title)
                        .font(Theme.captionFont)
                        .lineLimit(1)
                        .foregroundStyle(isOn ? Palette.accent : Palette.ink60)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(isOn ? Palette.accentWash : Palette.raised, in: Capsule())
                        .overlay(Capsule().stroke(isOn ? Palette.accent.opacity(0.5) : Color.clear, lineWidth: 1))
                        .contentShape(Capsule())
                }
                .buttonStyle(PressableStyle())
            }
            Spacer(minLength: 0)
        }
    }

    private var filtered: [InstalledApp] {
        let chosen = Set(selected)
        var matching = apps
        if !sources.isEmpty {
            matching = matching.filter { sources.contains($0.source) }
        }
        if !filter.isEmpty {
            matching = matching.filter { $0.name.localizedCaseInsensitiveContains(filter) }
        }
        // Selected apps float to the top so choices stay visible.
        return matching.sorted {
            (chosen.contains($0.id) ? 0 : 1, $0.name) < (chosen.contains($1.id) ? 0 : 1, $1.name)
        }
    }

    private func row(_ app: InstalledApp) -> some View {
        let isSelected = selected.contains(app.id)
        return Button {
            if isSelected {
                selected.removeAll { $0 == app.id }
            } else {
                selected.append(app.id)
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 12))
                    .foregroundStyle(isSelected ? Palette.accent : Palette.ink40)
                if let icon = AppVisuals.icon(for: app.id) {
                    Image(nsImage: icon)
                        .resizable()
                        .frame(width: 16, height: 16)
                }
                Text(app.name)
                    .font(Theme.bodyFont)
                    .foregroundStyle(Palette.ink)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func addManual() {
        let trimmed = manualBundleID.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        if !selected.contains(trimmed) {
            selected.append(trimmed)
        }
        manualBundleID = ""
    }
}

struct InstalledApp: Identifiable, Equatable, Sendable {
    let id: String // bundle ID
    let name: String
    let source: AppSource
}

/// Where an app lives — the noise filter: user-facing apps sit in
/// /Applications and ~/Applications, preinstalled and vendor bundles
/// elsewhere.
enum AppSource: String, CaseIterable, Identifiable, Sendable {
    case applications
    case user
    case system
    case other

    var id: String { rawValue }

    var title: String {
        switch self {
        case .applications: "Applications"
        case .user: "~/Applications"
        case .system: "System"
        case .other: "Other"
        }
    }

    static func categorize(path: String, home: String) -> AppSource {
        if path.hasPrefix("\(home)/Applications/") { return .user }
        if path.hasPrefix("/Applications/") { return .applications }
        if path.hasPrefix("/System/") || path.hasPrefix("/Library/Apple/") { return .system }
        return .other
    }
}

/// Finds every installed application the way Launchpad does — via Spotlight —
/// with a directory scan as fallback for machines with indexing disabled.
enum AppCatalog {
    static func discover() async -> [InstalledApp] {
        var byBundleID: [String: (app: InstalledApp, path: String)] = [:]
        let home = FileManager.default.homeDirectoryForCurrentUser.path

        func register(path: String) {
            guard path.hasSuffix(".app"),
                  !path.contains(".app/"),               // helpers inside bundles
                  !path.contains("/Library/Developer/"), // simulators, previews
                  !path.hasPrefix("/Volumes/")
            else { return }
            guard let bundle = Bundle(path: path), let bundleID = bundle.bundleIdentifier else { return }
            let name = FileManager.default.displayName(atPath: path)
                .replacingOccurrences(of: ".app", with: "")
            // Prefer the /Applications copy when duplicates exist.
            if let existing = byBundleID[bundleID],
               existing.path.hasPrefix("/Applications"), !path.hasPrefix("/Applications") {
                return
            }
            byBundleID[bundleID] = (
                InstalledApp(
                    id: bundleID,
                    name: name,
                    source: AppSource.categorize(path: path, home: home)
                ),
                path
            )
        }

        for path in await spotlightPaths() {
            register(path: path)
        }
        for path in directoryScanPaths() {
            register(path: path)
        }

        return byBundleID.values
            .map(\.app)
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private static func spotlightPaths() async -> [String] {
        await Process.outputLines("/usr/bin/mdfind", ["kMDItemContentTypeTree == 'com.apple.application-bundle'"])
    }

    /// One level deep over the standard locations — enough to catch
    /// /Applications subfolders and ~/Applications when Spotlight is off.
    private static func directoryScanPaths() -> [String] {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let roots = [
            "/Applications",
            "/System/Applications",
            "/System/Applications/Utilities",
            "\(home)/Applications",
        ]
        var paths: [String] = []
        for root in roots {
            let entries = (try? FileManager.default.contentsOfDirectory(atPath: root)) ?? []
            for entry in entries {
                let full = "\(root)/\(entry)"
                if entry.hasSuffix(".app") {
                    paths.append(full)
                } else {
                    // Vendor subfolders like /Applications/Utilities.
                    let nested = (try? FileManager.default.contentsOfDirectory(atPath: full)) ?? []
                    paths.append(contentsOf: nested.filter { $0.hasSuffix(".app") }.map { "\(full)/\($0)" })
                }
            }
        }
        return paths
    }
}
