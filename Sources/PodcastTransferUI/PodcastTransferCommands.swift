import PodcastTransferFeature
import SwiftUI

public struct PodcastTransferCommands: Commands {
  @EnvironmentObject private var sceneModel: PodcastTransferSceneModel
  @Environment(\.openURL) private var openURL
  @SceneStorage("podcastTransfer.sourcePresentation")
  private var sourcePresentationRaw = SourcePresentation.grouped.rawValue
  @SceneStorage("podcastTransfer.isDestinationInspectorPresented")
  private var isDestinationInspectorPresented = true

  public init() {}

  public var body: some Commands {
    CommandGroup(after: .newItem) {
      RefreshButton(
        action: {
          Task {
            await sceneModel.viewModel.loadEpisodes()
            await sceneModel.viewModel.loadDestinationEpisodes()
          }
        },
        isEnabled: true
      )
      OpenPodcastsButton(
        action: {
          Task { await PodcastsAppLauncher.open(openURL: openURL) }
        },
        isEnabled: true
      )
    }

    CommandGroup(after: .textEditing) {
      Menu("Selection") {
        SelectionMenuContent(
          selectAll: { sceneModel.viewModel.selectAll() },
          clearSelection: { sceneModel.viewModel.clearSelection() },
          isEnabled: true
        )
      }
    }

    CommandGroup(after: .toolbar) {
      ViewModePickerContent(
        sourcePresentation: sourcePresentationBinding,
        isEnabled: true
      )

      DestinationInspectorButton(
        isPresented: $isDestinationInspectorPresented,
        isEnabled: true
      )
    }
  }
}

extension PodcastTransferCommands {
  private var sourcePresentation: SourcePresentation {
    get { SourcePresentation(rawValue: sourcePresentationRaw) ?? .grouped }
    set { sourcePresentationRaw = newValue.rawValue }
  }

  private var sourcePresentationBinding: Binding<SourcePresentation> {
    Binding(
      get: { sourcePresentation },
      set: { sourcePresentationRaw = $0.rawValue }
    )
  }
}

struct ViewModePickerContent: View {
  @Binding var sourcePresentation: SourcePresentation
  var isEnabled = true

  var body: some View {
    Picker("View", selection: $sourcePresentation) {
      Label("Grouped", systemImage: "list.bullet.rectangle")
        .tag(SourcePresentation.grouped)
      Label("Table", systemImage: "tablecells")
        .tag(SourcePresentation.table)
    }
    .pickerStyle(.inline)
    .disabled(!isEnabled)
  }
}

struct SelectionMenuContent: View {
  let selectAll: () -> Void
  let clearSelection: () -> Void
  var isEnabled = true

  var body: some View {
    Group {
      Button("Select All") {
        selectAll()
      }
      .keyboardShortcut("a", modifiers: [.command])

      Button("Clear Selection") {
        clearSelection()
      }
      .keyboardShortcut(.escape, modifiers: [])
    }
    .disabled(!isEnabled)
  }
}

struct RefreshButton: View {
  let action: () -> Void
  var isEnabled = true

  var body: some View {
    Button {
      action()
    } label: {
      Label("Refresh", systemImage: "arrow.clockwise")
    }
    .keyboardShortcut("r", modifiers: [.command])
    .disabled(!isEnabled)
  }
}

struct OpenPodcastsButton: View {
  let action: () -> Void
  var isEnabled = true

  var body: some View {
    Button {
      action()
    } label: {
      Label("Open Podcasts app", systemImage: "waveform")
    }
    .disabled(!isEnabled)
  }
}

struct DestinationInspectorButton: View {
  @Binding var isPresented: Bool
  var isEnabled = true

  var body: some View {
    Button {
      isPresented.toggle()
    } label: {
      Label(
        isPresented ? "Hide Destination" : "Show Destination",
        systemImage: "sidebar.right"
      )
    }
    .disabled(!isEnabled)
  }
}
