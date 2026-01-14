import Dependencies
import Foundation
import OSLog
import Observation
import PodcastTransferCore
import Sharing

@Observable
@MainActor
public final class PodcastTransferViewModel {
  private let logger = Logger(subsystem: "PodcastTransfer", category: "ViewModel")

  @ObservationIgnored
  @Dependency(\.podcastLibrary) var podcastLibrary

  @ObservationIgnored
  @Dependency(\.transferClient) var transferClient

  @ObservationIgnored
  @Dependency(\.destinationClient) var destinationClient

  @ObservationIgnored
  @Shared(.podcastDestination) public var persistedDestination: URL? = nil

  public private(set) var episodes: [PodcastEpisode] = []
  public private(set) var destinationEpisodes: [PodcastEpisode] = []
  public private(set) var selectedEpisodeIDs: Set<String> = []
  public private(set) var state: TransferState = .idle
  public private(set) var isLoading = false
  public private(set) var lastError: String?

  public init() {}

  public func loadEpisodes() async {
    isLoading = true
    lastError = nil
    do {
      logger.debug("Loading episodes from SQLite-backed library…")
      episodes = try await podcastLibrary.loadEpisodes()
      let count = episodes.count
      logger.debug("Loaded \(count, privacy: .public) episodes")
      selectedEpisodeIDs = selectedEpisodeIDs.intersection(Set(episodes.map(\.id)))
      state = .idle
    } catch {
      lastError = error.localizedDescription
      state = .failed(error.localizedDescription)
      logger.error(
        "Failed to load episodes: \(error.localizedDescription, privacy: .public)"
      )
    }
    isLoading = false
  }

  public func loadDestinationEpisodes() async {
    guard let destination = persistedDestination else { return }
    do {
      destinationEpisodes = try await destinationClient.listEpisodes(destination)
    } catch {
      lastError = error.localizedDescription
    }
  }

  public func setDestination(_ url: URL) {
    $persistedDestination.withLock { $0 = url }
    Task { await loadDestinationEpisodes() }
  }

  public func toggleSelection(for episode: PodcastEpisode) {
    if selectedEpisodeIDs.contains(episode.id) {
      selectedEpisodeIDs.remove(episode.id)
    } else {
      selectedEpisodeIDs.insert(episode.id)
    }
  }

  public func selectAll() {
    selectedEpisodeIDs = Set(episodes.map(\.id))
  }

  public func clearSelection() {
    selectedEpisodeIDs.removeAll()
  }

  public func transferAll() async {
    guard let destination = persistedDestination else {
      state = .failed("Select a destination first.")
      return
    }

    let chosenEpisodes: [PodcastEpisode] = episodes.filter { selectedEpisodeIDs.contains($0.id) }

    guard !chosenEpisodes.isEmpty else {
      state = .failed("Select at least one episode to transfer.")
      return
    }

    state = .inProgress(progress: .init(completed: 0, total: chosenEpisodes.count))

    do {
      let outcome = try await transferClient.transfer(chosenEpisodes, destination)
      state = .finished(outcome)
      await loadDestinationEpisodes()
    } catch {
      state = .failed(error.localizedDescription)
    }
  }

  public func deleteDestinationEpisode(_ episode: PodcastEpisode) async {
    do {
      try await destinationClient.deleteEpisode(episode.fileURL)
      await loadDestinationEpisodes()
    } catch {
      lastError = error.localizedDescription
    }
  }
}
