import SwiftUI

/// "Music" module: the current track as a hero card — artwork, title,
/// scrubber, transport — and the running players as one grouped list.
/// Clicking a player makes it the one the buttons control.
struct MediaModuleView: View {
    var media: MediaCenter

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 18) {
                    if let track = media.track {
                        hero(track)
                    } else {
                        EmptyStateZone(label: L10n.t(.mediaNoSignal), sublabel: idleMessage)
                            .frame(height: 110)
                    }
                    if media.availableSources.count > 1 {
                        players
                    }
                }
            }
            if media.track != nil {
                ModuleFootnote(systemName: "music.note", text: L10n.t(.mediaControlNote))
            }
        }
    }

    // MARK: - Hero

    private func hero(_ track: MediaTrack) -> some View {
        HeroCard {
            HStack(spacing: 7) {
                StatusDot(color: track.isPlaying ? Theme.accent : Theme.segmentOff)
                HStack(spacing: 0) {
                    Text(L10n.t(track.isPlaying ? .mediaPlaying : .mediaPaused))
                        .heroCaption()
                    Text(" · \(media.label(for: track.source))")
                        .font(Theme.subFont)
                        .lineLimit(1)
                        .foregroundStyle(Theme.textTertiary)
                }
            }
            HStack(spacing: 14) {
                artworkView
                VStack(alignment: .leading, spacing: 3) {
                    Text(track.title)
                        .font(Theme.heroFont)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .foregroundStyle(Theme.textPrimary)
                    if !track.artist.isEmpty {
                        Text(track.artist)
                            .font(Theme.subFont)
                            .lineLimit(1)
                            .foregroundStyle(Theme.textTertiary)
                    }
                }
                Spacer(minLength: 0)
            }
            progress(for: track)
            transport(for: track)
        }
    }

    /// Scrubber and time readouts. Progress is derived from the track's
    /// timing sample on a one-second `TimelineView`, so only this subtree
    /// re-renders per tick (and only while the module is on screen); the
    /// title, artwork and transport above and below stay untouched.
    private func progress(for track: MediaTrack) -> some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let position = track.position(at: context.date)
            VStack(alignment: .leading, spacing: 4) {
                ScrubberBar(
                    fraction: track.duration > 0 ? position / track.duration : 0,
                    fillColor: Theme.segmentOn
                ) { target in
                    media.seek(toFraction: target)
                }
                .disabled(!media.canControlActive)
                HStack {
                    Text(TimeFormat.mmss(position))
                    Spacer()
                    Text("−" + TimeFormat.mmss(track.duration - position))
                }
                .font(Theme.subFont)
                .monospacedDigit()
                .foregroundStyle(Theme.textTertiary)
            }
        }
    }

    private var artworkView: some View {
        Group {
            if let artwork = media.artwork {
                Image(nsImage: artwork)
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
        .frame(width: 64, height: 64)
        .clipShape(RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
    }

    private func transport(for track: MediaTrack) -> some View {
        HStack(spacing: 8) {
            ModuleButton(systemName: "backward.fill") { media.previous() }
            ModuleButton(
                label: L10n.t(track.isPlaying ? .timerPause : .mediaPlay),
                systemName: track.isPlaying ? "pause.fill" : "play.fill",
                kind: .light
            ) {
                media.togglePlayPause()
            }
            ModuleButton(systemName: "forward.fill") { media.next() }
            Spacer(minLength: 0)
            if media.supportsLike {
                ModuleButton(systemName: "heart") { media.like() }
            }
        }
        .disabled(!media.canControlActive)
        .opacity(media.canControlActive ? 1 : 0.4)
    }

    // MARK: - Players

    private var players: some View {
        let sources = media.availableSources
        return VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title: L10n.t(.mediaPlayers), trailing: "\(sources.count)")
            GroupedCard {
                ForEach(Array(sources.enumerated()), id: \.element.id) { index, kind in
                    playerRow(kind, isLast: index == sources.count - 1)
                }
            }
        }
    }

    private func playerRow(_ kind: MediaSourceKind, isLast: Bool) -> some View {
        let isActive = media.activeSource == kind
        return Button {
            media.select(kind)
        } label: {
            HStack(spacing: 12) {
                IconTile(systemName: Self.icon(for: kind))
                VStack(alignment: .leading, spacing: 2) {
                    Text(media.label(for: kind))
                        .font(Theme.bodyFont)
                        .lineLimit(1)
                        .foregroundStyle(Theme.textPrimary)
                    if isActive, let track = media.track {
                        Text("\(L10n.t(track.isPlaying ? .mediaPlaying : .mediaPaused)) · \(track.title)")
                            .font(Theme.subFont)
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .foregroundStyle(Theme.textTertiary)
                    }
                }
                Spacer(minLength: 0)
                if isActive {
                    StatusDot()
                }
            }
            .groupedRow(isLast: isLast)
        }
        .buttonStyle(PressableStyle())
    }

    private static func icon(for kind: MediaSourceKind) -> String {
        switch kind {
        case .spotify, .appleMusic: "music.note"
        case .client: "play.rectangle"
        }
    }

    private var idleMessage: String {
        if let active = media.activeSource, !media.canControl(active) {
            return L10n.f(.mediaSilent, media.label(for: active))
        }
        return L10n.t(.mediaIdle)
    }
}
