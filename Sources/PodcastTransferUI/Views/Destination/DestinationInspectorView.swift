import Foundation
import PodcastTransferCore
import SwiftUI

struct DestinationInspectorView: View {
  let destination: URL?
  let episodes: [PodcastEpisode]
  var artworkLoader: ArtworkLoader
  var onChooseFolder: () -> Void
  var onDelete: (PodcastEpisode) -> Void

  var body: some View {
    VStack(alignment: .center, spacing: 12) {
      DestinationControlsView(destination: destination, onChooseFolder: onChooseFolder)

      Divider()

      if destination == nil {
        ContentUnavailableView(
          "No destination",
          systemImage: "externaldrive",
          description: Text("Choose a folder to see what's already on the device.")
        )
      } else if isDestinationReachable == false {
        ContentUnavailableView(
          "Destination not mounted",
          systemImage: "externaldrive.badge.exclamationmark",
          description: Text("Reconnect the volume and try again.")
        )
      } else if episodes.isEmpty {
        ContentUnavailableView(
          "Nothing found",
          systemImage: "tray",
          description: Text("No podcast files were found at this destination.")
        )
      } else {
        VStack(alignment: .leading, spacing: 8) {
          Text("On Destination")
            .font(.headline)

          List {
            ForEach(sortedDestinationEpisodes) { episode in
              DestinationEpisodeRow(episode: episode, artworkLoader: artworkLoader) {
                onDelete(episode)
              }
              .listRowInsets(EdgeInsets(top: 6, leading: 0, bottom: 6, trailing: 0))
            }
          }
          .listStyle(.plain)
          .scrollContentBackground(.hidden)
        }
      }
    }
    .padding(16)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
  }

  private var isDestinationReachable: Bool {
    guard let destination else { return false }
    if let isReachable = try? destination.checkResourceIsReachable() {
      return isReachable
    }
    return FileManager.default.fileExists(atPath: destination.path)
  }

  private var sortedDestinationEpisodes: [PodcastEpisode] {
    episodes.sorted { lhs, rhs in
      (lhs.createdAt ?? .distantPast) > (rhs.createdAt ?? .distantPast)
    }
  }
}
