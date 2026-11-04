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
    let unreadable = try makePackage(in: directory.appendingPathComponent("unreadable"))
    let inaccessible = unreadable.appendingPathComponent("inaccessible")
    try FileManager.default.createDirectory(at: inaccessible, withIntermediateDirectories: true)
    try FileManager.default.setAttributes([.posixPermissions: 0], ofItemAtPath: inaccessible.path)
    defer {
      try? FileManager.default.setAttributes(
        [.posixPermissions: 0o700],
        ofItemAtPath: inaccessible.path
      )
    }
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
      for (index, url) in [package, audio, invalidPackage, nonMedia, missing, unreadable]
        .enumerated()
      {
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
    #expect(Set(episodes.map(\.fileURL)) == [package, audio, unreadable])
    let packagedEpisode = try #require(episodes.first { $0.fileURL == package })
    #expect(packagedEpisode.podcastTitle == "Test Show")
    #expect(packagedEpisode.duration == 2)
    #expect(packagedEpisode.fileSize > 1_600)
    let unreadableEpisode = try #require(episodes.first { $0.fileURL == unreadable })
    #expect(unreadableEpisode.fileSize == 0)
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

  @Test
  func playlistOriginAccountsForSegmentsBeforeProgramDate() throws {
    let lines = [
      "#EXTM3U",
      "#EXTINF:6.25,",
      "first.m4s",
      "#EXTINF:3.75,",
      "second.m4s",
      "#EXTINF:4.5,",
      "#EXT-X-PROGRAM-DATE-TIME:2026-01-01T00:00:10Z",
      "third.m4s",
    ]
    let expected = try #require(ISO8601DateFormatter().date(from: "2026-01-01T00:00:00Z"))
    #expect(try MediaPackageAudio.playlistOrigin(lines) == expected)
    #expect(throws: MediaPackageAudio.ExportError.self) {
      try MediaPackageAudio.playlistOrigin([
        "#EXTINF:not-a-duration,", "first.m4s", "#EXT-X-PROGRAM-DATE-TIME:2026-01-01T00:00:10Z",
      ])
    }
  }

  @Test(arguments: [(0.0, 2.0), (1.0, 3.0), (10.0, 4.0)])
  func exportHonorsInterstitialPlayoutLimit(limit: Double, expectedDuration: Double) async throws {
    let directory = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let package = try makePackage(in: directory, withInterstitial: true, playoutLimit: limit)
    let output = directory.appendingPathComponent("limited.m4a")
    try await MediaPackageAudio.export(from: package, to: output)
    let duration = try await AVURLAsset(url: output).load(.duration).seconds
    #expect(abs(duration - expectedDuration) < 0.1)
  }

  @Test
  func playoutLimitSpansMultipleInterstitialAssets() async throws {
    let directory = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let package = try makePackage(
      in: directory,
      withInterstitial: true,
      withAssetList: true,
      playoutLimit: 3
    )
    let interstitials = package.appendingPathComponent("InterstitialAssets")
    try FileManager.default.copyItem(
      at: interstitials.appendingPathComponent("ad.movpkg"),
      to: interstitials.appendingPathComponent("second.movpkg")
    )
    let boot = package.appendingPathComponent("boot.xml")
    let xml = try String(contentsOf: boot, encoding: .utf8)
    try xml.replacingOccurrences(
      of: "</InterstitialAssets>",
      with: """
        <InterstitialAsset><NetworkURL>https://example.invalid/second</NetworkURL>
        <PathToLocalCopy>second.movpkg</PathToLocalCopy></InterstitialAsset></InterstitialAssets>
        """
    ).write(to: boot, atomically: true, encoding: .utf8)
    try """
    {"ASSETS":[{"URI":"https://example.invalid/ad"},{"URI":"https://example.invalid/second"}]}
    """.write(
      to: package.appendingPathComponent("Data/ads.json"),
      atomically: true,
      encoding: .utf8
    )

    let output = directory.appendingPathComponent("limited.m4a")
    try await MediaPackageAudio.export(from: package, to: output)
    let duration = try await AVURLAsset(url: output).load(.duration).seconds
    #expect(abs(duration - 5) < 0.1)
  }

  @Test
  func exportStagesAudioWithoutCopyingVideoRenditions() async throws {
    let directory = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let package = try makePackage(in: directory, withInterstitial: true)
    try addVideoRendition(to: package)
    try addVideoRendition(to: package.appendingPathComponent("InterstitialAssets/ad.movpkg"))
    let output = directory.appendingPathComponent("audio-only.m4a")
    try await MediaPackageAudio.export(from: package, to: output)
    let asset = AVURLAsset(url: output)
    #expect(try await asset.loadTracks(withMediaType: .audio).count == 1)
    #expect(try await asset.loadTracks(withMediaType: .video).isEmpty)
    #expect(abs((try await asset.load(.duration).seconds) - 4) < 0.1)
  }

  @Test(arguments: [
    "incomplete", "missing-fragment", "truncated-fragment", "duplicate-sequence",
    "escaping-path", "missing-interstitial", "invalid-playout-limit",
  ])
  func invalidPackageReportsFailureWithoutPartialOutput(problem: String) async throws {
    let directory = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let package = try makePackage(
      in: directory,
      withInterstitial: problem == "missing-interstitial" || problem == "invalid-playout-limit"
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
    case "invalid-playout-limit":
      let playlist = package.appendingPathComponent("audio/media.m3u8")
      let text = try String(contentsOf: playlist, encoding: .utf8)
      try text.replacingOccurrences(
        of: "X-RESUME-OFFSET=0",
        with: "X-RESUME-OFFSET=0,X-PLAYOUT-LIMIT=nan"
      ).write(to: playlist, atomically: true, encoding: .utf8)
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
  withAssetList: Bool = false,
  playoutLimit: Double? = nil
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
    let limitAttribute = playoutLimit.map { ",X-PLAYOUT-LIMIT=\($0)" } ?? ""
    if withAssetList {
      try """
      {"ASSETS":[{"URI":"https://example.invalid/ad","DURATION":2}]}
      """.write(to: data.appendingPathComponent("ads.json"), atomically: true, encoding: .utf8)
    }
    try """
    #EXTM3U
    #EXT-X-PROGRAM-DATE-TIME:2026-01-01T00:00:00Z
    #EXT-X-DATERANGE:ID="ad",CLASS="com.apple.hls.interstitial",START-DATE="2026-01-01T00:00:01Z",X-RESUME-OFFSET=0,\(attribute)\(limitAttribute)
    """.write(to: stream.appendingPathComponent("media.m3u8"), atomically: true, encoding: .utf8)
  }
  return package
}

