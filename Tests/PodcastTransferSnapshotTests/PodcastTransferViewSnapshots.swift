import AppKit
import Dependencies
import PodcastTransferCore
import PodcastTransferFeature
import SnapshotTesting
import SwiftUI
import Testing

@testable import PodcastTransferApp
@testable import PodcastTransferUI

/// To record snapshots: `SNAPSHOT_TESTING_RECORD=all make test`
@Suite
struct PodcastTransferViewSnapshots {
  @MainActor
  @Test
  func listViewSnapshot() async {
    let snapshotLibrary = PodcastLibraryClient { @Sendable in
      sampleEpisodes()
    }

    let view = await withDependencies {
      $0.podcastLibrary = snapshotLibrary
      $0.transferClient = .preview
    } operation: {
      let viewModel = PodcastTransferViewModel()
      await viewModel.loadEpisodes()
      await viewModel.loadDestinationEpisodes()
      return PodcastTransferView(viewModel: viewModel)
    }

    assertSnapshotView(view, size: .init(width: 900, height: 700))
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

    assertSnapshotView(view, size: .init(width: 420, height: 420))
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

    assertSnapshotView(view, size: .init(width: 420, height: 420))
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

    assertSnapshotView(view, size: .init(width: 520, height: 520))
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

    assertSnapshotView(view, size: .init(width: 700, height: 520))
  }

  @MainActor
  @Test
  func episodesTableSnapshot() async {
    let view = EpisodesTableSnapshotHost(episodes: sampleEpisodes())

    assertSnapshotView(view, size: .init(width: 700, height: 520))
  }

  @MainActor
  @Test
  func aboutViewSnapshot() async {
    let info = AboutInfo(
      bundleDisplayName: "Podcast Transfer",
      version: "1.2.3",
      buildNumber: "456",
      tagline: "Transfer your Apple Podcasts downloads to any folder.",
      author: "",
      homepageURL: URL(string: "https://example.com"),
      dataAccessNote: "",
      gitSHA: "abcdef1",
      gitTag: "v1.2.3",
      buildIdentifier: "CI",
      acknowledgements: [
        .init(
          name: "swift-dependencies",
          url: URL(string: "https://github.com/pointfreeco/swift-dependencies")
        ),
        .init(
          name: "swift-sharing",
          url: URL(string: "https://github.com/pointfreeco/swift-sharing")
        ),
      ]
    )

    let view = withDependencies {
      $0.aboutInfoClient = AboutInfoClient(load: { info })
    } operation: {
      AboutView()
    }

    assertSnapshotView(view, size: .init(width: 560, height: 520))
  }
}

@MainActor
private func assertSnapshotView<V: View>(
  _ view: V,
  size: CGSize,
  fileID: StaticString = #fileID,
  filePath: StaticString = #filePath,
  testName: String = #function,
  line: UInt = #line,
  column: UInt = #column
) {
  let rootView =
    view
    .frame(width: size.width, height: size.height, alignment: .topLeading)
    .background(Color(nsColor: .windowBackgroundColor))
    .environment(\.colorScheme, .light)

  let host = NSHostingView(rootView: rootView)
  host.frame = .init(origin: .zero, size: size)
  host.appearance = NSAppearance(named: .aqua)
  host.wantsLayer = true
  host.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor

  // Some AppKit-backed SwiftUI components (notably `Table` and certain `List` styles)
  // only fully render once attached to a window and given a layout/display pass.
  let window = NSWindow(
    contentRect: NSRect(origin: .zero, size: size),
    styleMask: [.borderless],
    backing: .buffered,
    defer: false
  )
  window.isReleasedWhenClosed = false
  window.backgroundColor = .windowBackgroundColor
  window.isOpaque = true
  window.hasShadow = false
  window.contentView = host

  host.layoutSubtreeIfNeeded()
  window.displayIfNeeded()
  host.displayIfNeeded()

  // Allow the run loop to process a tiny bit of view work.
  RunLoop.main.run(until: Date().addingTimeInterval(0.02))

  assertSnapshot(
    of: host,
    as: .image,
    fileID: fileID,
    file: filePath,
    testName: testName,
    line: line,
    column: column
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
