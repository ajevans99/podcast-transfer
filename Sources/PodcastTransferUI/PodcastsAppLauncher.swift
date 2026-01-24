import SwiftUI

#if os(macOS)
  import AppKit
#endif

public enum PodcastsAppLauncher {
  @MainActor
  public static func open(openURL: OpenURLAction) async {
    #if os(macOS)
      if let appURL = NSWorkspace.shared.urlForApplication(
        withBundleIdentifier: "com.apple.podcasts"
      ) {
        let configuration = NSWorkspace.OpenConfiguration()
        _ = try? await NSWorkspace.shared.openApplication(at: appURL, configuration: configuration)
        return
      }

      if let url = URL(string: "podcast://") {
        NSWorkspace.shared.open(url)
      }
    #else
      if let url = URL(string: "podcast://") {
        await openURL(url)
      }
    #endif
  }
}
