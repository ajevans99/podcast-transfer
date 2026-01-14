import PodcastTransferCore

@main
enum PlaygroundMain {
  static func main() async throws {
    let episodes = try await PodcastLibraryClient.preview.loadEpisodes()
    print("Preview episodes available: \(episodes.count)")
  }
}
