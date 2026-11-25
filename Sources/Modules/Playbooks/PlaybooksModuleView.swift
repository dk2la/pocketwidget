import AppKit
import SwiftUI

/// "Playbooks" module: the last-run playbook as a hero card with Run, the
/// rest as one grouped list — symbol, name over a one-line recipe of its
/// steps, a run button — ending in "Add playbook…", which opens the editor
/// right here in the panel. Clicking the hero or a row outside its run
/// button opens the playbook: a hero card with Run and
/// its steps in order, so it is clear what running it will do, Delete, and
/// Edit, which opens the same editor filled with it. With no playbook at all the
/// module is the empty message over "Add playbook…". A quiet register
/// underneath reports failures of the last run.
struct PlaybooksModuleView: View {
    var store: PlaybookStore
    var runner: PlaybookRunner

    /// Playbook that just finished — it shows a checkmark for 3 s.
    @State private var justRanID: UUID?
    /// Where the module is; read through `shown`.
    @State private var route: PlaybooksRoute = .list
    /// Opened playbook whose Delete was clicked once and waits for the
    /// confirming click.
    @State private var confirmingDeleteID: UUID?
    @State private var confirmTask: Task<Void, Never>?
    /// Not observable — re-read on appearance, set by the guide on success.
    @State private var accessibilityTrusted = WindowLayoutService.isTrusted

    /// Some playbook arranges windows, which silently does nothing without
    /// Accessibility — say so where the playbooks are run.
    private var needsAccessibility: Bool {
        !accessibilityTrusted && store.playbooks.contains { playbook in
            playbook.steps.contains { step in
                if case .openApps(_, _, let layout) = step { return layout != .none }
                return false
            }
        }
    }

    /// The route on screen: an opened or edited playbook deleted meanwhile
    /// (in Settings, or by the editor itself) drops back to the list.
    private var shown: PlaybooksRoute {
        route.resolved(existing: store.playbooks.map(\.id))
    }

    private func show(_ route: PlaybooksRoute) {
        withAnimation(.snappy) { self.route = route }
    }

    var body: some View {
        let isEditing = shown.isEditor
        return VStack(spacing: 10) {
            if store.playbooks.isEmpty, !isEditing {
                emptyScreen
            } else {
                screens
            }
            // The editor gets the whole panel: at the smallest size there
            // is no room to spare, and it has its own access hint.
            if !isEditing {
                if needsAccessibility {
                    accessNotice
                }
                if let last = runner.lastRun, !last.result.failures.isEmpty {
                    runRegister(last)
                }
            }
        }
        .onAppear { accessibilityTrusted = WindowLayoutService.isTrusted }
        .onChange(of: runner.lastRun) { _, record in
            guard let record else { return }
            justRanID = record.playbook.id
            Task {
                try? await Task.sleep(for: .seconds(3))
                if justRanID == record.playbook.id, runner.lastRun == record {
                    justRanID = nil
                }
            }
        }
    }

    /// The list with whatever is opened laid over it. The list stays
    /// mounted underneath, so Back finds it at the same scroll position.
    private var screens: some View {
        let shown = shown
        return ZStack {
            list
                .opacity(shown == .list ? 1 : 0)
                .allowsHitTesting(shown == .list)
                .accessibilityHidden(shown != .list)
            switch shown {
            case .list:
                EmptyView()
            case .playbook(let id):
                if let playbook = store.playbooks.first(where: { $0.id == id }) {
                    opened(playbook)
                        .transition(.opacity)
                }
            case .editor(let id):
                editor(for: id)
                    .transition(.opacity)
            }
        }
    }

    // MARK: - Empty

    /// No playbook yet: the empty message, centred in the free space, over
    /// the button that adds the first one.
    private var emptyScreen: some View {
        ModuleEmptyScreen(label: L10n.t(.playNoneTitle), sublabel: L10n.t(.playNoneSub)) {
            ModuleButton(label: L10n.t(.playAdd), kind: .light) {
                show(.editor(nil))
            }
        }
    }

    // MARK: - List

