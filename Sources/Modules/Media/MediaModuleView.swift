import SwiftUI

/// "Music" module: the current track as one player card after the Spotify
/// Card on 21st.dev — a tinted, glowing card with the player's badge, large
/// artwork (hover for play and like), a small equalizer while playing, and
/// a black control deck with the scrubber, transport and system volume.
/// The tint follows the artwork. Below it: the song on repeat and the
/// recently played shelf, then the running players — clicking one makes it
/// the one the buttons control.
struct MediaModuleView: View {
    var media: MediaCenter
    var audio: AudioSystemMonitor

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 18) {
                    if let track = media.track {
                        PlayerCard(media: media, audio: audio, track: track)
                    } else {
                        EmptyStateZone(label: L10n.t(.mediaNoSignal), sublabel: idleMessage)
                            .frame(height: 110)
                    }
                    MediaHistorySection(media: media)
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

    static func icon(for kind: MediaSourceKind) -> String {
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

// MARK: - Player card

/// The Spotify-style card. Hover state drives the glow that follows the
/// pointer, the pulsing rim and the artwork overlay.
private struct PlayerCard: View {
    var media: MediaCenter
    var audio: AudioSystemMonitor
    let track: MediaTrack

    @State private var isHovered = false
    @State private var isArtHovered = false
    @State private var pointer: CGPoint?

    /// Spotify green when the artwork gives no color.
    private static let fallbackTint = Color(red: 0.118, green: 0.843, blue: 0.376) // #1ED760

    private var tint: Color {
        media.artworkAccent ?? Self.fallbackTint
    }

    private let shape = RoundedRectangle(cornerRadius: Theme.heroRadius, style: .continuous)

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 14) {
                header
                artwork
                Equalizer(isPlaying: track.isPlaying, tint: tint)
                    .frame(height: 22)
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 10)
            deck
        }
        .background(background)
        .clipShape(shape)
        .overlay(shape.stroke(Color.white.opacity(0.06), lineWidth: 1))
        .overlay(rim)
        .shadow(color: tint.opacity(isHovered ? 0.18 : 0.08), radius: 22)
        .onContinuousHover { phase in
            switch phase {
            case let .active(location):
                pointer = location
                if !isHovered { withAnimation(.easeOut(duration: 0.5)) { isHovered = true } }
            case .ended:
                withAnimation(.easeOut(duration: 0.5)) { isHovered = false }
            }
        }
    }

    // MARK: Surface

    private var background: some View {
        GeometryReader { proxy in
            ZStack {
                Color(white: 0.035)
                RadialGradient(
                    colors: [tint.opacity(0.30), tint.opacity(0.07)],
                    center: UnitPoint(x: 0.5, y: 0.3),
                    startRadius: 0,
                    endRadius: max(proxy.size.width, proxy.size.height) * 0.75
                )
                // Soft light that follows the pointer.
                if let pointer {
                    Circle()
                        .fill(tint.opacity(0.22))
                        .frame(width: 180, height: 180)
                        .position(pointer)
                        .blur(radius: 40)
                        .opacity(isHovered ? 1 : 0)
                }
            }
        }
    }

    /// Thin tinted rim that breathes while the pointer is over the card.
    private var rim: some View {
        TimelineView(.animation(paused: !isHovered || Theme.reduceMotion)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            let pulse = (sin(t * .pi * 2 / 2.5) + 1) / 2
            shape.stroke(tint.opacity(0.35), lineWidth: 1)
                .opacity(isHovered ? (Theme.reduceMotion ? 0.6 : pulse) : 0)
        }
        .allowsHitTesting(false)
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(Color.black.opacity(0.9))
                Image(systemName: media.activeSource.map(MediaModuleView.icon(for:)) ?? "music.note")
                    .font(Theme.iconLargeFont)
                    .foregroundStyle(tint)
                    .shadow(color: tint.opacity(isHovered ? 0.6 : 0), radius: 3)
                    .scaleEffect(isHovered ? 1.08 : 1)
            }
            .frame(width: 44, height: 44)
            .shadow(color: tint.opacity(isHovered ? 0.3 : 0), radius: 8)

            VStack(alignment: .leading, spacing: 2) {
                Text(media.label(for: track.source))
                    .font(Theme.titleFont)
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    StatusDot(color: track.isPlaying ? tint : Theme.segmentOff)
                    Text(L10n.t(track.isPlaying ? .mediaPlaying : .mediaPaused))
                        .font(Theme.captionFont)
                        .fontWeight(.medium)
                        .foregroundStyle(track.isPlaying ? tint : Theme.textTertiary)
                }
            }
            Spacer(minLength: 0)
            if media.availableSources.count > 1 {
                nextPlayerButton
            }
        }
    }

    /// The round chevron of the original: here it hands the buttons to the
    /// next running player.
    private var nextPlayerButton: some View {
        Button {
            let sources = media.availableSources
            guard let current = media.activeSource, let index = sources.firstIndex(of: current) else {
                if let first = sources.first { media.select(first) }
                return
            }
            media.select(sources[(index + 1) % sources.count])
        } label: {
            Image(systemName: "chevron.right")
                .font(Theme.iconSmallFont)
                .foregroundStyle(isHovered ? Theme.inkOnAccent : Theme.textSecondary)
                .frame(width: 32, height: 32)
                .background(Circle().fill(isHovered ? tint : Color.black.opacity(0.25)))
                .offset(x: isHovered ? 0 : 4)
                .contentShape(Circle())
        }
        .buttonStyle(PressableStyle())
        .help(L10n.t(.mediaPlayers))
    }

    // MARK: Artwork

    private var artwork: some View {
        let artShape = RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
        // A square slot first; the image fills it, so wide or tall artwork
        // can't stretch the layout.
        return Color.clear
            .aspectRatio(1, contentMode: .fit)
            .frame(maxWidth: 200, maxHeight: 200)
            .overlay {
                Group {
                    if let image = media.artwork {
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
                .scaleEffect(isArtHovered ? 1.02 : 1)
                .brightness(isArtHovered ? 0.03 : 0)
            }
            .overlay {
                artOverlay
                    .opacity(isArtHovered ? 1 : 0)
            }
            .clipShape(artShape)
            .contentShape(artShape)
        .shadow(color: .black.opacity(isHovered ? 0.45 : 0.25), radius: isHovered ? 16 : 8, y: isHovered ? 10 : 4)
        .shadow(color: tint.opacity(isHovered ? 0.15 : 0), radius: 8)
        .frame(maxWidth: .infinity)
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.35)) { isArtHovered = hovering }
        }
    }

    private var artOverlay: some View {
        ZStack {
            LinearGradient(
                colors: [.black.opacity(0.2), .black.opacity(0.5), .black.opacity(0.7)],
                startPoint: .top,
                endPoint: .bottom
            )
            Button {
                media.togglePlayPause()
            } label: {
                Image(systemName: track.isPlaying ? "pause.fill" : "play.fill")
                    .font(Theme.iconLargeFont)
                    .foregroundStyle(Theme.inkOnAccent)
                    .offset(x: track.isPlaying ? 0 : 2)
                    .frame(width: 52, height: 52)
                    .background(Circle().fill(tint))
                    .shadow(color: tint.opacity(0.55), radius: 12)
                    .scaleEffect(isArtHovered ? 1 : 0.4)
                    .contentShape(Circle())
            }
            .buttonStyle(PressableStyle())
            .disabled(!media.canControlActive)

            if media.supportsLike {
                Button {
                    media.like()
                } label: {
                    Image(systemName: "heart")
                        .font(Theme.iconSmallFont)
                        .foregroundStyle(Theme.textPrimary)
                        .frame(width: 28, height: 28)
                        .background(Circle().fill(.black.opacity(0.45)))
                        .contentShape(Circle())
                }
                .buttonStyle(PressableStyle())
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                .padding(10)
            }
        }
    }

    // MARK: Deck

    /// The black strip at the bottom: scrubber, title and times, transport,
    /// volume.
    private var deck: some View {
        VStack(alignment: .leading, spacing: 10) {
            DeckProgress(media: media, track: track, tint: tint, titleTint: isHovered ? tint : Theme.textPrimary)
            HStack(spacing: 8) {
                transport
                Spacer(minLength: 8)
                volume
            }
        }
        .padding(12)
        .background(Color.black.opacity(0.92))
        .overlay(alignment: .top) {
            Rectangle().fill(Color.white.opacity(0.05)).frame(height: 1)
        }
        .overlay(alignment: .bottom) {
            // Tinted glint along the bottom edge on hover.
            LinearGradient(colors: [.clear, tint.opacity(0.5), .clear], startPoint: .leading, endPoint: .trailing)
                .frame(height: 2)
                .blur(radius: 1)
                .opacity(isHovered ? 1 : 0)
        }
    }

    private var transport: some View {
            HStack(spacing: 8) {
                transportButton("backward.fill") { media.previous() }
                Button {
                    media.togglePlayPause()
                } label: {
                    Image(systemName: track.isPlaying ? "pause.fill" : "play.fill")
                        .font(Theme.iconSmallFont)
                        .foregroundStyle(Theme.inkOnAccent)
                        .offset(x: track.isPlaying ? 0 : 1)
                        .frame(width: 32, height: 32)
                        .background(Circle().fill(Color.white))
                        .shadow(color: .white.opacity(0.3), radius: 4)
                        .contentShape(Circle())
                }
                .buttonStyle(PressableStyle())
                transportButton("forward.fill") { media.next() }
            }
            .disabled(!media.canControlActive)
            .opacity(media.canControlActive ? 1 : 0.4)
    }

    private func transportButton(_ systemName: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(Theme.iconSmallFont)
                .foregroundStyle(Theme.textPrimary)
                .frame(width: 28, height: 28)
                .contentShape(Circle())
        }
        .buttonStyle(HoverCircleStyle())
    }

    /// System output volume: speaker toggles mute-to-zero, the track sets it.
    private var volume: some View {
        HStack(spacing: 6) {
            Button {
                audio.setVolume(audio.volume > 0 ? 0 : 0.5)
            } label: {
                Image(systemName: audio.volume > 0 ? "speaker.wave.2.fill" : "speaker.slash.fill")
                    .font(Theme.iconSmallFont)
                    .foregroundStyle(Theme.textTertiary)
                    .frame(width: 24, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(HoverCircleStyle())
            ScrubberBar(fraction: audio.volume, fillColor: isHovered ? tint : .white) { target in
                audio.setVolume(target)
            }
            .frame(width: 64)
        }
    }
}

/// Scrubber with the title and times. Lives in its own one-second
/// `TimelineView`, so only this subtree re-renders per tick.
private struct DeckProgress: View {
    var media: MediaCenter
    let track: MediaTrack
    let tint: Color
    let titleTint: Color

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let position = track.position(at: context.date)
            VStack(alignment: .leading, spacing: 8) {
                ScrubberBar(
                    fraction: track.duration > 0 ? position / track.duration : 0,
                    fillColor: tint
                ) { target in
                    media.seek(toFraction: target)
                }
                .shadow(color: tint.opacity(0.4), radius: 3)
                .disabled(!media.canControlActive)
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(track.title)
                            .font(Theme.headlineFont)
                            .foregroundStyle(titleTint)
                            .lineLimit(1)
                            .truncationMode(.tail)
                        if !track.artist.isEmpty {
                            Text(track.artist)
                                .font(Theme.captionFont)
                                .foregroundStyle(Theme.textTertiary)
                                .lineLimit(1)
                        }
                    }
                    Spacer(minLength: 8)
                    Text("\(TimeFormat.mmss(position)) / \(TimeFormat.mmss(track.duration))")
                        .font(Theme.captionFont)
                        .monospacedDigit()
                        .foregroundStyle(Theme.textTertiary)
                }
            }
        }
    }
}

