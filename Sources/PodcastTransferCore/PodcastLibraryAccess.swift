import Foundation
import GRDB
import OSLog

/// Manages read access to the Apple Podcasts library, which lives in another app's
/// Group Container.
///
/// On recent macOS releases, opening that database directly returns SQLite error 23
/// (`SQLITE_AUTH`, "authorization denied") because the location is protected by the
/// system's privacy controls (TCC). To read it reliably we:
///
/// 1. Open the database **read-only**, so SQLite never attempts to create the
///    `-wal`/`-shm` sidecar files in the protected directory.
/// 2. Gate every access behind a user-granted, security-scoped bookmark. The user
///    selects the Podcasts Group Container once; we persist a bookmark and reuse it on
///    subsequent launches without prompting again.
public enum PodcastLibraryAccess {
  private static let logger = Logger(subsystem: "PodcastTransfer", category: "Access")

  private static var bookmarkURL: URL {
    let base = FileManager.default.homeDirectoryForCurrentUser
      .appendingPathComponent("Library/Application Support/podcast-transfer", isDirectory: true)
    return base.appendingPathComponent("library-access.bookmark", isDirectory: false)
  }

  /// Whether the user has previously granted access to the Podcasts library.
  public static var hasBookmark: Bool {
    FileManager.default.fileExists(atPath: bookmarkURL.path)
  }

  /// Creates and persists a security-scoped bookmark for a user-selected folder
  /// (typically the Apple Podcasts Group Container) so access survives relaunches.
  public static func storeBookmark(for url: URL) throws {
    let started = url.startAccessingSecurityScopedResource()
    defer { if started { url.stopAccessingSecurityScopedResource() } }

    let data = try url.bookmarkData(
      options: [.withSecurityScope],
      includingResourceValuesForKeys: nil,
      relativeTo: nil
    )

    try FileManager.default.createDirectory(
      at: bookmarkURL.deletingLastPathComponent(),
      withIntermediateDirectories: true
    )
    try data.write(to: bookmarkURL, options: .atomic)
    logger.debug("Stored library access bookmark for \(url.path, privacy: .public)")
  }

  /// Removes any persisted bookmark, forcing the user to re-grant access.
  public static func clearBookmark() {
    try? FileManager.default.removeItem(at: bookmarkURL)
  }

  /// Resolves the persisted bookmark into a security-scoped URL, refreshing it if stale.
  private static func resolveScopedURL() -> URL? {
    guard let data = try? Data(contentsOf: bookmarkURL) else { return nil }

    var isStale = false
    guard
      let url = try? URL(
        resolvingBookmarkData: data,
        options: [.withSecurityScope],
        relativeTo: nil,
        bookmarkDataIsStale: &isStale
      )
    else {
      logger.error("Failed to resolve library access bookmark")
      return nil
    }

    if isStale {
      logger.debug("Library access bookmark is stale; refreshing")
      try? storeBookmark(for: url)
    }

    return url
  }

  /// Runs `body` while holding security-scoped access to the persisted bookmark, if any.
  ///
  /// When no bookmark exists the body still runs, relying on Full Disk Access or other
  /// pre-existing permission. This keeps behavior graceful when the user has granted
  /// access through System Settings instead.
  public static func withAccess<T>(_ body: () throws -> T) rethrows -> T {
    guard let scopedURL = resolveScopedURL() else {
      return try body()
    }

    let started = scopedURL.startAccessingSecurityScopedResource()
    defer { if started { scopedURL.stopAccessingSecurityScopedResource() } }
    return try body()
  }

  /// Opens the database in read-only mode to avoid writing sidecar files into the
  /// protected Group Container.
  public static func openReadOnlyDatabase(at databaseURL: URL) throws -> DatabaseQueue {
    var configuration = Configuration()
    configuration.readonly = true
    return try DatabaseQueue(path: databaseURL.path, configuration: configuration)
  }
}
