import Dependencies
import PodcastTransferFeature
import PodcastTransferUI
import Sharing
import SwiftUI

@main
struct PodcastTransferApp: App {
  @StateObject private var sceneModel = PodcastTransferSceneModel()

  init() {
    prepareDependencies {
      $0.podcastLibrary = .live()
      $0.transferClient = .live()
    }
  }

  var body: some Scene {
    WindowGroup {
      PodcastTransferView(viewModel: sceneModel.viewModel)
        .environmentObject(sceneModel)
    }
    .defaultSize(width: 1100, height: 760)
    .commands {
      PodcastTransferCommands()
    }
  }
}
