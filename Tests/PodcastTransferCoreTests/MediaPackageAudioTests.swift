import AVFoundation
import Foundation
import GRDB
import Testing

@testable import PodcastTransferCore

@Suite
struct MediaPackageAudioTests {
  @Test
  func libraryIncludesPackagesAlongsideAudioFiles() async throws {
    let directory = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let package = try makePackage(in: directory)
    let audio = directory.appendingPathComponent("ordinary.mp3")
    try Data("audio".utf8).write(to: audio)
    let invalidPackage = directory.appendingPathComponent("file.movpkg")
    try Data("not a package".utf8).write(to: invalidPackage)
    let nonMedia = directory.appendingPathComponent("folder")
    try FileManager.default.createDirectory(at: nonMedia, withIntermediateDirectories: true)
    let missing = directory.appendingPathComponent("missing.movpkg")
    let databaseURL = directory.appendingPathComponent("library.sqlite")
    let database = try DatabaseQueue(path: databaseURL.path)
    try await database.write { db in
      try db.execute(
        sql: """
          CREATE TABLE ZMTPODCAST (Z_PK INTEGER PRIMARY KEY, ZTITLE TEXT);
          CREATE TABLE ZMTEPISODE (
            Z_PK INTEGER PRIMARY KEY, ZPODCAST INTEGER, ZTITLE TEXT,
            ZCURRENTMEDIAENCLOSURE INTEGER
          );
          CREATE TABLE ZMTMEDIAENCLOSURE (Z_PK INTEGER PRIMARY KEY, ZLOCALURL TEXT, ZDURATION REAL);
          INSERT INTO ZMTPODCAST VALUES (1, 'Test Show');
          """
      )
      for (index, url) in [package, audio, invalidPackage, nonMedia, missing].enumerated() {
        try db.execute(
          sql: "INSERT INTO ZMTEPISODE VALUES (?, 1, ?, ?)",
          arguments: [index, "Episode \(index)", index]
        )
        try db.execute(
          sql: "INSERT INTO ZMTMEDIAENCLOSURE VALUES (?, ?, 2)",
          arguments: [index, url.absoluteString]
        )
      }
    }

    let episodes = try await PodcastLibraryClient.live(databaseURL: databaseURL).loadEpisodes()
    #expect(Set(episodes.map(\.fileURL)) == [package, audio])
    let packagedEpisode = try #require(episodes.first { $0.fileURL == package })
    #expect(packagedEpisode.podcastTitle == "Test Show")
    #expect(packagedEpisode.duration == 2)
    #expect(packagedEpisode.fileSize > 1_600)
  }

