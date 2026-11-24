import SwiftUI

/// "Add file…" — the row Shelf ends in, a card of its own so it sits the
/// same under an empty shelf and under a full one. Opens the file picker;
/// `onAdded` runs once new files are on the shelf.
struct ShelfAddFileRow: View {
    var shelf: ShelfStore
    var onAdded: () -> Void = {}

    /// One picker at a time.
    @State private var isPicking = false

    var body: some View {
        GroupedCard {
            Button {
                pick()
            } label: {
                HStack(spacing: 12) {
                    IconTile(systemName: "plus", dashed: true)
                    Text(L10n.t(.shelfAdd))
                        .font(Theme.bodyFont)
                        .foregroundStyle(Theme.textSecondary)
                    Spacer(minLength: 0)
                }
                .groupedRow(isLast: true)
            }
            .buttonStyle(PressableStyle())
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