    /// The hero: the last playbook run, else the first one.
    private var featured: Playbook? {
        if let last = runner.lastRun,
           let current = store.playbooks.first(where: { $0.id == last.playbook.id }) {
            return current
        }
        return store.playbooks.first
    }

    private var list: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 18) {
                if let featured {
                    // Like a row: a click outside Run opens the playbook.
                    hero(featured)
                        .contentShape(Rectangle())
                        .onTapGesture { show(.playbook(featured.id)) }
                }
                list(store.playbooks.filter { $0.id != featured?.id })
            }
        }
    }

    private func list(_ playbooks: [Playbook]) -> some View {
        GroupedCard {
            ForEach(playbooks) { playbook in
                row(for: playbook)
            }
            newRow
        }
    }

    /// Run runs the playbook in place; a click anywhere else on the row
    /// opens it.
    private func row(for playbook: Playbook) -> some View {
        let isRunningThis = runner.runningPlaybookID == playbook.id
        let justRan = justRanID == playbook.id
        return HStack(alignment: .center, spacing: 12) {
            IconTile(systemName: playbook.icon)
            VStack(alignment: .leading, spacing: 2) {
                Text(playbook.name)
                    .font(Theme.bodyFont)
                    .fontWeight(.medium)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .foregroundStyle(Theme.textPrimary)
                Text(summary(for: playbook))
                    .font(Theme.subFont)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .foregroundStyle(Theme.textTertiary)
            }
            Spacer(minLength: 0)
            if justRan {
                Image(systemName: "checkmark")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.accent)
                    .transition(.opacity)
            }
            CircleGlassButton(systemName: "play.fill", size: 30, solid: isRunningThis) {
                // Stays enabled during a run so the click is not passed on to
                // the row, which would open the playbook; the runner ignores it.
                runner.run(playbook)
            }
            .opacity(runner.isRunning && !isRunningThis ? 0.5 : 1)
            .help(L10n.t(.asstPlaybookRun))
        }
        .groupedRow(isLast: false)
        .onTapGesture { show(.playbook(playbook.id)) }
        .animation(.easeOut(duration: 0.15), value: justRan)
    }

    // MARK: - Opened playbook

    /// One playbook on its own: Back, Delete and Edit pinned on top, then
    /// the hero card with Run and the steps in order.
    private func opened(_ playbook: Playbook) -> some View {
        let confirming = confirmingDeleteID == playbook.id
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                ModuleButton(label: L10n.t(.playBack), systemName: "chevron.left", height: 28) {
                    show(.list)
                }
                Spacer(minLength: 0)
                ModuleButton(
                    label: confirming ? L10n.t(.calDelete) : nil,
                    systemName: "trash",
                    height: 28,
                    tint: Theme.critical.opacity(0.9)
                ) {
                    deleteTapped(playbook)
                }
                .help(L10n.t(.calDelete))
                .accessibilityLabel(L10n.t(confirming ? .calConfirmDelete : .calDelete))
                // Edit gives up its label while Delete shows one: both do
                // not fit beside Back at the smallest panel size.
                ModuleButton(
                    label: confirming ? nil : L10n.t(.calEdit),
                    systemName: "pencil",
                    height: 28
                ) {
                    show(.editor(playbook.id))
                }
                .help(L10n.t(.calEdit))
            }
            .animation(Theme.stateSpring, value: confirming)
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 18) {
                    hero(playbook)
                    steps(of: playbook)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    /// Delete asks first, as it does in the editor: the first click grows
    /// the trash button a "Delete" label for a few seconds, the second one
    /// deletes and leads back to the list.
    private func deleteTapped(_ playbook: Playbook) {
        confirmTask?.cancel()
        guard confirmingDeleteID == playbook.id else {
            confirmingDeleteID = playbook.id
            confirmTask = Task {
                try? await Task.sleep(for: .seconds(3))
                guard !Task.isCancelled else { return }
                confirmingDeleteID = nil
            }
            return
        }
        confirmingDeleteID = nil
        withAnimation(.snappy) {
            store.remove(playbook)
            route = .list
        }
    }

    // MARK: - Editor

    /// The Settings editor in its panel layout: empty for a new playbook,
    /// filled for an existing one. It works on a draft of its own, so
    /// leaving it any way but Save — Back, or the panel closed by hand —
    /// changes nothing. Done leads back to where it was opened from: the
    /// list after adding, the playbook after editing, the list again when
    /// that playbook was just deleted.
    private func editor(for id: UUID?) -> some View {
        PlaybookEditorView(
            store: store,
            existing: store.playbooks.first { $0.id == id },
            layout: .panel
        ) {
            show(PlaybooksRoute.editor(id).back.resolved(existing: store.playbooks.map(\.id)))
        }
        .id(id)
    }

    // MARK: - Hero

    private func hero(_ playbook: Playbook) -> some View {
        let isRunningThis = runner.runningPlaybookID == playbook.id
        return HeroCard {
            if let last = runner.lastRun, last.playbook.id == playbook.id {
                HStack(spacing: 7) {
                    StatusDot()
                    Text(L10n.f(.playLastRun, Self.timeFormatter.string(from: last.finishedAt)))
                        .heroCaption()
                        .monospacedDigit()
                }
            }
            HStack(spacing: 12) {
                IconTile(systemName: playbook.icon, size: 44)
                VStack(alignment: .leading, spacing: 3) {
                    Text(playbook.name)
                        .font(Theme.heroFont)
                        .lineLimit(1)
                        .foregroundStyle(Theme.textPrimary)
                    Text(summary(for: playbook))
                        .font(Theme.subFont)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .foregroundStyle(Theme.textSecondary)
                }
            }
            HStack(spacing: 4) {
                ForEach(appIDs(of: playbook).prefix(6), id: \.self) { bundleID in
                    if let icon = AppVisuals.icon(for: bundleID) {
                        Image(nsImage: icon)
                            .resizable()
                            .frame(width: 24, height: 24)
                            .help(AppVisuals.name(for: bundleID) ?? bundleID)
                    }
                }
                Spacer(minLength: 0)
                ModuleButton(
                    label: L10n.t(.asstPlaybookRun),
                    systemName: justRanID == playbook.id ? "checkmark" : "play.fill",
                    kind: .accent,
                    height: 34,
                    enabled: !runner.isRunning || isRunningThis
                ) {
                    runner.run(playbook)
                }
            }
        }
    }

    /// Apps the playbook opens, in step order.
    private func appIDs(of playbook: Playbook) -> [String] {
        playbook.steps.flatMap { step -> [String] in
            if case .openApps(_, let bundleIDs, _) = step { return bundleIDs }
            return []
        }
    }

    private static let timeFormatter = DateFormatter(format: "HH:mm")

    // MARK: - Steps

    /// What the playbook does, in the order it does it.
    private func steps(of playbook: Playbook) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title: L10n.t(.playSteps), trailing: "\(playbook.steps.count)")
            if playbook.steps.isEmpty {
                Text(L10n.t(.playEmpty))
                    .font(Theme.subFont)
                    .foregroundStyle(Theme.textTertiary)
                    .padding(.horizontal, 4)
            } else {
                GroupedCard {
                    ForEach(Array(playbook.steps.enumerated()), id: \.element.id) { index, step in
                        stepRow(step, number: index + 1, isLast: index == playbook.steps.count - 1)
                    }
                }
            }
        }
    }

    private func stepRow(_ step: PlaybookStep, number: Int, isLast: Bool) -> some View {
        HStack(alignment: .center, spacing: 12) {
            IconTile(systemName: step.kind.icon)
            VStack(alignment: .leading, spacing: 2) {
                Text(step.kind.title)
                    .font(Theme.bodyFont)
                    .lineLimit(1)
                    .foregroundStyle(Theme.textPrimary)
                if let detail = detail(for: step) {
                    Text(detail)
                        .font(Theme.subFont)
                        .lineLimit(2)
                        .truncationMode(.tail)
                        .foregroundStyle(Theme.textTertiary)
                }
            }
            Spacer(minLength: 8)
            Text("\(number)")
                .font(Theme.subFont)
                .monospacedDigit()
                .foregroundStyle(Theme.textQuaternary)
        }
        .groupedRow(isLast: isLast)
    }

    /// The specifics of a step: which apps and how they are laid out, which
    /// shortcut, how long, which sites.
    private func detail(for step: PlaybookStep) -> String? {
        switch step {
        case .openApps(_, let bundleIDs, let layout):
            var parts: [String] = []
            if !bundleIDs.isEmpty {
                parts.append(bundleIDs.map { AppVisuals.name(for: $0) ?? $0 }.joined(separator: ", "))
            }
            if layout != .none { parts.append(layout.title) }
            return parts.isEmpty ? nil : parts.joined(separator: " · ")
        case .closeOtherApps:
            return nil
        case .runShortcut(_, let name), .setFocus(_, let name):
            return name.isEmpty ? nil : name
        case .startTimer(_, let minutes):
            return L10n.f(.ageMin, minutes)
        case .openURLs(_, let urls):
            let hosts = urls.map { URL(string: $0)?.host ?? $0 }
            return hosts.isEmpty ? nil : hosts.joined(separator: ", ")
        }
    }

    /// "3 apps · Three columns · focus · 25 min" — one token per step.
    private func summary(for playbook: Playbook) -> String {
        var parts: [String] = []
        for step in playbook.steps {
            switch step {
            case .openApps(_, let bundleIDs, let layout):
                parts.append(L10n.f(.playApps, bundleIDs.count))
                if layout != .none { parts.append(layout.title) }
            case .closeOtherApps:
                parts.append(L10n.t(.playCloseRest))
            case .runShortcut(_, let name):
                parts.append(name.isEmpty ? L10n.t(.playStepShortcut) : name)
            case .setFocus:
                parts.append(L10n.t(.playFocus))
            case .startTimer(_, let minutes):
                parts.append(L10n.f(.ageMin, minutes))
            case .openURLs(_, let urls):
                parts.append(L10n.f(.playLinks, urls.count))
            }
        }
        return parts.isEmpty ? L10n.t(.playEmpty) : parts.joined(separator: " · ")
    }

    /// The last row of the list: opens the editor on a new playbook.
    private var newRow: some View {
        AddRow(label: L10n.t(.playAdd)) {
            show(.editor(nil))
        }
    }

    // MARK: - Access notice

    private var accessNotice: some View {
        HStack(spacing: 10) {
            Image(systemName: "macwindow")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Theme.accent)
            Text(L10n.t(.playAccessNeeded))
                .font(Theme.subFont)
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            ModuleButton(label: L10n.t(.obAllowAccess), kind: .accent, height: 28) {
                WindowLayoutService.requestAccess {
                    accessibilityTrusted = true
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Theme.cardFill, in: RoundedRectangle(cornerRadius: Theme.groupRadius, style: .continuous))
    }

    // MARK: - Run register

    /// "«Работа» — закрыто 6, ошибок 1". Shown only when something failed:
    /// success already has its checkmark in the row.
    private func runRegister(_ last: PlaybookRunner.RunRecord) -> some View {
        HStack(spacing: 10) {
            Circle()
                .fill(Theme.critical)
                .frame(width: 5, height: 5)
            Text(registerText(last))
                .font(Theme.subFont)
                .lineLimit(1)
                .foregroundStyle(Theme.textSecondary)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Theme.cardFill, in: RoundedRectangle(cornerRadius: Theme.groupRadius, style: .continuous))
    }

    private func registerText(_ last: PlaybookRunner.RunRecord) -> String {
        var parts: [String] = []
        if last.result.closed > 0 { parts.append(L10n.f(.playClosed, last.result.closed)) }
        if last.result.opened > 0 { parts.append(L10n.f(.playOpened, last.result.opened)) }
        if !last.result.failures.isEmpty { parts.append(L10n.f(.playErrors, last.result.failures.count)) }
        let detail = parts.isEmpty ? L10n.t(.playDone) : parts.joined(separator: ", ")
        return "«\(last.playbook.name)» — \(detail)"
    }
}
