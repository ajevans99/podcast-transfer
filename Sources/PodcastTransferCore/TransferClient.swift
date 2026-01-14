import Dependencies
import Foundation

public struct TransferClient: Sendable {
  public var transfer:
    @Sendable (_ episodes: [PodcastEpisode], _ destination: URL) async throws
      -> TransferOutcome

  public init(
    transfer:
      @escaping @Sendable (_ episodes: [PodcastEpisode], _ destination: URL) async throws
      -> TransferOutcome
  ) {
    self.transfer = transfer
  }
}

extension TransferClient {
  public static func live(fileManager: FileManager = .default) -> Self {
    let fileManager = UncheckedSendable(fileManager)

    return Self { episodes, destination in
      let fileManager = fileManager.wrappedValue
      var copied = 0
      var skipped = 0
      var failures: [TransferFailure] = []

      func sanitizeFilenameComponent(_ input: String) -> String {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return "" }

        // Conservative set of replacements for cross-platform safety.
        let invalidCharacters = CharacterSet(charactersIn: "/\\:?*\"<>|")
        let parts = trimmed.components(separatedBy: invalidCharacters)
        let joined = parts.joined(separator: "-")
        let squashed = joined.replacingOccurrences(
          of: "\\s+",
          with: " ",
          options: .regularExpression
        )
        return squashed.trimmingCharacters(in: .whitespacesAndNewlines)
      }

      func destinationFileName(for episode: PodcastEpisode) -> String {
        let ext = episode.fileURL.pathExtension
        let base = sanitizeFilenameComponent(episode.title)
        let fallbackBase = sanitizeFilenameComponent(
          episode.fileURL.deletingPathExtension().lastPathComponent
        )
        let finalBase = base.isEmpty ? fallbackBase : base
        if ext.isEmpty { return finalBase }
        return "\(finalBase).\(ext)"
      }

      try fileManager.createDirectory(
        at: destination,
        withIntermediateDirectories: true,
        attributes: nil
      )

      for episode in episodes {
        let showDirectory = destination.appendingPathComponent(episode.podcastTitle)
        try fileManager.createDirectory(
          at: showDirectory,
          withIntermediateDirectories: true,
          attributes: nil
        )
        let destinationURL = showDirectory.appendingPathComponent(destinationFileName(for: episode))

        if fileManager.fileExists(atPath: destinationURL.path) {
          skipped += 1
          continue
        }

        do {
          try fileManager.copyItem(at: episode.fileURL, to: destinationURL)
          copied += 1
        } catch {
          failures.append(
            TransferFailure(source: episode.fileURL, reason: error.localizedDescription)
          )
        }
      }

      return TransferOutcome(
        destination: destination,
        copied: copied,
        skipped: skipped,
        failed: failures
      )
    }
  }

  public static let preview: Self = .init { @Sendable episodes, destination in
    TransferOutcome(destination: destination, copied: episodes.count, skipped: 0, failed: [])
  }
}

extension TransferClient: DependencyKey {
  public static let liveValue: Self = .live()
  public static let previewValue: Self = .preview
  public static let testValue: Self = .init { @Sendable _, _ in
    unimplemented(
      "TransferClient.transfer",
      placeholder: .init(
        destination: .init(fileURLWithPath: "/tmp"),
        copied: 0,
        skipped: 0,
        failed: []
      )
    )
  }
}

extension DependencyValues {
  public var transferClient: TransferClient {
    get { self[TransferClient.self] }
    set { self[TransferClient.self] = newValue }
  }
}
