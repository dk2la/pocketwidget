import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// "Shelf" module: a dashed drop tile on top, then the parked files as one
/// grouped list — icon, name over size and kind, a remove button. Items
/// drag out; click opens. Clearing lives in the panel header.
struct ShelfModuleView: View {
    var shelf: ShelfStore

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 18) {
                    dropTile
                    if !shelf.items.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            SectionHeader(
                                title: L10n.t(.shelfSection),
                                trailing: "\(shelf.items.count)"
                            )
                            GroupedCard {
                                ForEach(Array(shelf.items.enumerated()), id: \.element.id) { index, item in
                                    itemRow(item, isLast: index == shelf.items.count - 1)
                                }
                            }
                        }
                    }
                }
            }
            ModuleFootnote(systemName: "link", text: L10n.t(.shelfLinksNote))
        }
    }

    private var dropTile: some View {
        let shape = RoundedRectangle(cornerRadius: Theme.heroRadius, style: .continuous)
        return HStack(spacing: 12) {
            IconTile(systemName: "plus", dashed: true)
            VStack(alignment: .leading, spacing: 2) {
                Text(L10n.t(.shelfDrop))
                    .font(Theme.headlineFont)
                    .lineLimit(1)
                    .foregroundStyle(Theme.textPrimary)
                Text(L10n.t(.shelfDropSub))
                    .font(Theme.subFont)
                    .lineLimit(1)
                    .foregroundStyle(Theme.textTertiary)
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(shape.stroke(Theme.dashedBorder, style: StrokeStyle(lineWidth: 1, dash: [5, 6])))
    }

    private func itemRow(_ item: ShelfStore.Item, isLast: Bool) -> some View {
        HStack(spacing: 12) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: item.url.path))
                .resizable()
                .frame(width: 24, height: 24)
                .frame(width: 32, height: 32)
                .background(Theme.raisedFill, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(item.name)
                    .font(Theme.bodyFont)
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
                shelf.remove(item)
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
        .groupedRow(isLast: isLast)
        .onDrag {
            NSItemProvider(object: item.url as NSURL)
        }
        .onTapGesture {
            NSWorkspace.shared.open(item.url)
        }
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