  @Test
  func transferExportsAudioOnlyAndSkipsExistingM4A() async throws {
    let directory = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let package = try makePackage(in: directory)
    let destination = directory.appendingPathComponent("destination")
    let episode = episode(at: package)
    let client = TransferClient.live()
    let outcome = try await client.transfer([episode], destination)
    #expect(outcome.copied == 1)
    #expect(outcome.failed.isEmpty)
    let output = destination.appendingPathComponent("Test Show/Test Episode.m4a")
    let asset = AVURLAsset(url: output)
    #expect(try await asset.loadTracks(withMediaType: .audio).count == 1)
    #expect(try await asset.loadTracks(withMediaType: .video).isEmpty)
    let duration = try await asset.load(.duration).seconds
    #expect(abs(duration - 2) < 0.1)
    #expect(FileManager.default.fileExists(atPath: package.appendingPathComponent("boot.xml").path))

    let repeated = try await client.transfer([episode], destination)
    #expect(repeated.skipped == 1)
    #expect(repeated.copied == 0)
    #expect(repeated.failed.isEmpty)
    let listed = try await DestinationClient.live().listEpisodes(destination)
    #expect(
      listed.map { $0.fileURL.resolvingSymlinksInPath() } == [output.resolvingSymlinksInPath()]
    )
  }

  @Test(arguments: [false, true])
  func exportRetainsLocallyCachedInterstitialAudio(usingAssetList: Bool) async throws {
    let directory = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let package = try makePackage(
      in: directory,
      withInterstitial: true,
      withAssetList: usingAssetList
    )
    let output = directory.appendingPathComponent("output.m4a")
    try await MediaPackageAudio.export(from: package, to: output)
    let asset = AVURLAsset(url: output)
    let duration = try await asset.load(.duration).seconds
    #expect(abs(duration - 4) < 0.05)
    #expect(try await asset.loadTracks(withMediaType: .video).isEmpty)
  }

  @Test(arguments: [
    "incomplete", "missing-fragment", "truncated-fragment", "duplicate-sequence",
    "escaping-path", "missing-interstitial",
  ])
  func invalidPackageReportsFailureWithoutPartialOutput(problem: String) async throws {
    let directory = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let package = try makePackage(
      in: directory,
      withInterstitial: problem == "missing-interstitial"
    )
    let info = package.appendingPathComponent("audio/StreamInfoBoot.xml")
    switch problem {
    case "incomplete":
      let boot = package.appendingPathComponent("boot.xml")
      let xml = try String(contentsOf: boot, encoding: .utf8)
      try xml.replacingOccurrences(of: ">YES<", with: ">NO<").write(
        to: boot,
        atomically: true,
        encoding: .utf8
      )
    case "missing-fragment":
      try FileManager.default.removeItem(at: package.appendingPathComponent("audio/1.frag"))
    case "truncated-fragment":
      try Data([0]).write(to: package.appendingPathComponent("audio/1.frag"))
    case "duplicate-sequence":
      let xml = try String(contentsOf: info, encoding: .utf8)
      try xml.replacingOccurrences(of: "SeqNum=\"1\"", with: "SeqNum=\"0\"").write(
        to: info,
        atomically: true,
        encoding: .utf8
      )
    case "escaping-path":
      let xml = try String(contentsOf: info, encoding: .utf8)
      try xml.replacingOccurrences(of: "PATH=\"0.frag\"", with: "PATH=\"../../outside.frag\"")
        .write(
          to: info,
          atomically: true,
          encoding: .utf8
        )
    case "missing-interstitial":
      try FileManager.default.removeItem(
        at: package.appendingPathComponent("InterstitialAssets/ad.movpkg")
      )
    default:
      Issue.record("Unknown package corruption")
    }

    let destination = directory.appendingPathComponent("destination")
    let result = try await TransferClient.live().transfer([episode(at: package)], destination)
    #expect(result.copied == 0)
    #expect(result.failed.count == 1)
    #expect(result.failed.first?.reason.isEmpty == false)
    #expect(
      !FileManager.default.fileExists(
        atPath: destination.appendingPathComponent("Test Show/Test Episode.m4a").path
      )
    )
  }
}

private func episode(at package: URL) -> PodcastEpisode {
  PodcastEpisode(
    title: "Test Episode",
    podcastTitle: "Test Show",
    fileURL: package,
    fileSize: 1_768,
    createdAt: nil
  )
}

private func temporaryDirectory() throws -> URL {
  let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
  return url
}

