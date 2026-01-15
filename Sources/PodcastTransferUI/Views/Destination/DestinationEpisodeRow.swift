import PodcastTransferCore
import SwiftUI

struct DestinationEpisodeRow: View {
  let episode: PodcastEpisode
  var artworkLoader: ArtworkLoader
  var onDelete: () -> Void

  var body: some View {
    HStack(alignment: .top, spacing: 10) {
      VStack(alignment: .leading, spacing: 4) {
        Text(episode.title)
          .font(.subheadline)
          .lineLimit(2)

        Text(episode.podcastTitle)
          .font(.caption)
          .foregroundStyle(.secondary)
          .lineLimit(1)

        HStack(spacing: 10) {
          if let createdAt = episode.createdAt {
            Label(
              createdAt.formatted(date: .abbreviated, time: .shortened),
              systemImage: "calendar"
            )
          }
          if let duration = episode.duration {
            Label(durationString(duration), systemImage: "clock")
          }
          Label(byteCountString(episode.fileSize), systemImage: "externaldrive")
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
      }

      Spacer(minLength: 0)

      Button(role: .destructive) {
        onDelete()
      } label: {
        Image(systemName: "trash")
      }
      .buttonStyle(.borderless)
      .help("Delete")
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
