import SwiftUI

/// "Add file…" — what Shelf ends in: a card of its own under the list, or,
/// with `isBar`, the bar pinned under the empty screen like in every other
/// empty module. Opens the file picker; `onAdded` runs once new files are
/// on the shelf.
struct ShelfAddFileRow: View {
    var shelf: ShelfStore
    var isBar = false
    var onAdded: () -> Void = {}

    /// One picker at a time.
    @State private var isPicking = false

    var body: some View {
        if isBar {
            EmptyActionBar(label: L10n.t(.shelfAdd)) {
                pick()
            }
        } else {
            GroupedCard {
                AddRow(label: L10n.t(.shelfAdd)) {
                    pick()
                }
            }
        }
    }

    private func pick() {
        guard !isPicking else { return }
        isPicking = true
        Task {
            let added = await ShelfFilePicker.addFiles(to: shelf)
            isPicking = false
            if added { onAdded() }
        }
    }
}
