import PodcastTransferCore
import SwiftUI

#if os(macOS)
  import AppKit
#endif

struct EpisodesTableView: View {
  let episodes: [PodcastEpisode]
  @Binding var selectedEpisodeIDs: Set<String>
  let isLoading: Bool
  @Binding var sortOrder: [KeyPathComparator<PodcastEpisode>]
  var artworkLoader: ArtworkLoader
  var onSelectionChanged: (Set<String>) -> Void
  var onRefresh: () async -> Void

  var body: some View {
    Table(sortedEpisodes, selection: $selectedEpisodeIDs, sortOrder: $sortOrder) {
      TableColumn("Title", value: \.title) { episode in
        EpisodeTableTitleCell(episode: episode, artworkLoader: artworkLoader)
          #if os(macOS)
            .contextMenu {
              Button("Show in Finder", systemImage: "folder") {
                NSWorkspace.shared.activateFileViewerSelecting([episode.fileURL])
              }
            }
          #endif
      }
      .width(min: 220)

      TableColumn("Podcast", value: \.podcastTitle) { episode in
        Text(episode.podcastTitle)
          .lineLimit(1)
      }
      .width(min: 160)

      TableColumn("Date", value: \.createdAtSortable) { episode in
        if let createdAt = episode.createdAt {
          Text(createdAt.formatted(date: .abbreviated, time: .shortened))
        } else {
          Text("–")
            .foregroundStyle(.secondary)
        }
      }
      .width(min: 140)

      TableColumn("Size", value: \.fileSize) { episode in
        Text(byteCountString(episode.fileSize))
      }
      .width(min: 90)

      TableColumn("Length", value: \.durationSortable) { episode in
        if let duration = episode.duration {
          Text(durationString(duration))
        } else {
          Text("–")
            .foregroundStyle(.secondary)
        }
      }
      .width(min: 90)
    }
    .onChange(of: selectedEpisodeIDs) { _, newValue in
      onSelectionChanged(newValue)
    }
    .refreshable {
      await onRefresh()
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
  }

  private var sortedEpisodes: [PodcastEpisode] {
    if sortOrder.isEmpty {
      return episodes.sorted { (lhs, rhs) in
        (lhs.createdAt ?? .distantPast) > (rhs.createdAt ?? .distantPast)
      }
    }
    return episodes.sorted(using: sortOrder)
  }

  private func byteCountString(_ size: Int64) -> String {
    let formatter = ByteCountFormatter()
    formatter.allowedUnits = [.useMB, .useGB]
    formatter.countStyle = .file
    return formatter.string(fromByteCount: size)
  }

  private func durationString(_ duration: TimeInterval) -> String {
    let totalSeconds = Int(duration)
    let minutes = totalSeconds / 60
    let seconds = totalSeconds % 60
    return String(format: "%dm %02ds", minutes, seconds)
  }
}
