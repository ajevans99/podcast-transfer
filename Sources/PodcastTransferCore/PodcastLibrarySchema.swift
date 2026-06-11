import GRDB
import OSLog

/// Builds the episode query from the columns that actually exist in the live Apple
/// Podcasts database.
///
/// Apple reshapes the `ZMTEPISODE` / `ZMTPODCAST` Core Data tables across macOS releases.
/// Notably, in macOS 27 the downloaded-file URL and duration moved out of `ZMTEPISODE`
/// into a separate `ZMTMEDIAENCLOSURE` table (`ZLOCALURL`, `ZDURATION`), joined via
/// `ZMTEPISODE.ZCURRENTMEDIAENCLOSURE`. Hard-coding column names breaks the app on every
/// OS update, so we resolve each logical field from a prioritized list of candidate
/// (table, column) pairs discovered at runtime, falling back to `NULL` when absent.
enum PodcastLibrarySchema {
  private static let logger = Logger(subsystem: "PodcastTransfer", category: "Schema")

  /// Table aliases used in the generated SQL.
  private enum Table: String {
    case episode = "e"
    case podcast = "p"
    case enclosure = "m"
  }

  static func episodeSelectSQL(_ database: Database) throws -> String? {
    func columns(_ table: String) -> Set<String> {
      Set((try? database.columns(in: table).map(\.name)) ?? [])
    }

    let episodeColumns = columns("ZMTEPISODE")
    let podcastColumns = columns("ZMTPODCAST")
    let enclosureColumns = columns("ZMTMEDIAENCLOSURE")

    let hasPodcastJoin = episodeColumns.contains("ZPODCAST") && podcastColumns.contains("Z_PK")
    let hasEnclosureJoin =
      episodeColumns.contains("ZCURRENTMEDIAENCLOSURE") && enclosureColumns.contains("Z_PK")

    func columns(for table: Table) -> Set<String> {
      switch table {
      case .episode: return episodeColumns
      case .podcast: return hasPodcastJoin ? podcastColumns : []
      case .enclosure: return hasEnclosureJoin ? enclosureColumns : []
      }
    }

    var usedTables: Set<Table> = []

    /// Resolves the first available `table.column` expression from the candidate list.
    func resolve(_ sources: [(Table, [String])]) -> String? {
      for (table, candidates) in sources {
        let available = columns(for: table)
        if let column = candidates.first(where: available.contains) {
          usedTables.insert(table)
          return "\(table.rawValue).\(column)"
        }
      }
      return nil
    }

    // The local file URL is essential; without it there is nothing to transfer.
    guard
      let assetExpr = resolve([
        (.episode, ["ZASSETURL", "ZLOCALURL", "ZFILEURL"]),
        (.enclosure, ["ZLOCALURL", "ZASSETURL"]),
      ])
    else {
      logger.error("No recognizable local-file URL column found; schema unsupported")
      return nil
    }

    let fields: [(alias: String, sources: [(Table, [String])])] = [
      ("episodeTitle", [(.episode, ["ZTITLE", "ZCLEANEDTITLE", "ZITUNESTITLE"])]),
      ("duration", [(.episode, ["ZDURATION"]), (.enclosure, ["ZDURATION"])]),
      (
        "downloadDate",
        [
          (.episode, ["ZDOWNLOADDATE", "ZIMPORTDATE", "ZADDEDDATE"]),
          (.enclosure, ["ZDOWNLOADDATE"]),
        ]
      ),
      ("pubDate", [(.episode, ["ZPUBDATE", "ZPUBLISHEDDATE", "ZRELEASEDATE"])]),
      (
        "episodeArtworkTemplateURL",
        [
          (.episode, ["ZARTWORKTEMPLATEURL", "ZARTWORKURL"]), (.enclosure, ["ZARTWORKTEMPLATEURL"]),
        ]
      ),
      ("podcastTitle", [(.podcast, ["ZTITLE", "ZCLEANEDTITLE"])]),
      ("podcastImageURL", [(.podcast, ["ZIMAGEURL", "ZARTWORKURL"])]),
      ("podcastArtworkTemplateURL", [(.podcast, ["ZARTWORKTEMPLATEURL"])]),
    ]

    var selectClauses = ["\(assetExpr) AS assetURL"]
    for field in fields {
      if let expr = resolve(field.sources) {
        selectClauses.append("\(expr) AS \(field.alias)")
      } else {
        selectClauses.append("NULL AS \(field.alias)")
      }
    }

    // Author can live on either the episode or the podcast.
    let episodeAuthor = resolve([(.episode, ["ZAUTHOR"])])
    let podcastAuthor = resolve([(.podcast, ["ZAUTHOR"])])
    switch (episodeAuthor, podcastAuthor) {
    case (let ep?, let pod?): selectClauses.append("COALESCE(\(ep), \(pod)) AS author")
    case (let ep?, nil): selectClauses.append("\(ep) AS author")
    case (nil, let pod?): selectClauses.append("\(pod) AS author")
    case (nil, nil): selectClauses.append("NULL AS author")
    }

    var joins: [String] = []
    if usedTables.contains(.podcast) {
      joins.append("LEFT JOIN ZMTPODCAST p ON p.Z_PK = e.ZPODCAST")
    }
    if usedTables.contains(.enclosure) {
      joins.append("LEFT JOIN ZMTMEDIAENCLOSURE m ON m.Z_PK = e.ZCURRENTMEDIAENCLOSURE")
    }

    let sql = """
      SELECT
        \(selectClauses.joined(separator: ",\n  "))
      FROM ZMTEPISODE e
      \(joins.joined(separator: "\n"))
      WHERE \(assetExpr) IS NOT NULL
      """

    logger.debug("Resolved Podcasts query:\n\(sql, privacy: .public)")
    return sql
  }
}
