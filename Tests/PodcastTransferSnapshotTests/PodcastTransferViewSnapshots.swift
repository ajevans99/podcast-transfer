import AppKit
import Dependencies
import PodcastTransferFeature
import PodcastTransferUI
import SnapshotTesting
import SwiftUI
import Testing

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

    let shouldRecord = ProcessInfo.processInfo.environment["RECORD_SNAPSHOTS"] == "1"

    let host = NSHostingView(rootView: view)
    host.frame = .init(x: 0, y: 0, width: 900, height: 700)

    let message = verifySnapshot(
      of: host,
      as: .image,
      named: "podcast-transfer",
      record: shouldRecord
    )

    if shouldRecord {
      return
    }

    if let message {
      #expect(Bool(false), "Snapshot mismatch: \(message)")
    }
  }
}
