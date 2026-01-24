import Dependencies
import TelemetryDeck

public struct TelemetryConfiguration: Sendable, Equatable {
  public var appID: String

  public init(appID: String) {
    self.appID = appID
  }
}

public enum TelemetryEvent: Sendable, Equatable {
  case transferStarted(selectedCount: Int)
  case transferCompleted(copied: Int, skipped: Int, failed: Int)
  case transferFailed(reason: TransferFailureReason, selectedCount: Int)
  case toolbarAction(ToolbarAction)
  case selectionAction(SelectionAction)
  case viewModeChanged(ViewMode)
  case destinationInspectorToggled(isPresented: Bool)
}

public enum TransferFailureReason: String, Sendable, Equatable {
  case noDestination
  case noSelection
  case transferError
}

public enum ToolbarAction: String, Sendable, Equatable {
  case refresh
  case openPodcasts
  case appInfo
  case eject
}

public enum SelectionAction: String, Sendable, Equatable {
  case selectAll
  case clearSelection
}

public enum ViewMode: String, Sendable, Equatable {
  case grouped
  case table
}

public struct TelemetryClient: Sendable {
  public var configure: @Sendable (TelemetryConfiguration) -> Void
  public var track: @Sendable (TelemetryEvent) -> Void

  public init(
    configure: @escaping @Sendable (TelemetryConfiguration) -> Void,
    track: @escaping @Sendable (TelemetryEvent) -> Void
  ) {
    self.configure = configure
    self.track = track
  }
}

extension TelemetryClient {
  public static func live() -> Self {
    Self(
      configure: { configuration in
        let config = TelemetryDeck.Config(appID: configuration.appID)
        config.defaultSignalPrefix = "PodcastTransfer."
        TelemetryDeck.initialize(config: config)
      },
      track: { event in
        TelemetryDeck.signal(
          event.signalName,
          parameters: event.parameters
        )
      }
    )
  }

  public static let noop = Self(
    configure: { _ in },
    track: { _ in }
  )
}

extension TelemetryClient: DependencyKey {
  public static let liveValue: TelemetryClient = .live()
  public static let previewValue: TelemetryClient = .noop
  public static let testValue: TelemetryClient = .noop
}

extension DependencyValues {
  public var telemetryClient: TelemetryClient {
    get { self[TelemetryClient.self] }
    set { self[TelemetryClient.self] = newValue }
  }
}

extension TelemetryEvent {
  public var signalName: String {
    switch self {
    case .transferStarted:
      return "transfer.started"
    case .transferCompleted:
      return "transfer.completed"
    case .transferFailed:
      return "transfer.failed"
    case .toolbarAction(let action):
      return "toolbar.action.\(action.rawValue)"
    case .selectionAction(let action):
      return "selection.\(action.rawValue)"
    case .viewModeChanged:
      return "view.mode.changed"
    case .destinationInspectorToggled:
      return "destination.inspector.toggled"
    }
  }

  public var parameters: [String: String] {
    switch self {
    case .transferStarted(let selectedCount):
      return ["selectedCount": String(selectedCount)]
    case .transferCompleted(let copied, let skipped, let failed):
      return [
        "copied": String(copied),
        "skipped": String(skipped),
        "failed": String(failed),
      ]
    case .transferFailed(let reason, let selectedCount):
      return [
        "reason": reason.rawValue,
        "selectedCount": String(selectedCount),
      ]
    case .toolbarAction:
      return [:]
    case .selectionAction:
      return [:]
    case .viewModeChanged(let mode):
      return ["mode": mode.rawValue]
    case .destinationInspectorToggled(let isPresented):
      return ["isPresented": String(isPresented)]
    }
  }
}
