import PodcastTransferCore
import SwiftUI

#if os(macOS)
  import AppKit
#endif

struct EpisodeRow: View {
  let episode: PodcastEpisode
  var isSelected: Bool
  var artworkLoader: ArtworkLoader
  var showSelection: Bool = true

  @State private var image: PlatformImage?

  var body: some View {
    HStack(alignment: .center, spacing: 10) {
      if showSelection {
        Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
          .foregroundStyle(isSelected ? Color.accentColor : .secondary)
      }
      ArtworkThumbnail(image: image)
        .frame(width: 44, height: 44)
        .cornerRadius(6)
      VStack(alignment: .leading, spacing: 4) {
        Text(episode.title)
          .font(.headline)
        Text(episode.podcastTitle)
          .font(.subheadline)
          .foregroundStyle(.secondary)
        HStack(spacing: 12) {
          if let duration = episode.duration {
            Label(durationString(duration), systemImage: "clock")
              .font(.caption)
              .foregroundStyle(.secondary)
          }
          Label(byteCountString(episode.fileSize), systemImage: "externaldrive")
            .font(.caption)
            .foregroundStyle(.secondary)
          if let createdAt = episode.createdAt {
            Label(
              createdAt.formatted(date: .abbreviated, time: .omitted),
              systemImage: "calendar"
            )
            .font(.caption)
            .foregroundStyle(.secondary)
          }
        }
      }
    }
    #if os(macOS)
      .contextMenu {
        Button("Show in Finder", systemImage: "folder") {
          NSWorkspace.shared.activateFileViewerSelecting([episode.fileURL])
        }
      }
    #endif
    .task {
      if image == nil {
        image = await artworkLoader.thumbnail(
          for: episode.fileURL,
          fallbackArtworkURL: episode.artworkURL
        )
      }
    }
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
