import AVFoundation
import Foundation
import OSLog

/// Exports downloaded HLS audio using only the package's local fragments.
enum MediaPackageAudio {
  private static let logger = Logger(subsystem: "PodcastTransfer", category: "PackageAudio")

  enum ExportError: LocalizedError {
    case invalidPackage(String)
    case noAudio

    var errorDescription: String? {
      switch self {
      case .invalidPackage(let detail):
        return "Cannot extract downloaded audio: \(detail)"
      case .noAudio:
        return "The download does not contain a complete, unprotected audio stream."
      }
    }
  }

  static func export(from package: URL, to destination: URL) async throws {
    let workspace = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: true)
    defer {
      do {
        try FileManager.default.removeItem(at: workspace)
      } catch {
        logger.error("Could not remove temporary audio files: \(error.localizedDescription)")
      }
    }

    let staged = try PodcastLibraryAccess.withAccess {
      try stage(package: package, in: workspace)
    }
    let (mainAsset, mainTrack) = try await audioTrack(in: staged.streams)
    let duration = try await mainAsset.load(.duration)
    guard duration.isNumeric, duration > .zero else {
      throw ExportError.invalidPackage("invalid audio duration.")
    }
    let composition = AVMutableComposition()
    guard
      let track = composition.addMutableTrack(
        withMediaType: .audio,
        preferredTrackID: kCMPersistentTrackID_Invalid
      )
    else {
      throw ExportError.noAudio
    }

    var cursor = CMTime.zero
    for insertion in staged.interstitials {
      let position = CMTime(seconds: insertion.offset, preferredTimescale: 48_000)
      guard position >= cursor, position <= duration else {
        throw ExportError.invalidPackage("unsupported interstitial timeline.")
      }
      try track.insertTimeRange(
        CMTimeRange(start: cursor, end: position),
        of: mainTrack,
        at: composition.duration
      )
      for streams in insertion.streams {
        let (asset, audio) = try await audioTrack(in: streams)
        let adDuration = try await asset.load(.duration)
        guard adDuration.isNumeric, adDuration > .zero else {
          throw ExportError.invalidPackage("invalid interstitial audio duration.")
        }
        try track.insertTimeRange(
          CMTimeRange(start: .zero, duration: adDuration),
          of: audio,
          at: composition.duration
        )
      }
      cursor = position
    }
    try track.insertTimeRange(
      CMTimeRange(start: cursor, end: duration),
      of: mainTrack,
      at: composition.duration
    )