private func addVideoRendition(to package: URL) throws {
  let bytes = try #require(Data(base64Encoded: blackVideo, options: .ignoreUnknownCharacters))
  try #require(bytes.count == 1_720)
  let video = package.appendingPathComponent("video")
  try FileManager.default.createDirectory(at: video, withIntermediateDirectories: true)
  try bytes.subdata(in: 0..<776).write(to: video.appendingPathComponent("init.initfrag"))
  try bytes.subdata(in: 776..<1509).write(to: video.appendingPathComponent("0.frag"))
  try """
  <StreamInfo><Complete>YES</Complete><MediaInitializationSegments>
  <ISEG PATH="init.initfrag" Len="776"/>
  </MediaInitializationSegments><MediaSegments>
  <SEG PATH="0.frag" Len="733" SeqNum="0"/>
  <SEG PATH="missing-video.frag" Len="125" SeqNum="1"/>
  </MediaSegments></StreamInfo>
  """.write(
    to: video.appendingPathComponent("StreamInfoBoot.xml"),
    atomically: true,
    encoding: .utf8
  )
  let boot = package.appendingPathComponent("boot.xml")
  let xml = try String(contentsOf: boot, encoding: .utf8)
  try xml.replacingOccurrences(
    of: "<Streams>",
    with: "<Streams><Stream ID=\"video\"><Complete>YES</Complete></Stream>"
  ).write(to: boot, atomically: true, encoding: .utf8)
}

