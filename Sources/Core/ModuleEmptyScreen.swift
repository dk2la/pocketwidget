import SwiftUI

/// The empty screen of a module: its animated device over the empty
/// message, centred in whatever space the module gives it. `extra` is for
/// the one thing an empty module may still offer under the message — a
/// button, a row, a drop tile.
///
/// A module shows this only while it has nothing at all to show; with
/// content it looks as usual and carries no device. Swap the two with
/// `emptyScreen(when:_:)`, which cross-fades them in one frame.
///
///     list.emptyScreen(when: store.notes.isEmpty) {
///         ModuleEmptyScreen(label: L10n.t(.notesEmptyTitle), sublabel: L10n.t(.notesEmptySub)) {
///             IsoNotebookView(count: 0, isRecording: false)
///         }
///     }
struct ModuleEmptyScreen<Device: View, Extra: View>: View {
    private let label: String
    private let sublabel: String?
    private let device: Device
    private let extra: Extra

    init(
        label: String,
        sublabel: String? = nil,
        @ViewBuilder device: () -> Device,
        @ViewBuilder extra: () -> Extra
    ) {
        self.label = label
        self.sublabel = sublabel
        self.device = device()
        self.extra = extra()
    }

    var body: some View {
        VStack(spacing: 16) {
            // The message and the extra content keep their size; on a short
            // panel it is the device that gives way.
            device
                .moduleScene(shrinks: true)
            EmptyStateZone(label: label, sublabel: sublabel)
                .fixedSize(horizontal: false, vertical: true)
            extra
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

extension ModuleEmptyScreen where Extra == EmptyView {
    init(label: String, sublabel: String? = nil, @ViewBuilder device: () -> Device) {
        self.init(label: label, sublabel: sublabel, device: device) { EmptyView() }
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
