import AppKit
import QuickLookThumbnailing
import SwiftUI
import UniformTypeIdentifiers

/// "Shelf" module. Empty, it is the empty screen: a small bookcase, and
/// the "Add file" bar pinned to the bottom. With files it is one grouped list — icon, name over
/// size and kind, a remove button — where the picked row opens up to show
/// a preview of what is inside, Open and Show in Finder; the list ends in
/// the same "Add file" row. Files drop anywhere on the module in both
/// states and drag back out of a row. Clearing lives in the panel header.
struct ShelfModuleView: View {
    var shelf: ShelfStore

    @State private var selectedID: UUID?
    @State private var isTargeted = false

    /// The picked file, or the newest one.
    private var focus: ShelfStore.Item? {
        shelf.items.first { $0.id == selectedID } ?? shelf.items.first
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            files.emptyScreen(when: shelf.items.isEmpty) {
                VStack(spacing: 10) {
                    ModuleEmptyScreen(label: L10n.t(.shelfEmpty), sublabel: L10n.t(.shelfEmptySub)) {
                        IsoShelfView(isTargeted: isTargeted)
                    }
                    ShelfAddFileRow(shelf: shelf, isBar: true) { showNewest() }
                }
            }
            ModuleFootnote(systemName: "link", text: L10n.t(.shelfLinksNote))
        }
        .dropDestination(for: URL.self) { urls, _ in
            shelf.add(urls)
            showNewest()
            return !urls.isEmpty
        } isTargeted: { isTargeted = $0 }
    }

    /// New files land first — open the newest one.
    private func showNewest() {
        withAnimation(.snappy(duration: 0.3)) { selectedID = shelf.items.first?.id }
    }

    private func select(_ item: ShelfStore.Item) {
        withAnimation(Theme.reduceMotion ? nil : .snappy(duration: 0.3)) {
            selectedID = item.id
        }
    }

    // MARK: - List

    private var files: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 8) {
                    SectionHeader(title: L10n.t(.shelfSection), trailing: "\(shelf.items.count)")
                    GroupedCard {
                        ForEach(Array(shelf.items.enumerated()), id: \.element.id) { index, item in
                            itemRow(item, isLast: index == shelf.items.count - 1)
                        }
                    }
                    // The card lights up while files hang over the module.
                    .overlay(
                        RoundedRectangle(cornerRadius: Theme.groupRadius, style: .continuous)
                            .stroke(Theme.accent.opacity(isTargeted ? 0.7 : 0), lineWidth: 1)
                    )
                }
                ShelfAddFileRow(shelf: shelf) { showNewest() }
            }
        }
    }

    private func itemRow(_ item: ShelfStore.Item, isLast: Bool) -> some View {
        let isPicked = item.id == focus?.id
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                fileIcon(item)
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.name)
                        .font(Theme.bodyFont)
                        .fontWeight(isPicked ? .semibold : .regular)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .foregroundStyle(Theme.textPrimary)
                    Text(Self.meta(for: item.url))
                        .font(Theme.subFont)
                        .lineLimit(1)
                        .foregroundStyle(Theme.textTertiary)
                }
                Spacer(minLength: 0)
                Button {
                    withAnimation(.snappy(duration: 0.3)) { shelf.remove(item) }
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Theme.textSecondary)
                        .frame(width: 30, height: 30)
                        .background(Circle().fill(Theme.raisedFill))
                        .contentShape(Circle())
                }
                .buttonStyle(PressableStyle())
            }
            if isPicked {
                details(item)
                    .transition(.opacity)
            }
        }
        .groupedRow(isLast: isLast)
        .onDrag {
            NSItemProvider(object: item.url as NSURL)
        }
        .onTapGesture {
            select(item)
        }
    }

    /// What the picked row opens up to: a look inside and the two ways out.
    private func details(_ item: ShelfStore.Item) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            FilePreview(url: item.url)
                .frame(height: 132)
            HStack(spacing: 8) {
                ModuleButton(label: L10n.t(.licManageOpen), systemName: "arrow.up.forward", kind: .light) {
                    NSWorkspace.shared.open(item.url)
                }
                ModuleButton(label: L10n.t(.shelfReveal)) {
                    NSWorkspace.shared.activateFileViewerSelecting([item.url])
                }
                Spacer(minLength: 0)
            }
        }
    }

    private func fileIcon(_ item: ShelfStore.Item) -> some View {
        Image(nsImage: NSWorkspace.shared.icon(forFile: item.url.path))
            .resizable()
            .frame(width: 24, height: 24)
            .frame(width: 32, height: 32)
            .background(Theme.raisedFill, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
    }

    /// "2.4 MB · PDF document" — folders carry the kind alone.
    private static func meta(for url: URL) -> String {
        let values = try? url.resourceValues(forKeys: [.fileSizeKey, .isDirectoryKey, .localizedTypeDescriptionKey])
        var parts: [String] = []
        if values?.isDirectory != true, let bytes = values?.fileSize {
            parts.append(ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file))
        }
        if let kind = values?.localizedTypeDescription, !kind.isEmpty {
            parts.append(kind)
        }
        return parts.isEmpty ? "—" : parts.joined(separator: " · ")
    }
}

/// A look inside the file: its Quick Look thumbnail — the first page, the
/// picture, the opening lines — on a dark well. Falls back to the file's
/// icon for types Quick Look cannot draw.
private struct FilePreview: View {
    let url: URL

    @State private var image: NSImage?

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
        ZStack {
            shape.fill(Color.black.opacity(0.28))
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .padding(10)
                    .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity)
        .overlay(shape.stroke(Theme.hairlineSoft, lineWidth: 1))
        .animation(.easeOut(duration: 0.2), value: image != nil)
        .task(id: url) {
            image = await Self.thumbnail(for: url)
        }
    }

    private static func thumbnail(for url: URL) async -> NSImage? {
        let request = QLThumbnailGenerator.Request(
            fileAt: url,
            size: CGSize(width: 360, height: 240),
            scale: 2,
            representationTypes: .all
        )
        let representation = try? await QLThumbnailGenerator.shared.generateBestRepresentation(for: request)
        return representation?.nsImage
    }
}
