import PodcastTransferCore
import SwiftUI

struct SourceEpisodesView: View {
  let presentation: SourcePresentation
  let episodes: [PodcastEpisode]
  let selectedEpisodeIDs: Set<String>
  @Binding var tableSelectedEpisodeIDs: Set<String>
  let isLoading: Bool
  @Binding var sortOrder: [KeyPathComparator<PodcastEpisode>]
  var artworkLoader: ArtworkLoader
  var onToggle: (PodcastEpisode) -> Void
  var onTableSelectionChanged: (Set<String>) -> Void
  var onRefresh: () async -> Void

  var body: some View {
    switch presentation {
    case .grouped:
      EpisodesListView(
        episodes: episodes,
        selectedEpisodeIDs: selectedEpisodeIDs,
        isLoading: isLoading,
        artworkLoader: artworkLoader,
        onToggle: onToggle,
        onRefresh: onRefresh
      )

    case .table:
      EpisodesTableView(
        episodes: episodes,
        selectedEpisodeIDs: $tableSelectedEpisodeIDs,
        isLoading: isLoading,
        sortOrder: $sortOrder,
        artworkLoader: artworkLoader,
        onSelectionChanged: onTableSelectionChanged,
        onRefresh: onRefresh
      )
    }
  }
}
