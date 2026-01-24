import Dependencies
import Foundation

public struct AboutInfo: Sendable, Equatable {
  public struct Acknowledgement: Identifiable, Sendable, Equatable {
    public var name: String
    public var url: URL?

    public var id: String { name }

    public init(name: String, url: URL?) {
      self.name = name
      self.url = url
    }
  }

  public var bundleDisplayName: String
  public var version: String
  public var buildNumber: String
  public var tagline: String
  public var author: String
  public var homepageURL: URL?
  public var dataAccessNote: String
  public var gitSHA: String
  public var gitTag: String
  public var buildIdentifier: String
  public var acknowledgements: [Acknowledgement]

  public init(
    bundleDisplayName: String,
    version: String,
    buildNumber: String,
    tagline: String,
    author: String,
    homepageURL: URL?,
    dataAccessNote: String,
    gitSHA: String,
    gitTag: String,
    buildIdentifier: String,
    acknowledgements: [Acknowledgement]
  ) {
    self.bundleDisplayName = bundleDisplayName
    self.version = version
    self.buildNumber = buildNumber
    self.tagline = tagline
    self.author = author
    self.homepageURL = homepageURL
    self.dataAccessNote = dataAccessNote
    self.gitSHA = gitSHA
    self.gitTag = gitTag
    self.buildIdentifier = buildIdentifier
    self.acknowledgements = acknowledgements
  }

  public static let preview = AboutInfo(
    bundleDisplayName: "Podcast Transfer",
    version: "0.0.0",
    buildNumber: "0",
    tagline: "Transfer your Apple Podcasts downloads to any folder.",
    author: "",
    homepageURL: URL(string: "https://github.com/ajevans99/podcast-transfer"),
    dataAccessNote: "",
    gitSHA: "",
    gitTag: "",
    buildIdentifier: "",
    acknowledgements: [
      .init(
        name: "swift-dependencies",
        url: URL(string: "https://github.com/pointfreeco/swift-dependencies")
      ),
      .init(
        name: "swift-sharing",
        url: URL(string: "https://github.com/pointfreeco/swift-sharing")
      ),
      .init(
        name: "swift-snapshot-testing",
        url: URL(string: "https://github.com/pointfreeco/swift-snapshot-testing")
      ),
      .init(name: "GRDB.swift", url: URL(string: "https://github.com/groue/GRDB.swift")),
    ]
  )
}

public struct AboutInfoClient: Sendable {
  public var load: @Sendable () -> AboutInfo

  public init(load: @escaping @Sendable () -> AboutInfo) {
    self.load = load
  }
}

extension AboutInfoClient: DependencyKey {
  public static let liveValue = AboutInfoClient(
    load: {
      let bundle = Bundle.main

      func string(_ key: String) -> String {
        bundle.object(forInfoDictionaryKey: key) as? String ?? ""
      }

      let bundleDisplayName =
        (bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
        ?? (bundle.object(forInfoDictionaryKey: "CFBundleName") as? String)
        ?? "Podcast Transfer"

      let version =
        (bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String) ?? "0.0.0"
      let buildNumber = (bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String) ?? "0"
      let tagline =
        string("PodcastTransferTagline").isEmpty
        ? "Transfer your Apple Podcasts downloads to any folder."
        : string("PodcastTransferTagline")

      let homepageURL = URL(string: string("PodcastTransferHomepageURL"))

      return AboutInfo(
        bundleDisplayName: bundleDisplayName,
        version: version,
        buildNumber: buildNumber,
        tagline: tagline,
        author: string("PodcastTransferAuthor"),
        homepageURL: homepageURL,
        dataAccessNote: string("PodcastTransferDataAccessNote"),
        gitSHA: string("PodcastTransferGitSHA"),
        gitTag: string("PodcastTransferGitTag"),
        buildIdentifier: string("PodcastTransferBuildIdentifier"),
        acknowledgements: [
          .init(
            name: "swift-dependencies",
            url: URL(string: "https://github.com/pointfreeco/swift-dependencies")
          ),
          .init(
            name: "swift-sharing",
            url: URL(string: "https://github.com/pointfreeco/swift-sharing")
          ),
          .init(
            name: "swift-snapshot-testing",
            url: URL(string: "https://github.com/pointfreeco/swift-snapshot-testing")
          ),
          .init(name: "GRDB.swift", url: URL(string: "https://github.com/groue/GRDB.swift")),
        ]
      )
    }
  )

  public static let previewValue = AboutInfoClient(load: { .preview })
}

extension DependencyValues {
  public var aboutInfoClient: AboutInfoClient {
    get { self[AboutInfoClient.self] }
    set { self[AboutInfoClient.self] = newValue }
  }
}