private func makePackage(
  in directory: URL,
  withInterstitial: Bool = false,
  withAssetList: Bool = false
) throws -> URL {
  let package = directory.appendingPathComponent("download.movpkg")
  let stream = package.appendingPathComponent("audio")
  let data = package.appendingPathComponent("Data")
  try FileManager.default.createDirectory(at: stream, withIntermediateDirectories: true)
  try FileManager.default.createDirectory(at: data, withIntermediateDirectories: true)
  let bytes = try #require(Data(base64Encoded: silentAAC, options: .ignoreUnknownCharacters))
  try #require(bytes.count == 1_768)
  let ranges = [732..<1239, 1239..<1543, 1543..<1663]
  try bytes.subdata(in: 0..<732).write(to: stream.appendingPathComponent("init.initfrag"))
  var fragments = ""
  for (index, range) in ranges.enumerated() {
    try bytes.subdata(in: range).write(to: stream.appendingPathComponent("\(index).frag"))
    fragments += "<SEG PATH=\"\(index).frag\" Len=\"\(range.count)\" SeqNum=\"\(index)\"/>"
  }
  try """
  <StreamInfo><Complete>YES</Complete><MediaInitializationSegments>
  <ISEG PATH="init.initfrag" Len="732"/>
  </MediaInitializationSegments><MediaSegments>\(fragments)</MediaSegments></StreamInfo>
  """.write(
    to: stream.appendingPathComponent("StreamInfoBoot.xml"),
    atomically: true,
    encoding: .utf8
  )

  let adMetadata =
    withInterstitial
    ? """
    <InterstitialAssets Directory="InterstitialAssets"><InterstitialAsset>
    <NetworkURL>https://example.invalid/ad</NetworkURL>
    <PathToLocalCopy>ad.movpkg</PathToLocalCopy>
    </InterstitialAsset></InterstitialAssets>
    """ : ""
  let listMetadata =
    withAssetList
    ? """
    <DataItem><Category>AssetList</Category>
    <kDataItemNetworkURL>https://example.invalid/list</kDataItemNetworkURL>
    <DataPath>ads.json</DataPath></DataItem>
    """ : ""
  try """
  <HLSMoviePackage><Streams><Stream ID="audio"><Complete>YES</Complete></Stream></Streams>
  <DataItems Directory="Data"><DataItem><Role>Master</Role><DataPath>master.m3u8</DataPath></DataItem>
  \(listMetadata)</DataItems>\(adMetadata)</HLSMoviePackage>
  """.write(to: package.appendingPathComponent("boot.xml"), atomically: true, encoding: .utf8)
  try "#EXTM3U\n".write(
    to: data.appendingPathComponent("master.m3u8"),
    atomically: true,
    encoding: .utf8
  )
  if withInterstitial {
    let ads = package.appendingPathComponent("InterstitialAssets")
    let generated = try makePackage(in: ads)
    try FileManager.default.moveItem(at: generated, to: ads.appendingPathComponent("ad.movpkg"))
    let attribute =
      withAssetList
      ? "X-ASSET-LIST=\"https://example.invalid/list\""
      : "X-ASSET-URI=\"https://example.invalid/ad\""
    if withAssetList {
      try """
      {"ASSETS":[{"URI":"https://example.invalid/ad","DURATION":2}]}
      """.write(to: data.appendingPathComponent("ads.json"), atomically: true, encoding: .utf8)
    }
    try """
    #EXTM3U
    #EXT-X-PROGRAM-DATE-TIME:2026-01-01T00:00:00Z
    #EXT-X-DATERANGE:ID="ad",CLASS="com.apple.hls.interstitial",START-DATE="2026-01-01T00:00:01Z",X-RESUME-OFFSET=0,\(attribute)
    """.write(to: stream.appendingPathComponent("media.m3u8"), atomically: true, encoding: .utf8)
  }
  return package
}

