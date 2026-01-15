import PodcastTransferCore
import SwiftUI

struct EpisodeTableTitleCell: View {
  let episode: PodcastEpisode
  var artworkLoader: ArtworkLoader

  @State private var image: PlatformImage?

  var body: some View {
    HStack(spacing: 8) {
      ArtworkThumbnail(image: image)
        .frame(width: 24, height: 24)
        .cornerRadius(4)
      Text(episode.title)
        .lineLimit(1)
    }
    .task(id: episode.id) {
      if image == nil {
        image = await artworkLoader.thumbnail(
          for: episode.fileURL,
          fallbackArtworkURL: episode.artworkURL
        )
      }
    }
  }
}
