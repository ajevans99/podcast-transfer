import Dependencies
import Foundation
import GRDB
import OSLog
import Sharing

public struct PodcastLibraryClient: Sendable {
  public var loadEpisodes: @Sendable () async throws -> [PodcastEpisode]

  public init(loadEpisodes: @escaping @Sendable () async throws -> [PodcastEpisode]) {
    self.loadEpisodes = loadEpisodes
  }
}

extension PodcastLibraryClient {
  public static func live(
    databaseURL: URL = PodcastLibraryPaths.defaultApplePodcastsDatabase()
  ) -> Self {
    let logger = Logger(subsystem: "PodcastTransfer", category: "Library")

    return Self { @Sendable in
      guard FileManager.default.fileExists(atPath: databaseURL.path) else {
        logger.debug("Podcasts DB missing at \(databaseURL.path, privacy: .public)")
        return []
      }

      func materializeArtworkURL(_ raw: String?) -> URL? {
        guard var raw else { return nil }
        raw = raw.replacingOccurrences(of: "{w}", with: "300")
        raw = raw.replacingOccurrences(of: "{h}", with: "300")
        raw = raw.replacingOccurrences(of: "{f}", with: "jpg")
        if raw.contains("{") { return nil }
        return URL(string: raw)
      }

      func dateFromAppleTimestamp(_ value: Double?) -> Date? {
        guard let value else { return nil }
        // Apple uses CFAbsoluteTime-style timestamps (seconds since 2001-01-01).
        return Date(timeIntervalSinceReferenceDate: value)
      }

      let resourceKeys: Set<URLResourceKey> = [
        .isRegularFileKey,
        .fileSizeKey,
        .creationDateKey,
        .contentModificationDateKey,
      ]

      let db = try DatabaseQueue(path: databaseURL.path)
      return try db.read { database in
        let sql = """
          SELECT
            e.ZTITLE AS episodeTitle,
            p.ZTITLE AS podcastTitle,
            COALESCE(e.ZAUTHOR, p.ZAUTHOR) AS author,
            e.ZDURATION AS duration,
            e.ZASSETURL AS assetURL,
            e.ZDOWNLOADDATE AS downloadDate,
            e.ZPUBDATE AS pubDate,
            e.ZARTWORKTEMPLATEURL AS episodeArtworkTemplateURL,
            p.ZIMAGEURL AS podcastImageURL,
            p.ZARTWORKTEMPLATEURL AS podcastArtworkTemplateURL
          FROM ZMTEPISODE e
          LEFT JOIN ZMTPODCAST p
            ON p.Z_PK = e.ZPODCAST
          WHERE e.ZASSETURL IS NOT NULL
          """

        let rows = try Row.fetchAll(database, sql: sql)
        logger.debug("Loaded \(rows.count, privacy: .public) downloaded rows from SQLite")

        var episodes: [PodcastEpisode] = []
        episodes.reserveCapacity(rows.count)

        for row in rows {
          guard let assetURLString: String = row["assetURL"],
            let fileURL = URL(string: assetURLString)
          else { continue }

          // Only show files that still exist on disk.
          let resourceValues = try? fileURL.resourceValues(forKeys: resourceKeys)
          guard resourceValues?.isRegularFile == true else { continue }
          guard fileURL.isAudioFile else { continue }

          let size = resourceValues?.fileSize.map(Int64.init) ?? 0
          let createdAt =
            dateFromAppleTimestamp(row["downloadDate"]) ?? dateFromAppleTimestamp(row["pubDate"])
            ?? resourceValues?.creationDate
            ?? resourceValues?.contentModificationDate

          let episodeTitle: String? = row["episodeTitle"]
          let podcastTitle: String? = row["podcastTitle"]
          let author: String? = row["author"]
          let duration: Double? = row["duration"]

          let episodeArtworkTemplateURL: String? = row["episodeArtworkTemplateURL"]
          let podcastImageURL: String? = row["podcastImageURL"]
          let podcastArtworkTemplateURL: String? = row["podcastArtworkTemplateURL"]

          let artworkURL =
            materializeArtworkURL(episodeArtworkTemplateURL)
            ?? materializeArtworkURL(podcastImageURL)
            ?? materializeArtworkURL(podcastArtworkTemplateURL)

          episodes.append(
            PodcastEpisode(
              title: episodeTitle ?? fileURL.deletingPathExtension().lastPathComponent,
              podcastTitle: podcastTitle ?? "Unknown Podcast",
              author: author,
              duration: duration,
              fileURL: fileURL,
              fileSize: size,
              createdAt: createdAt,
              artworkURL: artworkURL
            )
          )
        }

        // UI sorts again, but keep a sensible default here too.
        return episodes.sorted { lhs, rhs in
          (lhs.createdAt ?? .distantPast) > (rhs.createdAt ?? .distantPast)
        }
      }
    }
  }

  public static let preview: Self = .init { @Sendable in
    [
      PodcastEpisode(
        title: "Swim Better, Episode 1",
        podcastTitle: "Swim Pro Radio",
        author: "Swim Pro",
        duration: 1_200,
        fileURL: URL(fileURLWithPath: "/tmp/swim-pro-1.m4a"),
        fileSize: 48_000_000,
        createdAt: Date()
      ),
      PodcastEpisode(
        title: "Mindful Running",
        podcastTitle: "Run Club",
        author: "Run Club",
        duration: 1_800,
        fileURL: URL(fileURLWithPath: "/tmp/run-club-1.m4a"),
        fileSize: 64_000_000,
        createdAt: Date()
      ),
    ]
  }
}

extension PodcastLibraryClient: DependencyKey {
  public static let liveValue = PodcastLibraryClient.live()
  public static let previewValue = PodcastLibraryClient.preview
  public static let testValue = PodcastLibraryClient { @Sendable in
    unimplemented("PodcastLibraryClient.loadEpisodes", placeholder: [])
  }
}

extension DependencyValues {
  public var podcastLibrary: PodcastLibraryClient {
    get { self[PodcastLibraryClient.self] }
    set { self[PodcastLibraryClient.self] = newValue }
  }
}

extension URL {
  fileprivate var isAudioFile: Bool {
    let allowedExtensions: Set<String> = ["m4a", "mp3", "aac", "wav", "aiff", "aif"]
    return allowedExtensions.contains(pathExtension.lowercased())
  }
}
