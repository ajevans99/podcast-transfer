import Foundation
import OSLog

#if canImport(QuickLookThumbnailing)
  import QuickLookThumbnailing
#endif
#if os(macOS)
  import AppKit
#endif

@MainActor
final class ArtworkLoader: ObservableObject {
  private let logger = Logger(subsystem: "PodcastTransfer", category: "ArtworkLoader")
  private var cache: [URL: PlatformImage] = [:]

  func thumbnail(for url: URL, fallbackArtworkURL: URL?) async -> PlatformImage? {
    if let cached = cache[url] {
      logger.debug("Using cached artwork for \(url.lastPathComponent, privacy: .public)")
      return cached
    }

    #if os(macOS)
      if let artworkURL = fallbackArtworkURL, artworkURL.isFileURL,
        let image = NSImage(contentsOf: artworkURL)
      {
        cache[url] = image
        logger.debug(
          "Loaded file artwork for \(url.lastPathComponent, privacy: .public) from \(artworkURL.lastPathComponent, privacy: .public)"
        )
        return image
      }

      if let artworkURL = fallbackArtworkURL,
        artworkURL.scheme == "http" || artworkURL.scheme == "https"
      {
        do {
          let (data, response) = try await URLSession.shared.data(from: artworkURL)
          if let http = response as? HTTPURLResponse {
            logger.debug(
              "Fetched remote artwork HTTP \(http.statusCode, privacy: .public) for \(url.lastPathComponent, privacy: .public)"
            )
          }
          if let image = NSImage(data: data) {
            cache[url] = image
            logger.debug("Decoded remote artwork for \(url.lastPathComponent, privacy: .public)")
            return image
          } else {
            logger.debug(
              "Failed to decode remote artwork for \(url.lastPathComponent, privacy: .public)"
            )
          }
        } catch {
          logger.debug(
            "Remote artwork fetch failed for \(url.lastPathComponent, privacy: .public): \(error.localizedDescription, privacy: .public)"
          )
        }
      }

      do {
        if let image = try await generateThumbnail(for: url) {
          cache[url] = image
          logger.debug(
            "Generated Quick Look thumbnail for \(url.lastPathComponent, privacy: .public)"
          )
          return image
        }
      } catch {
        logger.debug(
          "Thumbnail generation failed for \(url.lastPathComponent, privacy: .public): \(error.localizedDescription, privacy: .public)"
        )
      }

      logger.debug("No artwork available for \(url.lastPathComponent, privacy: .public)")
    #else
      logger.debug(
        "Artwork generation not implemented for this platform for \(url.lastPathComponent, privacy: .public)"
      )
    #endif
    return nil
  }

  #if os(macOS)
    private func generateThumbnail(for url: URL) async throws -> NSImage? {
      let request = QLThumbnailGenerator.Request(
        fileAt: url,
        size: CGSize(width: 200, height: 200),
        scale: NSScreen.main?.backingScaleFactor ?? 2,
        representationTypes: .icon
      )

      return try await withCheckedThrowingContinuation { continuation in
        QLThumbnailGenerator.shared.generateBestRepresentation(for: request) {
          representation,
          error in
          if let image = representation?.nsImage {
            continuation.resume(returning: image)
          } else if let error {
            continuation.resume(throwing: error)
          } else {
            continuation.resume(returning: nil)
          }
        }
      }
    }
  #endif
}
