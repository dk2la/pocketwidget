import SwiftUI

/// The blocks under the player card, built from what Pocket heard play on
/// this Mac: the song on repeat and a shelf of recently played covers.
/// Clicking one starts it again in its player (Spotify, Music). Only songs
/// that can be started again are listed; with none, the section is gone.
struct MediaHistorySection: View {
    var media: MediaCenter

    var body: some View {
        let history = media.history
        let usable = media.replayableSourceIDs
        let recent = history.recent(excluding: media.track, usableSourceIDs: usable)
        let onRepeat = history.onRepeat(usableSourceIDs: usable)
        if onRepeat != nil || !recent.isEmpty {
            VStack(alignment: .leading, spacing: 18) {
                if let onRepeat {
                    OnRepeatCard(media: media, entry: onRepeat)
                }
                if !recent.isEmpty {
                    recentShelf(recent)
                }
            }
        }
    }

    private func recentShelf(_ recent: [PlayHistoryEntry]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title: L10n.t(.mediaRecent), trailing: "\(recent.count)")
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: 12) {
                    ForEach(recent) { entry in
                        RecentCover(media: media, entry: entry)
                    }
                }
                .padding(.horizontal, 2)
            }
            .scrollClipDisabled()
        }
    }
}

/// The most played song of the last two weeks, on a card tinted by its
/// cover.
private struct OnRepeatCard: View {
    var media: MediaCenter
    let entry: PlayHistoryEntry

    @State private var isHovered = false

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Theme.heroRadius, style: .continuous)
        let tint = media.history.accent(for: entry) ?? Theme.accent
        HStack(spacing: 14) {
            HistoryCover(image: media.history.cover(for: entry), size: 72)
                .shadow(color: tint.opacity(0.45), radius: isHovered ? 14 : 8, y: 4)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 5) {
                    Image(systemName: "repeat")
                        .font(Theme.captionFont.weight(.bold))
                    Text(L10n.t(.mediaOnRepeat).uppercased())
                        .font(Theme.captionFont)
                        .fontWeight(.bold)
                        .kerning(0.8)
                }
                .foregroundStyle(tint)
                Text(entry.title)
                    .font(Theme.titleFont)
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                if !entry.artist.isEmpty {
                    Text(entry.artist)
                        .font(Theme.subFont)
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(1)
                }
                Text(L10n.f(.mediaPlays, "\(entry.playCount)"))
                    .font(Theme.captionFont)
                    .monospacedDigit()
                    .foregroundStyle(Theme.textTertiary)
            }
            Spacer(minLength: 0)
            Button {
                media.replay(entry)
            } label: {
                Image(systemName: "play.fill")
                    .font(Theme.iconSmallFont)
                    .foregroundStyle(Theme.inkOnAccent)
                    .offset(x: 1)
                    .frame(width: 38, height: 38)
                    .background(Circle().fill(tint))
                    .shadow(color: tint.opacity(0.5), radius: isHovered ? 10 : 4)
                    .scaleEffect(isHovered ? 1.06 : 1)
                    .contentShape(Circle())
            }
            .buttonStyle(PressableStyle())
            .help(L10n.t(.mediaPlay))
        }
        .padding(14)
        .background(
            LinearGradient(
                colors: [tint.opacity(0.28), tint.opacity(0.06)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: shape
        )
        .background(Color(white: 0.04), in: shape)
        .overlay(shape.stroke(tint.opacity(isHovered ? 0.35 : 0.15), lineWidth: 1))
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.3)) { isHovered = hovering }
        }
    }
}

/// One cover on the "recently played" shelf; hover shows a play button.
private struct RecentCover: View {
    var media: MediaCenter
    let entry: PlayHistoryEntry

    @State private var isHovered = false
    private static let side: CGFloat = 92

    var body: some View {
        Button {
            media.replay(entry)
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                ZStack {
                    HistoryCover(image: media.history.cover(for: entry), size: Self.side)
                        .scaleEffect(isHovered ? 1.03 : 1)
                    Image(systemName: "play.fill")
                        .font(Theme.iconSmallFont)
                        .foregroundStyle(Theme.inkOnAccent)
                        .offset(x: 1)
                        .frame(width: 32, height: 32)
                        .background(Circle().fill(Color.white))
                        .shadow(color: .black.opacity(0.35), radius: 6)
                        .opacity(isHovered ? 1 : 0)
                        .scaleEffect(isHovered ? 1 : 0.6)
                }
                .shadow(color: .black.opacity(isHovered ? 0.4 : 0.2), radius: isHovered ? 10 : 5, y: 3)
                VStack(alignment: .leading, spacing: 1) {
                    Text(entry.title)
                        .font(Theme.subFont)
                        .fontWeight(.medium)
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(1)
                    Text(entry.artist)
                        .font(Theme.captionFont)
                        .foregroundStyle(Theme.textTertiary)
                        .lineLimit(1)
                }
                .frame(width: Self.side, alignment: .leading)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle())
        .help(L10n.t(.mediaPlay))
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.25)) { isHovered = hovering }
        }
    }
}

/// A square cover, or a note on a raised tile when none was saved.
private struct HistoryCover: View {
    let image: NSImage?
    let size: CGFloat

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Theme.cardRadius * 0.8, style: .continuous)
        Group {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                ZStack {
                    Theme.raisedFill
                    Image(systemName: "music.note")
                        .font(Theme.iconLargeFont)
                        .foregroundStyle(Theme.textTertiary)
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(shape)
        .overlay(shape.stroke(Color.white.opacity(0.08), lineWidth: 1))
    }
}
