import Foundation
import Sharing

extension SharedReaderKey where Self == FileStorageKey<URL?>.Default {
  /// Persists the last selected device destination on disk so it survives restarts.
  public static var podcastDestination: Self {
    let base = FileManager.default.homeDirectoryForCurrentUser
      .appendingPathComponent("Library/Application Support/podcast-transfer", isDirectory: true)
    let fileURL = base.appendingPathComponent("destination.json", isDirectory: false)
    return Self[.fileStorage(fileURL), default: nil]
  }
}
