import Foundation
import PodcastTransferCore
import Testing

@Suite
struct TransferClientTests {
  @Test
  func transferCopiesAndSanitizesFilename() async throws {
    let destination = try makeTempDirectory()
    defer { try? FileManager.default.removeItem(at: destination) }

    let sourceDir = try makeTempDirectory()
    defer { try? FileManager.default.removeItem(at: sourceDir) }

    let sourceURL = sourceDir.appendingPathComponent("source.m4a")
    try writeTempFile(at: sourceURL)

    let episode = PodcastEpisode(
      title: "Weird / Title:Name?*",
      podcastTitle: "My Show",
      author: nil,
      duration: nil,
      fileURL: sourceURL,
      fileSize: 12,
      createdAt: nil
    )

    let client = TransferClient.live(fileManager: .default)
    let outcome = try await client.transfer([episode], destination)

    #expect(outcome.copied == 1)
    #expect(outcome.skipped == 0)
    #expect(outcome.failed.isEmpty)

    let showDirectory = destination.appendingPathComponent("My Show")
    let contents = try FileManager.default.contentsOfDirectory(
      at: showDirectory,
      includingPropertiesForKeys: nil
    )
    #expect(contents.count == 1)

    let filename = contents[0].lastPathComponent
    #expect(filename.hasSuffix(".m4a"))

    let invalidCharacters = CharacterSet(charactersIn: "/\\:?*\"<>|")
    #expect(filename.rangeOfCharacter(from: invalidCharacters) == nil)
  }

  @Test
  func transferSkipsExistingFile() async throws {
    let destination = try makeTempDirectory()
    defer { try? FileManager.default.removeItem(at: destination) }

    let sourceDir = try makeTempDirectory()
    defer { try? FileManager.default.removeItem(at: sourceDir) }

    let sourceURL = sourceDir.appendingPathComponent("simple.m4a")
    try writeTempFile(at: sourceURL)

    let showDirectory = destination.appendingPathComponent("Simple Show")
    try FileManager.default.createDirectory(at: showDirectory, withIntermediateDirectories: true)
    let existing = showDirectory.appendingPathComponent("Simple Episode.m4a")
    try writeTempFile(at: existing)

    let episode = PodcastEpisode(
      title: "Simple Episode",
      podcastTitle: "Simple Show",
      author: nil,
      duration: nil,
      fileURL: sourceURL,
      fileSize: 8,
      createdAt: nil
    )

    let client = TransferClient.live(fileManager: .default)
    let outcome = try await client.transfer([episode], destination)

    #expect(outcome.copied == 0)
    #expect(outcome.skipped == 1)
    #expect(outcome.failed.isEmpty)
  }

  @Test
  func transferFallsBackToFileNameWhenTitleEmpty() async throws {
    let destination = try makeTempDirectory()
    defer { try? FileManager.default.removeItem(at: destination) }

    let sourceDir = try makeTempDirectory()
    defer { try? FileManager.default.removeItem(at: sourceDir) }

    let sourceURL = sourceDir.appendingPathComponent("fallback.m4a")
    try writeTempFile(at: sourceURL)

    let episode = PodcastEpisode(
      title: "   ",
      podcastTitle: "Fallback Show",
      author: nil,
      duration: nil,
      fileURL: sourceURL,
      fileSize: 16,
      createdAt: nil
    )

    let client = TransferClient.live(fileManager: .default)
    let outcome = try await client.transfer([episode], destination)

    #expect(outcome.copied == 1)
    #expect(outcome.failed.isEmpty)

    let showDirectory = destination.appendingPathComponent("Fallback Show")
    let contents = try FileManager.default.contentsOfDirectory(
      at: showDirectory,
      includingPropertiesForKeys: nil
    )
    let filename = contents.first?.lastPathComponent
    #expect(filename == "fallback.m4a")
  }
}

private func makeTempDirectory() throws -> URL {
  let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
  return url
}

private func writeTempFile(at url: URL) throws {
  try Data("demo".utf8).write(to: url)
}
