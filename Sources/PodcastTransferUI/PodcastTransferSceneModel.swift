import PodcastTransferFeature
import SwiftUI

@MainActor
public final class PodcastTransferSceneModel: ObservableObject {
  public let viewModel: PodcastTransferViewModel

  public init(viewModel: PodcastTransferViewModel = PodcastTransferViewModel()) {
    self.viewModel = viewModel
  }
}