// Two seconds of generated black video with no audio.
private let blackVideo = """
  AAAAJGZ0eXBpc29tAAACAGlzb21pc282aXNvMmF2YzFtcDQxAAAC5G1vb3YAAABsbXZoZAAAAAAAAAAAAAAAAAAAA+gAAAAAAAEA
  AAEAAAAAAAAAAAAAAAABAAAAAAAAAAAAAAAAAAAAAQAAAAAAAAAAAAAAAAAAQAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
  AAIAAAHndHJhawAAAFx0a2hkAAAAAwAAAAAAAAAAAAAAAQAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAABAAAAAAAAAAAAAAAAAAAA
  AQAAAAAAAAAAAAAAAAAAQAAAAAAQAAAAEAAAAAABg21kaWEAAAAgbWRoZAAAAAAAAAAAAAAAAAAAQAAAAAAAVcQAAAAAAC1oZGxy
  AAAAAAAAAAB2aWRlAAAAAAAAAAAAAAAAVmlkZW9IYW5kbGVyAAAAAS5taW5mAAAAFHZtaGQAAAABAAAAAAAAAAAAAAAkZGluZgAA
  ABxkcmVmAAAAAAAAAAEAAAAMdXJsIAAAAAEAAADuc3RibAAAAKJzdHNkAAAAAAAAAAEAAACSYXZjMQAAAAAAAAABAAAAAAAAAAAA
  AAAAAAAAAAAQABAASAAAAEgAAAAAAAAAARRMYXZjNjMuMS4xMDIgbGlieDI2NAAAAAAAAAAAAAAAABj//wAAACxhdmNDAULACv/h
  ABVnQsAK2nsBEAAAAwAQAAADACDxImoBAARozg/IAAAAEHBhc3AAAAABAAAAAQAAABBzdHRzAAAAAAAAAAAAAAAQc3RzYwAAAAAA
  AAAAAAAAFHN0c3oAAAAAAAAAAAAAAAAAAAAQc3RjbwAAAAAAAAAAAAAAKG12ZXgAAAAgdHJleAAAAAAAAAABAAAAAQAAAAAAAAAA
  AAAAAAAAAGF1ZHRhAAAAWW1ldGEAAAAAAAAAIWhkbHIAAAAAAAAAAG1kaXJhcHBsAAAAAAAAAAAAAAAALGlsc3QAAAAkqXRvbwAA
  ABxkYXRhAAAAAQAAAABMYXZmNjMuMS4xMDIAAABwbW9vZgAAABBtZmhkAAAAAAAAAAEAAABYdHJhZgAAACR0ZmhkAAAAOQAAAAEA
  AAAAAAADCAAAQAAAAAJlAQEAAAAAABR0ZmR0AQAAAAAAAAAAAAAAAAAAGHRydW4AAAAFAAAAAQAAAHgCAAAAAAACbW1kYXQAAAJT
  BgX//0/cRem95tlIt5Ys2CDZI+7veDI2NCAtIGNvcmUgMTY1IHIzMjIyIGIzNTYwNWEgLSBILjI2NC9NUEVHLTQgQVZDIGNvZGVj
  IC0gQ29weWxlZnQgMjAwMy0yMDI1IC0gaHR0cDovL3d3dy52aWRlb2xhbi5vcmcveDI2NC5odG1sIC0gb3B0aW9uczogY2FiYWM9
  MCByZWY9MSBkZWJsb2NrPTA6MDowIGFuYWx5c2U9MDowIG1lPWRpYSBzdWJtZT0wIHBzeT0xIHBzeV9yZD0xLjAwOjAuMDAgbWl4
  ZWRfcmVmPTAgbWVfcmFuZ2U9MTYgY2hyb21hX21lPTEgdHJlbGxpcz0wIDh4OGRjdD0wIGNxbT0wIGRlYWR6b25lPTIxLDExIGZh
  c3RfcHNraXA9MSBjaHJvbWFfcXBfb2Zmc2V0PTAgdGhyZWFkcz0xIGxvb2thaGVhZF90aHJlYWRzPTEgc2xpY2VkX3RocmVhZHM9
  MCBucj0wIGRlY2ltYXRlPTEgaW50ZXJsYWNlZD0wIGJsdXJheV9jb21wYXQ9MCBjb25zdHJhaW5lZF9pbnRyYT0wIGJmcmFtZXM9
  MCB3ZWlnaHRwPTAga2V5aW50PTI1MCBrZXlpbnRfbWluPTEgc2NlbmVjdXQ9MCBpbnRyYV9yZWZyZXNoPTAgcmM9Y3JmIG1idHJl
  ZT0wIGNyZj0yMy4wIHFjb21wPTAuNjAgcXBtaW49MCBxcG1heD02OSBxcHN0ZXA9NCBpcF9yYXRpbz0xLjQwIGFxPTAAgAAAAApl
  iIQ6JigACQLgAAAAbG1vb2YAAAAQbWZoZAAAAAAAAAACAAAAVHRyYWYAAAAkdGZoZAAAADkAAAABAAAAAAAABeUAAEAAAAAACQEB
  AAAAAAAUdGZkdAEAAAAAAAAAAABAAAAAABR0cnVuAAAAAQAAAAEAAAB0AAAAEW1kYXQAAAAFQZogFKUAAABWbWZyYQAAAD50ZnJh
  AQAAAAAAAAEAAAAAAAAAAgAAAAAAAAAAAAAAAAAAAwgBAQEAAAAAAABAAAAAAAAAAAXlAQEBAAAAEG1mcm8AAAAAAAAAVg==
  """

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
