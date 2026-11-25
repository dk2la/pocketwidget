import SwiftUI

/// The empty screen of a module: the empty message — a title and an
/// optional sublabel — centred in whatever space the module gives it.
/// `extra` is for the one thing an empty module may still offer under the
/// message, such as a button.
///
/// A module shows this only while it has nothing at all to show. Swap it
/// with the content using `emptyScreen(when:_:)`, which cross-fades the
/// two in one frame.
///
///     list.emptyScreen(when: store.notes.isEmpty) {
///         ModuleEmptyScreen(label: L10n.t(.notesEmptyTitle), sublabel: L10n.t(.notesEmptySub))
///     }
struct ModuleEmptyScreen<Extra: View>: View {
    private let label: String
    private let sublabel: String?
    private let extra: Extra

    init(label: String, sublabel: String? = nil, @ViewBuilder extra: () -> Extra) {
        self.label = label
        self.sublabel = sublabel
        self.extra = extra()
    }

    var body: some View {
        VStack(spacing: 16) {
            EmptyStateZone(label: label, sublabel: sublabel)
                .fixedSize(horizontal: false, vertical: true)
            extra
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

extension ModuleEmptyScreen where Extra == EmptyView {
    init(label: String, sublabel: String? = nil) {
        self.init(label: label, sublabel: sublabel) { EmptyView() }
    }
}

/// The one thing an empty module still offers — "Add playbook…", "Add
/// mail" — as a bar pinned under the empty screen. Same card and place as
/// the text box of Assistant and Notes, so every module ends the same way.
///
///     VStack(spacing: 10) {
///         ModuleEmptyScreen(label: …)
///         EmptyActionBar(label: L10n.t(.playAdd)) { … }
///     }
struct EmptyActionBar: View {
    let label: String
    var systemName = "plus"
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ComposerBar {
                // Same dashed plus tile and label as `AddRow`, so adding
                // looks the same on an empty screen and under a list.
                IconTile(systemName: systemName, size: 30, dashed: true)
                Text(label)
                    .font(Theme.bodyFont)
                    .monospacedDigit()
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .foregroundStyle(Theme.textSecondary)
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle())
    }
}

extension View {
    /// Shows `screen` in place of this view while `isEmpty` is true. The
    /// two share one frame that fills the free space and cross-fade in it,
    /// so going from empty to non-empty and back moves nothing around.
    /// Apply it to the part of the module that holds the content (the
    /// list), not to bars that stay in both states.
    func emptyScreen<Screen: View>(
        when isEmpty: Bool,
        @ViewBuilder _ screen: () -> Screen
    ) -> some View {
        ZStack(alignment: .top) {
            if isEmpty {
                screen()
                    .transition(.opacity)
            } else {
                self
                    .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .animation(Theme.stateSpring, value: isEmpty)
    }
}
