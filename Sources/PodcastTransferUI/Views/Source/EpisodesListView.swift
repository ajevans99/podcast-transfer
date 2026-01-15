import PodcastTransferCore
import SwiftUI

struct EpisodesListView: View {
  let episodes: [PodcastEpisode]
  let selectedEpisodeIDs: Set<String>
  let isLoading: Bool
  var artworkLoader: ArtworkLoader
  var onToggle: (PodcastEpisode) -> Void
  var onRefresh: () async -> Void

  var body: some View {
    List {
      ForEach(podcastSections, id: \.podcast) { section in
        Section(section.podcast) {
          ForEach(section.episodes) { episode in
            Button {
              onToggle(episode)
            } label: {
              EpisodeRow(
                episode: episode,
                isSelected: selectedEpisodeIDs.contains(episode.id),
                artworkLoader: artworkLoader
              )
            }
            .buttonStyle(.plain)
          }
        }
      }
    }
    .overlay {
      if episodes.isEmpty && !isLoading {
        ContentUnavailableView(
          "No downloads",
          systemImage: "tray",
          description: Text("We could not find any downloaded Apple Podcasts in your library.")
        )
      }
    }
    .refreshable {
      await onRefresh()
    }
  }

  private var podcastSections: [(podcast: String, episodes: [PodcastEpisode])] {
    Dictionary(grouping: episodes, by: { $0.podcastTitle })
      .map { podcast, episodes in
        let sortedEpisodes = episodes.sorted { lhs, rhs in
          (lhs.createdAt ?? .distantPast) > (rhs.createdAt ?? .distantPast)
        }
        let newest = sortedEpisodes.first?.createdAt ?? .distantPast
        return (podcast: podcast, episodes: sortedEpisodes, newestDate: newest)
      }
      .sorted { $0.newestDate > $1.newestDate }
      .map { ($0.podcast, $0.episodes) }
  }
}
