import Dependencies
import Foundation

public struct DestinationClient: Sendable {
  public var listEpisodes: @Sendable (_ destination: URL) async throws -> [PodcastEpisode]
  public var deleteEpisode: @Sendable (_ fileURL: URL) async throws -> Void

  public init(
    listEpisodes: @escaping @Sendable (_ destination: URL) async throws -> [PodcastEpisode],
    deleteEpisode: @escaping @Sendable (_ fileURL: URL) async throws -> Void
  ) {
    self.listEpisodes = listEpisodes
    self.deleteEpisode = deleteEpisode
  }
}

extension DestinationClient {
  public static func live(fileManager: FileManager = .default) -> Self {
    let fileManager = UncheckedSendable(fileManager)

    return Self { destination in
      let resourceKeys: Set<URLResourceKey> = [
        .isRegularFileKey,
        .fileSizeKey,
        .creationDateKey,
        .contentModificationDateKey,
      ]
      guard fileManager.wrappedValue.fileExists(atPath: destination.path) else { return [] }

      let urls =
        (fileManager.wrappedValue.enumerator(
          at: destination,
          includingPropertiesForKeys: Array(resourceKeys),
          options: [.skipsHiddenFiles, .skipsPackageDescendants]
        )?.allObjects as? [URL]) ?? []
      var episodes: [PodcastEpisode] = []

      for fileURL in urls {
        let values = try fileURL.resourceValues(forKeys: resourceKeys)
        guard values.isRegularFile == true else { continue }
        guard fileURL.isAudioFile else { continue }
        let size = values.fileSize.map(Int64.init) ?? 0
        let title = fileURL.deletingPathExtension().lastPathComponent
        let podcastTitle = fileURL.deletingLastPathComponent().lastPathComponent
        let createdAt = values.creationDate ?? values.contentModificationDate

        episodes.append(
          PodcastEpisode(
            title: title,
            podcastTitle: podcastTitle,
            author: nil,
            duration: nil,
            fileURL: fileURL,
            fileSize: size,
            createdAt: createdAt
          )
        )
      }

      return episodes.sorted { lhs, rhs in
        if lhs.podcastTitle == rhs.podcastTitle {
          return lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
        }
        return lhs.podcastTitle.localizedStandardCompare(rhs.podcastTitle) == .orderedAscending
      }
    } deleteEpisode: { fileURL in
      try fileManager.wrappedValue.removeItem(at: fileURL)
    }
  }

  public static let preview = DestinationClient(
    listEpisodes: { _ in [] },
    deleteEpisode: { _ in }
  )
}

extension DestinationClient: DependencyKey {
  public static let liveValue: Self = .live()
  public static let previewValue: Self = .preview
  public static let testValue: Self = .init(
    listEpisodes: { _ in unimplemented("DestinationClient.listEpisodes", placeholder: []) },
    deleteEpisode: { _ in unimplemented("DestinationClient.deleteEpisode") }
  )
}

extension DependencyValues {
  public var destinationClient: DestinationClient {
    get { self[DestinationClient.self] }
    set { self[DestinationClient.self] = newValue }
  }
}

extension URL {
  fileprivate var isAudioFile: Bool {
    let allowedExtensions: Set<String> = ["m4a", "mp3", "aac", "wav", "aiff", "aif"]
    return allowedExtensions.contains(pathExtension.lowercased())
  }
}
