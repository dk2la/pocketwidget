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

/// "Playbooks" module: a key pad on top — one key per playbook — and the
/// same choice as a row of chips, like the System module. Below, the picked
/// playbook: a hero card with Run and its steps in order, so it is clear
/// what running it will do. "+" opens the editor in Settings. A quiet
/// register underneath reports failures of the last run.
struct PlaybooksModuleView: View {
    var store: PlaybookStore
    var runner: PlaybookRunner

    /// Playbook that just finished — it shows a checkmark for 3 s.
    @State private var justRanID: UUID?
    /// The playbook picked on the pad or the chips.
    @State private var selectedID: UUID?
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

    /// The playbook on show: the picked one, else the last one run, else
    /// the first.
    private var focus: Playbook? {
        if let picked = store.playbooks.first(where: { $0.id == selectedID }) {
            return picked
        }
        if let last = runner.lastRun,
           let current = store.playbooks.first(where: { $0.id == last.playbook.id }) {
            return current
        }
        return store.playbooks.first
    }

    var body: some View {
        VStack(spacing: 10) {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 18) {
                    IsoLaunchpadView(
                        count: store.playbooks.count,
                        selected: store.playbooks.firstIndex { $0.id == focus?.id },
                        isRunning: runner.runningPlaybookID != nil
                    ) { index in
                        guard store.playbooks.indices.contains(index) else { return }
                        select(store.playbooks[index])
                    }
                    .moduleScene()
                    if let focus {
                        picker(focus)
                        VStack(alignment: .leading, spacing: 18) {
                            hero(focus)
                            steps(of: focus)
                        }
                        // A fresh panel per playbook: it cross-fades instead
                        // of swapping text in place.
                        .id(focus.id)
                        .transition(.opacity)
                    } else {
                        GroupedCard { newRow }
                    }
                }
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

    // MARK: - Picker

    private func select(_ playbook: Playbook) {
        withAnimation(.snappy) { selectedID = playbook.id }
    }

    /// Every playbook as a labelled chip — the obvious way to switch —
    /// ending in "+".
    private func picker(_ focus: Playbook) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(store.playbooks) { playbook in
                    let isOn = playbook.id == focus.id
                    Button {
                        select(playbook)
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: playbook.icon)
                                .font(.system(size: 9, weight: .semibold))
                            Text(playbook.name)
                                .font(Theme.captionFont)
                                .fontWeight(.semibold)
                                .lineLimit(1)
                        }
                        .foregroundStyle(isOn ? Theme.inkOnAccent : Theme.textSecondary)
                        .padding(.horizontal, 10)
                        .frame(height: 26)
                        .background(Capsule().fill(isOn ? Theme.lightFill : Theme.cardFill))
                        .contentShape(Capsule())
                    }
                    .buttonStyle(PressableStyle())
                }
                Button {
                    requestSettings(page: .playbooks)
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Theme.textSecondary)
                        .frame(width: 26, height: 26)
                        .background(Circle().fill(Theme.cardFill))
                        .contentShape(Circle())
                }
                .buttonStyle(PressableStyle())
                .help(L10n.t(.playAdd))
            }
        }
    }

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

    /// Shown when there is no playbook yet: deep-links to Settings →
    /// Playbooks.
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
