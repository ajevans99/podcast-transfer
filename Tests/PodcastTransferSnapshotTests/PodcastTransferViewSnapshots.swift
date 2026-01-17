import AppKit
import Dependencies
import PodcastTransferFeature
import PodcastTransferCore
@testable import PodcastTransferUI
import SnapshotTesting
import SwiftUI
import Testing

/// SNAPSHOT_TESTING_RECORD = 1`
@Suite
struct PodcastTransferViewSnapshots {
  @MainActor
  @Test
  func listViewSnapshot() async {
    let view = withDependencies {
      $0.podcastLibrary = .preview
      $0.transferClient = .preview
    } operation: {
      PodcastTransferView()
    }

    assertSnapshotView(view, name: "podcast-transfer", size: .init(width: 900, height: 700))
  }

  @MainActor
  @Test
  func destinationInspectorEmptySnapshot() async {
    let view = DestinationInspectorView(
      destination: nil,
      episodes: [],
      artworkLoader: ArtworkLoader(),
      onChooseFolder: {},
      onDelete: { _ in }
    )

    assertSnapshotView(view, name: "destination-empty", size: .init(width: 420, height: 420))
  }

  @MainActor
  @Test
  func destinationInspectorMountedEmptySnapshot() async {
    let view = DestinationInspectorView(
      destination: URL(fileURLWithPath: NSTemporaryDirectory()),
      episodes: [],
      artworkLoader: ArtworkLoader(),
      onChooseFolder: {},
      onDelete: { _ in }
    )

    assertSnapshotView(view, name: "destination-mounted-empty", size: .init(width: 420, height: 420))
  }

  @MainActor
  @Test
  func destinationInspectorWithEpisodesSnapshot() async {
    let view = DestinationInspectorView(
      destination: URL(fileURLWithPath: NSTemporaryDirectory()),
      episodes: sampleEpisodes(),
      artworkLoader: ArtworkLoader(),
      onChooseFolder: {},
      onDelete: { _ in }
    )

    assertSnapshotView(view, name: "destination-with-episodes", size: .init(width: 520, height: 520))
  }

  @MainActor
  @Test
  func episodesListSnapshot() async {
    let view = EpisodesListView(
      episodes: sampleEpisodes(),
      selectedEpisodeIDs: [],
      isLoading: false,
      artworkLoader: ArtworkLoader(),
      onToggle: { _ in },
      onRefresh: {}
    )

    assertSnapshotView(view, name: "episodes-list", size: .init(width: 700, height: 520))
  }

  @MainActor
  @Test
  func episodesTableSnapshot() async {
    let view = EpisodesTableSnapshotHost(episodes: sampleEpisodes())

    assertSnapshotView(view, name: "episodes-table", size: .init(width: 700, height: 520))
  }
}

@MainActor
private func assertSnapshotView<V: View>(
  _ view: V,
  name: String,
  size: CGSize
) {
  let host = NSHostingView(rootView: view)
  host.frame = .init(origin: .zero, size: size)

  assertSnapshot(
    of: host,
    as: .image,
    named: name
  )
}

private func sampleEpisodes() -> [PodcastEpisode] {
  [
    PodcastEpisode(
      title: "A Short Episode",
      podcastTitle: "Sample Show",
      author: "Host",
      duration: 1_200,
      fileURL: URL(fileURLWithPath: "/tmp/sample1.m4a"),
      fileSize: 12_345_678,
      createdAt: Date(timeIntervalSince1970: 1_725_000_000)
    ),
    PodcastEpisode(
      title: "A Much Longer Episode Title That Wraps",
      podcastTitle: "Another Podcast",
      author: "Host",
      duration: 2_600,
      fileURL: URL(fileURLWithPath: "/tmp/sample2.m4a"),
      fileSize: 98_765_432,
      createdAt: Date(timeIntervalSince1970: 1_725_100_000)
    ),
  ]
}

private struct EpisodesTableSnapshotHost: View {
  let episodes: [PodcastEpisode]
  @State private var selected: Set<String> = []
  @State private var sortOrder: [KeyPathComparator<PodcastEpisode>] = [
    .init(\PodcastEpisode.createdAtSortable, order: .reverse)
  ]

  var body: some View {
    EpisodesTableView(
      episodes: episodes,
      selectedEpisodeIDs: $selected,
      isLoading: false,
      sortOrder: $sortOrder,
      artworkLoader: ArtworkLoader(),
      onSelectionChanged: { selected = $0 },
      onRefresh: {}
    )
  }
}
