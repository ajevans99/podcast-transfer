import Dependencies
import OSLog
import PodcastTransferFeature
import PodcastTransferTelemetry
import PodcastTransferUI
import Sharing
import SwiftUI

@main
struct PodcastTransferApp: App {
  @StateObject private var sceneModel = PodcastTransferSceneModel()

  private static let logger = Logger(subsystem: "PodcastTransfer", category: "Telemetry")

  init() {
    prepareDependencies {
      $0.podcastLibrary = .live()
      $0.transferClient = .live()
      $0.telemetryClient = .live()
    }

    let rawAppID =
      (Bundle.main.object(forInfoDictionaryKey: "PodcastTransferTelemetryAppID") as? String) ?? ""
    let appID = rawAppID.trimmingCharacters(in: .whitespacesAndNewlines)

    guard !appID.isEmpty else {
      Self.logger.warning(
        "Telemetry not configured: PodcastTransferTelemetryAppID is missing/empty"
      )
      return
    }

    guard UUID(uuidString: appID) != nil else {
      Self.logger.error(
        "Telemetry not configured: PodcastTransferTelemetryAppID is not a valid UUID"
      )
      return
    }

    TelemetryClient.liveValue.configure(.init(appID: appID))
    Self.logger.info("Telemetry configured")
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

    Window("About Podcast Transfer", id: "about") {
      AboutView()
    }
    .windowResizability(.contentSize)
  }
}
