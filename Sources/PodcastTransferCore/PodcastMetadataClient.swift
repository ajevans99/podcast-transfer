import Dependencies
import Foundation
import GRDB
import OSLog

public struct PodcastMetadataClient: Sendable {
  /// Returns a map keyed by filename (lastPathComponent) to enriched episode metadata.
  public var loadMetadata: @Sendable (_ databaseURL: URL?) async throws -> [String: EpisodeMetadata]

  public init(
    loadMetadata:
      @escaping @Sendable (_ databaseURL: URL?) async throws -> [String: EpisodeMetadata]
  ) {
    self.loadMetadata = loadMetadata
  }
}

extension PodcastMetadataClient {
  public static func live(
    defaultDatabaseURL: URL = PodcastLibraryPaths.defaultApplePodcastsDatabase()
  ) -> Self {
    Self { databaseURL in
      let dbURL = databaseURL ?? defaultDatabaseURL
      let logger = Logger(subsystem: "PodcastTransfer", category: "Metadata")

      return try PodcastLibraryAccess.withAccess {
        guard FileManager.default.fileExists(atPath: dbURL.path) else { return [:] }

        let db = try PodcastLibraryAccess.openReadOnlyDatabase(at: dbURL)
        return try db.read { database in
          func materializeArtworkURL(_ raw: String?) -> URL? {
            guard var raw else { return nil }

            // Apple artwork template URLs often contain {w} and {h} placeholders.
            raw = raw.replacingOccurrences(of: "{w}", with: "300")
            raw = raw.replacingOccurrences(of: "{h}", with: "300")

            // If the template still contains other placeholders, don't return an invalid URL.
            if raw.contains("{") { return nil }
            return URL(string: raw)
          }

          var metadata: [String: EpisodeMetadata] = [:]

          // Column names are resolved dynamically because Apple reshapes this Core Data
          // schema across macOS releases (see PodcastLibrarySchema).
          guard let sql = try PodcastLibrarySchema.episodeSelectSQL(database) else {
            return [:]
          }

          do {
            let rows = try Row.fetchAll(database, sql: sql)
            logger.debug("Read \(rows.count, privacy: .public) episode rows from ZMTEPISODE")

            for row in rows {
              guard let assetURLString: String = row["assetURL"],
                let assetURL = URL(string: assetURLString)
              else { continue }

              let key = assetURL.lastPathComponent
              let title: String? = row["episodeTitle"]
              let podcastTitle: String? = row["podcastTitle"]
              let author: String? = row["author"]
              let durationSeconds: Double? = row["duration"]

              let episodeArtworkTemplateURL: String? = row["episodeArtworkTemplateURL"]
              let podcastImageURL: String? = row["podcastImageURL"]
              let podcastArtworkTemplateURL: String? = row["podcastArtworkTemplateURL"]

              let artworkURL =
                materializeArtworkURL(episodeArtworkTemplateURL)
                ?? materializeArtworkURL(podcastImageURL)
                ?? materializeArtworkURL(podcastArtworkTemplateURL)

              metadata[key] = EpisodeMetadata(
                title: title,
                podcastTitle: podcastTitle,
                author: author,
                duration: durationSeconds,
                artworkURL: artworkURL
              )
            }
          } catch {
            logger.error("Metadata query failed: \(error.localizedDescription, privacy: .public)")
            return [:]
          }

          logger.debug("Returning \(metadata.count, privacy: .public) metadata entries")
          return metadata
        }
      }
    }
  }

  public static let preview = PodcastMetadataClient { _ in [:] }
}

extension PodcastMetadataClient: DependencyKey {
  public static let liveValue: Self = .live()
  public static let previewValue: Self = .preview
  public static let testValue: Self = .init { _ in [:] }
}

extension DependencyValues {
  public var podcastMetadata: PodcastMetadataClient {
    get { self[PodcastMetadataClient.self] }
    set { self[PodcastMetadataClient.self] = newValue }
  }
}
