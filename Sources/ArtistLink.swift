import SwiftUI

/// Blazify Project (C) 2026
/// Licensed under GPL-3.0

/// Makes the artist line under a song title open that artist.
///
/// Written as a modifier rather than a view because the three designs that show
/// the line each style it their own way — the cream plastic of the cassette, the
/// ring's centred column, the standard chrome — and a component that took a font
/// and a colour and an alignment would only be those three styles wearing a
/// disguise. This adds the tap and the page it opens, and leaves the text alone.
///
/// One difference from Android, which collapses the player and pushes the artist
/// onto the page underneath: here the artist is presented over the player, so
/// closing it puts you back where you were, still playing, rather than at the
/// bottom of a screen you did not ask to leave.
extension View {
    func opensArtist(_ player: Player) -> some View {
        modifier(OpensArtist(player: player))
    }
}

private struct OpensArtist: ViewModifier {
    @ObservedObject var player: Player

    @State private var artistId: String?
    @State private var showArtist = false
    /// True while a name is being turned into a channel, so a second tap on a
    /// slow network doesn't start the same search again.
    @State private var looking = false

    func body(content: Content) -> some View {
        content
            .contentShape(Rectangle())
            .onTapGesture { open() }
            .fullScreenCover(isPresented: $showArtist) {
                if let artistId {
                    ArtistView(browseId: artistId, player: player)
                }
            }
    }

    private func open() {
        guard let track = player.current, !track.artist.isEmpty, !looking else { return }
        if let id = track.artistId, !id.isEmpty {
            artistId = id
            showArtist = true
            return
        }
        // Rows from some shelves carry no channel id. Looking the name up is
        // better than a line that does nothing when pressed — and if nothing is
        // found, nothing happens, which is what a name with no page behind it
        // honestly deserves.
        looking = true
        Task {
            let found = await YouTube.resolveArtistId(name: track.artist)
            await MainActor.run {
                looking = false
                artistId = found
                if found != nil { showArtist = true }
            }
        }
    }
}