/// Five bars that bob while the track plays; flat dots when paused.
private struct Equalizer: View {
    let isPlaying: Bool
    let tint: Color

    /// Per-bar period (s) and height range (pt), from the original's waves.
    private static let waves: [(period: Double, low: CGFloat, high: CGFloat)] = [
        (1.1, 4, 16), (1.2, 5, 12), (1.3, 7, 18), (1.4, 5, 14), (1.5, 3, 13),
    ]

    var body: some View {
        TimelineView(.animation(paused: !isPlaying || Theme.reduceMotion)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            HStack(alignment: .bottom, spacing: 4) {
                ForEach(Self.waves.indices, id: \.self) { i in
                    let wave = Self.waves[i]
                    let phase = (sin(t * .pi * 2 / wave.period) + 1) / 2
                    let height = isPlaying
                        ? (Theme.reduceMotion ? (wave.low + wave.high) / 2 : wave.low + (wave.high - wave.low) * phase)
                        : 3
                    Capsule()
                        .fill(tint.opacity(isPlaying ? 0.75 : 0.3))
                        .frame(width: 4, height: height)
                        .shadow(color: tint.opacity(0.5), radius: 1)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        }
    }
}

/// Ghost round button that lights a faint disc on hover.
private struct HoverCircleStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        HoverCircle(configuration: configuration)
    }

    private struct HoverCircle: View {
        let configuration: ButtonStyleConfiguration
        @State private var hovering = false

        var body: some View {
            configuration.label
                .background(Circle().fill(Color.white.opacity(hovering ? 0.1 : 0)))
                .scaleEffect(configuration.isPressed ? 0.94 : 1)
                .onHover { hovering = $0 }
                .animation(.easeOut(duration: 0.15), value: hovering)
                .animation(.easeOut(duration: 0.08), value: configuration.isPressed)
        }
    }
}
