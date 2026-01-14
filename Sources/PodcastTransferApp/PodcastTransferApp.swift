import Dependencies
import PodcastTransferFeature
import PodcastTransferUI
import Sharing
import SwiftUI

@main
struct PodcastTransferApp: App {
  init() {
    prepareDependencies {
      $0.podcastLibrary = .live()
      $0.transferClient = .live()
    }
  }

  var body: some Scene {
    WindowGroup {
      PodcastTransferView()
    }
  }
}