    guard
      let exporter = AVAssetExportSession(
        asset: composition,
        presetName: AVAssetExportPresetPassthrough
      )
    else {
      throw ExportError.noAudio
    }
    let output = workspace.appendingPathComponent("audio.m4a")
    // Audio-only MPEG-4 supports the edit lists needed to retain interstitials
    // losslessly; the narrower .m4a export type rejects these compositions.
    if #available(macOS 15, iOS 18, tvOS 18, watchOS 11, *) {
      try await exporter.export(to: output, as: .mp4)
    } else {
      exporter.outputURL = output
      exporter.outputFileType = .mp4
      await exporter.export()
      guard exporter.status == .completed else {
        throw exporter.error ?? ExportError.noAudio
      }
    }
    try Task.checkCancellation()
    let pending = destination.deletingLastPathComponent()
      .appendingPathComponent(".\(UUID().uuidString).m4a")
    defer {
      if FileManager.default.fileExists(atPath: pending.path) {
        do {
          try FileManager.default.removeItem(at: pending)
        } catch {
          logger.error("Could not remove pending audio transfer: \(error.localizedDescription)")
        }
      }
    }
    try FileManager.default.copyItem(at: output, to: pending)
    try Task.checkCancellation()
    try FileManager.default.moveItem(at: pending, to: destination)
  }

  private struct StagedPackage {
    var streams: [URL]
    var interstitials: [Insertion]
  }

  private struct Insertion {
    var offset: Double
    var streams: [[URL]]
  }

  private struct AssetList: Decodable {
    var assets: [Asset]

    enum CodingKeys: String, CodingKey {
      case assets = "ASSETS"
    }

    struct Asset: Decodable {
      var uri: String

      enum CodingKeys: String, CodingKey {
        case uri = "URI"
      }
    }
  }

  private static func stage(package: URL, in workspace: URL) throws -> StagedPackage {
    let boot = try document(at: package.appendingPathComponent("boot.xml"))
    let streams = try stageStreams(package: package, boot: boot, in: workspace)
    let playlistPaths = try boot.nodes(
      forXPath:
        "//*[local-name()='DataItem'][*[local-name()='Role']='Master']/*[local-name()='DataPath']"
    )
    guard let playlistPath = playlistPaths.first?.stringValue else {
      throw ExportError.invalidPackage("missing master playlist.")
    }
    let dataDirectory = try boot.nodes(forXPath: "//*[local-name()='DataItems']/@Directory")
    guard let directory = dataDirectory.first?.stringValue else {
      throw ExportError.invalidPackage("missing playlist directory.")
    }
    let dataURL = try localURL(directory, in: package)
    let playlist = try String(contentsOf: localURL(playlistPath, in: dataURL), encoding: .utf8)

    // Interstitial declarations may live on either the master or a media playlist.
    let mediaPlaylists = try FileManager.default.contentsOfDirectory(
      at: package,
      includingPropertiesForKeys: [.isDirectoryKey]
    ).filter { try $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory == true }
    var playlists = [playlist]
    for streamDirectory in mediaPlaylists where streamDirectory.pathExtension != "movpkg" {
      for url in try FileManager.default.contentsOfDirectory(
        at: streamDirectory,
        includingPropertiesForKeys: nil
      ) where url.pathExtension == "m3u8" {
        playlists.append(try String(contentsOf: url, encoding: .utf8))
      }
    }

    var insertions: [String: Insertion] = [:]
    for playlist in playlists {
      let lines = playlist.components(separatedBy: .newlines)
      let declarations = try lines.filter { $0.hasPrefix("#EXT-X-DATERANGE:") }
        .map { try attributes(String($0.dropFirst("#EXT-X-DATERANGE:".count))) }
        .filter { $0["CLASS"] == "com.apple.hls.interstitial" }
      guard !declarations.isEmpty else { continue }
      guard let dateLine = lines.first(where: { $0.hasPrefix("#EXT-X-PROGRAM-DATE-TIME:") }),
        let origin = date(String(dateLine.dropFirst("#EXT-X-PROGRAM-DATE-TIME:".count)))
      else {
        throw ExportError.invalidPackage("missing interstitial timeline origin.")
      }
      for attributes in declarations {
        guard let id = attributes["ID"] else {
          throw ExportError.invalidPackage("missing interstitial identifier.")
        }
        guard insertions[id] == nil else { continue }
        guard let start = attributes["START-DATE"].flatMap(date),
          attributes["X-RESUME-OFFSET"].flatMap(Double.init) == 0
        else {
          throw ExportError.invalidPackage("unsupported interstitial timing.")
        }
        var remoteAssets: [String]
        if let uri = attributes["X-ASSET-URI"] {
          remoteAssets = [uri]
        } else if let listURL = attributes["X-ASSET-LIST"] {
          let items = try boot.nodes(
            forXPath: "//*[local-name()='DataItem'][*[local-name()='Category']='AssetList']"
          )
          guard
            let item = try items.first(where: {
              try text("kDataItemNetworkURL", in: $0) == listURL
            }), let path = try text("DataPath", in: item)
          else {
            throw ExportError.invalidPackage("an interstitial asset list is not downloaded.")
          }
          remoteAssets = try JSONDecoder().decode(
            AssetList.self,
            from: Data(contentsOf: localURL(path, in: dataURL))
          ).assets.map(\.uri)
        } else {
          throw ExportError.invalidPackage("missing interstitial assets.")
        }
        guard !remoteAssets.isEmpty else {
          throw ExportError.invalidPackage("empty interstitial asset list.")
        }
        var adStreams: [[URL]] = []
        let assets = try boot.nodes(forXPath: "//*[local-name()='InterstitialAsset']")
        for uri in remoteAssets {
          guard let asset = try assets.first(where: { try text("NetworkURL", in: $0) == uri }),
            let path = try text("PathToLocalCopy", in: asset)
          else {
            throw ExportError.invalidPackage("interstitial audio is not downloaded.")
          }
          let adsDirectory = try boot.nodes(
            forXPath: "//*[local-name()='InterstitialAssets']/@Directory"
          )
          guard let adsPath = adsDirectory.first?.stringValue else {
            throw ExportError.invalidPackage("missing interstitial directory.")
          }
          let adPackage = try localURL(path, in: localURL(adsPath, in: package))
          adStreams.append(
            try stageStreams(
              package: adPackage,
              boot: document(at: adPackage.appendingPathComponent("boot.xml")),
              in: workspace
            )
          )
        }
        insertions[id] = Insertion(offset: start.timeIntervalSince(origin), streams: adStreams)
      }
    }
    return StagedPackage(
      streams: streams,
      interstitials: insertions.values.sorted { $0.offset < $1.offset }
    )
  }

  private static func stageStreams(
    package: URL,
    boot: XMLDocument,
    in workspace: URL
  ) throws -> [URL] {
    let streams = try boot.nodes(
      forXPath: "//*[local-name()='Stream'][*[local-name()='Complete']='YES']/@ID"
    )
    var outputs: [URL] = []
    for stream in streams {
      try Task.checkCancellation()
      guard let id = stream.stringValue else { continue }
      let directory = try localURL(id, in: package)
      let info = try document(at: directory.appendingPathComponent("StreamInfoBoot.xml"))
      guard try text("Complete", in: info.rootElement()) == "YES" else { continue }
      let initial = try info.nodes(forXPath: "//*[local-name()='ISEG']")
      let segments = try info.nodes(forXPath: "//*[local-name()='SEG']")
      guard initial.count == 1, !segments.isEmpty else {
        throw ExportError.invalidPackage("unsupported or missing audio initialization segments.")
      }
      let ordered = try segments.map { node -> (Int, XMLNode) in
        guard let value = (node as? XMLElement)?.attribute(forName: "SeqNum")?.stringValue,
          let sequence = Int(value)
        else { throw ExportError.invalidPackage("missing segment sequence.") }
        return (sequence, node)
      }.sorted { $0.0 < $1.0 }
      guard ordered.enumerated().allSatisfy({ $0.element.0 == $0.offset })
      else {
        throw ExportError.invalidPackage("missing or duplicate downloaded fragments.")
      }
      let output = workspace.appendingPathComponent("\(UUID().uuidString).mp4")
      try Data().write(to: output)
      let handle = try FileHandle(forWritingTo: output)
      do {
        for node in initial + ordered.map(\.1) {
          try Task.checkCancellation()
          guard let element = node as? XMLElement,
            let path = element.attribute(forName: "PATH")?.stringValue,
            let length = element.attribute(forName: "Len")?.stringValue.flatMap(Int.init),
            length > 0
          else { throw ExportError.invalidPackage("invalid fragment metadata.") }
          let data = try Data(contentsOf: localURL(path, in: directory))
          guard data.count == length else {
            throw ExportError.invalidPackage("a downloaded fragment is incomplete.")
          }
          try handle.write(contentsOf: data)
        }
        try handle.close()
      } catch {
        try? handle.close()
        throw error
      }
      outputs.append(output)
    }
    guard !outputs.isEmpty else { throw ExportError.noAudio }
    return outputs
  }

  private static func audioTrack(in streams: [URL]) async throws -> (AVURLAsset, AVAssetTrack) {
    for url in streams {
      let asset = AVURLAsset(url: url)
      guard try await !asset.load(.hasProtectedContent) else { continue }
      if let track = try await asset.loadTracks(withMediaType: .audio).first {
        return (asset, track)
      }
    }
    throw ExportError.noAudio
  }

  private static func document(at url: URL) throws -> XMLDocument {
    try XMLDocument(data: Data(contentsOf: url), options: .nodeLoadExternalEntitiesNever)
  }

  private static func text(_ name: String, in node: XMLNode?) throws -> String? {
    try node?.nodes(forXPath: "./*[local-name()='\(name)']").first?.stringValue
  }

  private static func localURL(_ path: String, in directory: URL) throws -> URL {
    let root = directory.resolvingSymlinksInPath().standardizedFileURL
    let url = root.appendingPathComponent(path).resolvingSymlinksInPath().standardizedFileURL
    guard !path.isEmpty, !path.hasPrefix("/"), url.path.hasPrefix(root.path + "/") else {
      throw ExportError.invalidPackage("invalid local fragment path.")
    }
    return url
  }

  private static func date(_ string: String) -> Date? {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    if let date = formatter.date(from: string) { return date }
    formatter.formatOptions = [.withInternetDateTime]
    return formatter.date(from: string)
  }

  private static func attributes(_ string: String) throws -> [String: String] {
    var quoted = false
    var current = ""
    var parts: [String] = []
    for character in string {
      if character == "\"" { quoted.toggle() }
      if character == ",", !quoted {
        parts.append(current)
        current = ""
      } else {
        current.append(character)
      }
    }
    guard !quoted else { throw ExportError.invalidPackage("invalid playlist attributes.") }
    parts.append(current)
    var result: [String: String] = [:]
    for part in parts {
      let pair = part.split(separator: "=", maxSplits: 1)
      guard pair.count == 2 else {
        throw ExportError.invalidPackage("invalid playlist attribute.")
      }
      result[String(pair[0])] = String(pair[1]).trimmingCharacters(
        in: CharacterSet(charactersIn: "\"")
      )
    }
    return result
  }
}
