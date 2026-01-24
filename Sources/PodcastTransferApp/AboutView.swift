import Foundation
import SwiftUI

struct AboutView: View {
  private struct Acknowledgement: Identifiable {
    let name: String
    let url: URL?

    var id: String { name }
  }

  private let acknowledgementItems: [Acknowledgement] = [
    Acknowledgement(
      name: "swift-dependencies",
      url: URL(string: "https://github.com/pointfreeco/swift-dependencies")
    ),
    Acknowledgement(
      name: "swift-sharing",
      url: URL(string: "https://github.com/pointfreeco/swift-sharing")
    ),
    Acknowledgement(
      name: "swift-snapshot-testing",
      url: URL(string: "https://github.com/pointfreeco/swift-snapshot-testing")
    ),
    Acknowledgement(name: "GRDB.swift", url: URL(string: "https://github.com/groue/GRDB.swift")),
  ]

  private struct AppInfo {
    var bundleDisplayName: String {
      Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
        ?? Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String
        ?? "Podcast Transfer"
    }

    var version: String {
      Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        ?? "0.0.0"
    }

    var buildNumber: String {
      Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String
        ?? "0"
    }

    var tagline: String {
      Bundle.main.object(forInfoDictionaryKey: "PodcastTransferTagline") as? String
        ?? "Transfer your Apple Podcasts downloads to any folder."
    }

    var author: String {
      Bundle.main.object(forInfoDictionaryKey: "PodcastTransferAuthor") as? String
        ?? ""
    }

    var homepageURL: URL? {
      guard
        let value = Bundle.main.object(forInfoDictionaryKey: "PodcastTransferHomepageURL")
          as? String
      else {
        return nil
      }
      return URL(string: value)
    }

    var dataAccessNote: String {
      Bundle.main.object(forInfoDictionaryKey: "PodcastTransferDataAccessNote") as? String
        ?? ""
    }

    var gitSHA: String {
      Bundle.main.object(forInfoDictionaryKey: "PodcastTransferGitSHA") as? String
        ?? ""
    }

    var gitTag: String {
      Bundle.main.object(forInfoDictionaryKey: "PodcastTransferGitTag") as? String
        ?? ""
    }

    var buildIdentifier: String {
      Bundle.main.object(forInfoDictionaryKey: "PodcastTransferBuildIdentifier") as? String
        ?? ""
    }
  }

  private let info = AppInfo()

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      header
      Divider()
      metadata
      if !info.dataAccessNote.isEmpty {
        Divider()
        dataAccess
      }
      Divider()
      acknowledgements
    }
    .padding(20)
    .frame(width: 520)
  }

  private var header: some View {
    HStack(alignment: .top, spacing: 16) {
      Image(nsImage: NSApp.applicationIconImage)
        .resizable()
        .frame(width: 64, height: 64)

      VStack(alignment: .leading, spacing: 6) {
        Text(info.bundleDisplayName)
          .font(.title2)
          .fontWeight(.semibold)
        Text(info.tagline)
          .foregroundStyle(.secondary)

        if let homepage = info.homepageURL {
          Link(homepage.absoluteString, destination: homepage)
            .font(.callout)
        }
      }
    }
  }

  @ViewBuilder
  private var metadata: some View {
    Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 6) {
      GridRow {
        Text("Version")
          .foregroundStyle(.secondary)
        Text("\(info.version) (\(info.buildNumber))")
          .textSelection(.enabled)
      }

      if !info.buildIdentifier.isEmpty {
        GridRow {
          Text("Build")
            .foregroundStyle(.secondary)
          Text(info.buildIdentifier)
            .textSelection(.enabled)
        }
      }

      if !info.gitSHA.isEmpty {
        GridRow {
          Text("Git")
            .foregroundStyle(.secondary)
          VStack(alignment: .leading, spacing: 2) {
            Text(info.gitSHA)
              .font(.system(.callout, design: .monospaced))
              .textSelection(.enabled)
            if !info.gitTag.isEmpty {
              Text(info.gitTag)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
            }
          }
        }
      }

      if !info.author.isEmpty {
        GridRow {
          Text("Author")
            .foregroundStyle(.secondary)
          Text(info.author)
            .textSelection(.enabled)
        }
      }
    }
  }

  private var dataAccess: some View {
    VStack(alignment: .leading, spacing: 6) {
      Text("Data Access")
        .font(.headline)
      Text(info.dataAccessNote)
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
    }
  }

  private var acknowledgements: some View {
    VStack(alignment: .leading, spacing: 6) {
      Text("Acknowledgements")
        .font(.headline)
      VStack(alignment: .leading, spacing: 4) {
        ForEach(acknowledgementItems) { acknowledgement in
          HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text("\u{2022}")
              .foregroundStyle(.secondary)
            if let url = acknowledgement.url {
              Link(acknowledgement.name, destination: url)
            } else {
              Text(acknowledgement.name)
                .foregroundStyle(.secondary)
            }
          }
        }
      }
    }
  }
}
