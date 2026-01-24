import Foundation
import PodcastTransferCore
import Testing

@Suite
struct DestinationClientTests {
  @Test
  func destinationClientListsAudioFilesSorted() async throws {
    let destination = try makeTempDirectory()
    defer { try? FileManager.default.removeItem(at: destination) }

    let showA = destination.appendingPathComponent("Show A")
    let showB = destination.appendingPathComponent("Show B")
    try FileManager.default.createDirectory(at: showA, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: showB, withIntermediateDirectories: true)

    try writeTempFile(at: showA.appendingPathComponent("Alpha.m4a"))
    try writeTempFile(at: showA.appendingPathComponent("Delta.mp3"))
    try writeTempFile(at: showB.appendingPathComponent("Bravo.aac"))
    try writeTempFile(at: showB.appendingPathComponent("Ignore.txt"))

    let client = DestinationClient.live(fileManager: .default)
    let episodes = try await client.listEpisodes(destination)

    let titles = episodes.map { "\($0.podcastTitle)|\($0.title)" }
    #expect(titles == ["Show A|Alpha", "Show A|Delta", "Show B|Bravo"])
  }

  @Test
  func destinationClientDeletesEpisode() async throws {
    let destination = try makeTempDirectory()
    defer { try? FileManager.default.removeItem(at: destination) }

    let fileURL = destination.appendingPathComponent("DeleteMe.m4a")
    try writeTempFile(at: fileURL)

    let client = DestinationClient.live(fileManager: .default)
    try await client.deleteEpisode(fileURL)

    #expect(FileManager.default.fileExists(atPath: fileURL.path) == false)
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