// Two seconds of generated silent AAC in fragmented MP4, not podcast content.
private let silentAAC = """
  AAAAIGZ0eXBpc29tAAACAGlzb21pc282aXNvMm1wNDEAAAK8bW9vdgAAAGxtdmhkAAAAAAAAAAAAAAAAAAC7gAAAAAAAAQAAAQAA
  AAAAAAAAAAAAAAEAAAAAAAAAAAAAAAAAAAABAAAAAAAAAAAAAAAAAABAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAgAA
  Ab90cmFrAAAAXHRraGQAAAADAAAAAAAAAAAAAAABAAAAAAAAAAAAAAAAAAAAAAAAAAEBAAAAAAEAAAAAAAAAAAAAAAAAAAABAAAA
  AAAAAAAAAAAAAABAAAAAAAAAAAAAAAAAAAFbbWRpYQAAACBtZGhkAAAAAAAAAAAAAAAAAAC7gAAAAABVxAAAAAAALWhkbHIAAAAA
  AAAAAHNvdW4AAAAAAAAAAAAAAABTb3VuZEhhbmRsZXIAAAABBm1pbmYAAAAQc21oZAAAAAAAAAAAAAAAJGRpbmYAAAAcZHJlZgAA
  AAAAAAABAAAADHVybCAAAAABAAAAynN0YmwAAAB+c3RzZAAAAAAAAAABAAAAbm1wNGEAAAAAAAAAAQAAAAAAAAAAAAEAEAAAAAC7
  gAAAAAAANmVzZHMAAAAAA4CAgCUAAQAEgICAF0AVAAAAAAB9AAAAfQAFgICABRGIVuUABoCAgAECAAAAFGJ0cnQAAAAAAAB9AAAA
  fQAAAAAQc3R0cwAAAAAAAAAAAAAAEHN0c2MAAAAAAAAAAAAAABRzdHN6AAAAAAAAAAAAAAAAAAAAEHN0Y28AAAAAAAAAAAAAACht
  dmV4AAAAIHRyZXgAAAAAAAAAAQAAAAEAAAAAAAAAAAAAAAAAAABhdWR0YQAAAFltZXRhAAAAAAAAACFoZGxyAAAAAAAAAABtZGly
  YXBwbAAAAAAAAAAAAAAAACxpbHN0AAAAJKl0b28AAAAcZGF0YQAAAAEAAAAATGF2ZjYzLjEuMTAyAAABKG1vb2YAAAAQbWZoZAAA
  AAAAAAABAAABEHRyYWYAAAAkdGZoZAAAADkAAAABAAAAAAAAAtwAAAQAAAAAEwIAAAAAAAAUdGZkdAEAAAAAAAAAAAAAAAAAANB0
  cnVuAAACAQAAAC8AAAEwAAAAEwAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAE
  AAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAA
  BAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAAAEAAAABAAAAAQAAADTbWRhdNwATGF2YzYzLjEuMTAy
  AAIwQA4BGCAHARggBwEYIAcBGCAHARggBwEYIAcBGCAHARggBwEYIAcBGCAHARggBwEYIAcBGCAHARggBwEYIAcBGCAHARggBwEY
  IAcBGCAHARggBwEYIAcBGCAHARggBwEYIAcBGCAHARggBwEYIAcBGCAHARggBwEYIAcBGCAHARggBwEYIAcBGCAHARggBwEYIAcB
  GCAHARggBwEYIAcBGCAHARggBwEYIAcBGCAHARggBwEYIAcBGCAHAAAAbG1vb2YAAAAQbWZoZAAAAAAAAAACAAAAVHRyYWYAAAAk
  dGZoZAAAADkAAAABAAAAAAAABNcAAAQAAAAABAIAAAAAAAAUdGZkdAEAAAAAAAAAAAC8AAAAABR0cnVuAAAAAQAAAC8AAAB0AAAA
  xG1kYXQBGCAHARggBwEYIAcBGCAHARggBwEYIAcBGCAHARggBwEYIAcBGCAHARggBwEYIAcBGCAHARggBwEYIAcBGCAHARggBwEY
  IAcBGCAHARggBwEYIAcBGCAHARggBwEYIAcBGCAHARggBwEYIAcBGCAHARggBwEYIAcBGCAHARggBwEYIAcBGCAHARggBwEYIAcB
  GCAHARggBwEYIAcBGCAHARggBwEYIAcBGCAHARggBwEYIAcBGCAHARggBwAAAGxtb29mAAAAEG1maGQAAAAAAAAAAwAAAFR0cmFm
  AAAAJHRmaGQAAAA5AAAAAQAAAAAAAAYHAAADAAAAAAQCAAAAAAAAFHRmZHQBAAAAAAAAAAABeAAAAAAUdHJ1bgAAAAEAAAABAAAA
  dAAAAAxtZGF0ARggBwAAAGltZnJhAAAAUXRmcmEBAAAAAAAAAQAAAAAAAAADAAAAAAAAAAAAAAAAAAAC3AEBAQAAAAAAALwAAAAA
  AAAABNcBAQEAAAAAAAF4AAAAAAAAAAYHAQEBAAAAEG1mcm8AAAAAAAAAaQ==
  """
