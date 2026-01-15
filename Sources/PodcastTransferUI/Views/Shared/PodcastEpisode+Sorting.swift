import Foundation
import PodcastTransferCore

extension PodcastEpisode {
  var createdAtSortable: Date {
    createdAt ?? .distantPast
  }

  var durationSortable: TimeInterval {
    duration ?? 0
  }
}
