import AppKit
import SwiftUI

/// Icons and display names of the apps a playbook opens — the fastest way
/// to tell rows apart at a glance. Looked up once per bundle id, cached for
/// the app's lifetime (workspace lookups touch the disk).
@MainActor
enum AppVisuals {
    private static var icons: [String: NSImage?] = [:]
    private static var names: [String: String?] = [:]

    static func icon(for bundleID: String) -> NSImage? {
        if let cached = icons[bundleID] { return cached }
        let image = url(for: bundleID).map { NSWorkspace.shared.icon(forFile: $0.path) }
        icons[bundleID] = image
        return image
    }

    static func name(for bundleID: String) -> String? {
        if let cached = names[bundleID] { return cached }
        let name = url(for: bundleID).map {
            FileManager.default.displayName(atPath: $0.path)
                .replacingOccurrences(of: ".app", with: "")
        }
        names[bundleID] = name
        return name
    }

    private static func url(for bundleID: String) -> URL? {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
    }
}

/// "Playbooks" module: every playbook in one grouped list — symbol, name
/// over a one-line recipe of its steps, a run button — ending in "Add
/// playbook…", which opens the editor in Settings. Clicking a row outside
/// its run button opens the playbook: a hero card with Run and its steps in
/// order, so it is clear what running it will do. With no playbook at all
/// the key pad device stands over the empty message. A quiet register
/// underneath reports failures of the last run.
struct PlaybooksModuleView: View {
    var store: PlaybookStore
    var runner: PlaybookRunner

    /// Playbook that just finished — it shows a checkmark for 3 s.
    @State private var justRanID: UUID?
    /// Where the module is; read through `shown`.
    @State private var route: PlaybooksRoute = .list
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

    /// The route on screen: an opened playbook deleted meanwhile in
    /// Settings drops back to the list.
    private var shown: PlaybooksRoute {
        route.resolved(existing: store.playbooks.map(\.id))
    }

    private func show(_ route: PlaybooksRoute) {
        withAnimation(.snappy) { self.route = route }
    }

    var body: some View {
        VStack(spacing: 10) {
            if store.playbooks.isEmpty {
                emptyScreen
            } else {
                screens
            }
            if needsAccessibility {
                accessNotice
            }
            if let last = runner.lastRun, !last.result.failures.isEmpty {
                runRegister(last)
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
            }
        }
    }

    // MARK: - Empty

    /// No playbook yet: the device over the empty message, centred in the
    /// free space, and the row that adds the first one.
    private var emptyScreen: some View {
        VStack(spacing: 10) {
            VStack(spacing: 16) {
                IsoLaunchpadView(count: 0, isRunning: false)
                    .moduleScene()
                EmptyStateZone(label: L10n.t(.playNoneTitle))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            GroupedCard { newRow }
        }
    }

    // MARK: - List

    private var list: some View {
        ScrollView(.vertical, showsIndicators: false) {
            GroupedCard {
                ForEach(store.playbooks) { playbook in
                    row(for: playbook)
                }
                newRow
            }
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
                runner.run(playbook)
            }
            .disabled(runner.isRunning)
            .opacity(runner.isRunning && !isRunningThis ? 0.5 : 1)
            .help(L10n.t(.asstPlaybookRun))
        }
        .groupedRow(isLast: false)
        .onTapGesture { show(.playbook(playbook.id)) }
        .animation(.easeOut(duration: 0.15), value: justRan)
    }

    // MARK: - Opened playbook

    /// One playbook on its own: Back pinned on top, then the hero card with
    /// Run and the steps in order.
    private func opened(_ playbook: Playbook) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            ModuleButton(label: L10n.t(.playBack), systemName: "chevron.left", height: 28) {
                show(.list)
            }
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 18) {
                    hero(playbook)
                    steps(of: playbook)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
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

    /// The last row of the list and the only row of the empty screen:
    /// deep-links to Settings → Playbooks.
    private var newRow: some View {
        Button {
            requestSettings(page: .playbooks)
        } label: {
            HStack(spacing: 12) {
                IconTile(systemName: "plus", dashed: true)
                Text(L10n.t(.playAdd))
                    .font(Theme.bodyFont)
                    .foregroundStyle(Theme.textSecondary)
                Spacer(minLength: 0)
            }
            .groupedRow(isLast: true)
        }
        .buttonStyle(PressableStyle())
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
