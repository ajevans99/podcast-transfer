import Foundation

public struct PodcastEpisode: Codable, Identifiable, Hashable, Sendable {
  public var id: String { fileURL.path }
  public var title: String
  public var podcastTitle: String
  public var author: String?
  public var duration: TimeInterval?
  public var artworkURL: URL?
  public var fileURL: URL
  public var fileSize: Int64
  public var createdAt: Date?

  public init(
    title: String,
    podcastTitle: String,
    author: String? = nil,
    duration: TimeInterval? = nil,
    fileURL: URL,
    fileSize: Int64,
    createdAt: Date?,
    artworkURL: URL? = nil
  ) {
    self.title = title
    self.podcastTitle = podcastTitle
    self.author = author
    self.duration = duration
    self.artworkURL = artworkURL
    self.fileURL = fileURL
    self.fileSize = fileSize
    self.createdAt = createdAt
  }
}

public struct EpisodeMetadata: Sendable, Equatable {
  public var title: String?
  public var podcastTitle: String?
  public var author: String?
  public var duration: TimeInterval?
  public var artworkURL: URL?

  public init(
    title: String? = nil,
    podcastTitle: String? = nil,
    author: String? = nil,
    duration: TimeInterval? = nil,
    artworkURL: URL? = nil
  ) {
    self.title = title
    self.podcastTitle = podcastTitle
    self.author = author
    self.duration = duration
    self.artworkURL = artworkURL
  }
}

public struct TransferOutcome: Sendable, Equatable {
  public var destination: URL
  public var copied: Int
  public var skipped: Int
  public var failed: [TransferFailure]

  public init(destination: URL, copied: Int, skipped: Int, failed: [TransferFailure]) {
    self.destination = destination
    self.copied = copied
    self.skipped = skipped
    self.failed = failed
  }
}

public struct TransferFailure: Sendable, Identifiable, Equatable {
  public var id: URL { source }
  public var source: URL
  public var reason: String

  public init(source: URL, reason: String) {
    self.source = source
    self.reason = reason
  }
}

public enum TransferState: Equatable, Sendable {
  case idle
  case inProgress(progress: Progress)
  case finished(TransferOutcome)
  case failed(String)

  public struct Progress: Equatable, Sendable {
    public var completed: Int
    public var total: Int

    public init(completed: Int, total: Int) {
      self.completed = completed
      self.total = total
    }
  }
}

public struct PodcastLibraryPaths {
  public static func defaultApplePodcastsDirectory() -> URL {
    FileManager.default.homeDirectoryForCurrentUser
      .appendingPathComponent(
        "Library/Group Containers/243LU875E5.groups.com.apple.podcasts/Library/Cache"
      )
  }

  public static func defaultApplePodcastsDatabase() -> URL {
    FileManager.default.homeDirectoryForCurrentUser
      .appendingPathComponent(
        "Library/Group Containers/243LU875E5.groups.com.apple.podcasts/Documents/MTLibrary.sqlite"
      )
  }
}
