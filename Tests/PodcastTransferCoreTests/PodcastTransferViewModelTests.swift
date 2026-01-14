import Dependencies
import Foundation
import PodcastTransferCore
import PodcastTransferFeature
import Testing

@Suite
struct PodcastTransferViewModelTests {
  @MainActor
  @Test
  func loadsEpisodes() async throws {
    let sampleEpisodes = [
      PodcastEpisode(
        title: "Episode 1",
        podcastTitle: "Sample Show",
        author: "Host",
        duration: 600,
        fileURL: URL(fileURLWithPath: "/tmp/sample1.m4a"),
        fileSize: 1_024,
        createdAt: Date(timeIntervalSince1970: 0)
      ),
      PodcastEpisode(
        title: "Episode 2",
        podcastTitle: "Sample Show",
        author: "Host",
        duration: 700,
        fileURL: URL(fileURLWithPath: "/tmp/sample2.m4a"),
        fileSize: 2_048,
        createdAt: Date(timeIntervalSince1970: 10)
      ),
    ]

    let viewModel = withDependencies {
      $0.podcastLibrary = PodcastLibraryClient { @Sendable in sampleEpisodes }
      $0.transferClient = .preview
      $0.podcastMetadata = .preview
      $0.destinationClient = .preview
    } operation: {
      PodcastTransferViewModel()
    }

    await viewModel.loadEpisodes()
    #expect(viewModel.episodes == sampleEpisodes)
    #expect(viewModel.state == TransferState.idle)
  }

  @MainActor
  @Test
  func preventsTransferWithoutDestination() async {
    let viewModel = withDependencies {
      $0.podcastLibrary = PodcastLibraryClient.preview
      $0.transferClient = .preview
      $0.podcastMetadata = .preview
      $0.destinationClient = .preview
    } operation: {
      PodcastTransferViewModel()
    }

    await viewModel.loadEpisodes()
    await viewModel.transferAll()

    if case .failed(let message) = viewModel.state {
      #expect(message.contains("Select a destination"))
    } else {
      #expect(Bool(false), "Expected transfer to fail without a destination")
    }
  }

  @MainActor
  @Test
  func transfersEpisodes() async throws {
    let destination = URL(fileURLWithPath: NSTemporaryDirectory())
      .appendingPathComponent("podcast-transfer-tests")
    try? FileManager.default.removeItem(at: destination)

    let episodes = [
      PodcastEpisode(
        title: "Copy Me",
        podcastTitle: "Testing",
        author: nil,
        duration: nil,
        fileURL: makeTemporaryEpisode(named: "copy-me.m4a"),
        fileSize: 32,
        createdAt: nil
      )
    ]

    let viewModel = withDependencies {
      $0.podcastLibrary = PodcastLibraryClient { @Sendable in episodes }
      $0.transferClient = .live(fileManager: .default)
      $0.podcastMetadata = .preview
      $0.destinationClient = .live(fileManager: .default)
    } operation: {
      PodcastTransferViewModel()
    }

    viewModel.setDestination(destination)
    await viewModel.loadEpisodes()
    viewModel.selectAll()
    await viewModel.transferAll()

    if case .finished(let outcome) = viewModel.state {
      #expect(outcome.copied == 1)
      #expect(
        FileManager.default.fileExists(
          atPath:
            destination
            .appendingPathComponent("Testing")
            .appendingPathComponent("Copy Me.m4a")
            .path
        )
      )
    } else {
      #expect(Bool(false), "Expected transfer to finish successfully")
    }
  }
}

private func makeTemporaryEpisode(named name: String) -> URL {
  let url = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(name)
  try? "demo".data(using: .utf8)?.write(to: url)
  return url
}
