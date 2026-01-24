import PodcastTransferFeature
import SwiftUI

public struct PodcastTransferCommands: Commands {
  @EnvironmentObject private var sceneModel: PodcastTransferSceneModel
  @Environment(\.openWindow) private var openWindow
  @Environment(\.openURL) private var openURL
  @FocusedValue(\.sourcePresentation)
  private var sourcePresentationBinding: Binding<SourcePresentation>?
  @FocusedValue(\.isDestinationInspectorPresented)
  private var isDestinationInspectorPresentedBinding: Binding<Bool>?

  public init() {}

  public var body: some Commands {
    CommandGroup(replacing: .appInfo) {
      Button("About Podcast Transfer") {
        openWindow(id: "about")
      }
    }

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
      if let sourcePresentationBinding {
        ViewModePickerContent(
          sourcePresentation: sourcePresentationBinding,
          isEnabled: true
        )
      } else {
        ViewModePickerContent(
          sourcePresentation: .constant(.grouped),
          isEnabled: false
        )
      }

      if let isDestinationInspectorPresentedBinding {
        DestinationInspectorButton(
          isPresented: isDestinationInspectorPresentedBinding,
          isEnabled: true
        )
      } else {
        DestinationInspectorButton(
          isPresented: .constant(true),
          isEnabled: false
        )
      }
    }
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
      Label {
        Text("Open Podcasts app")
      } icon: {
        Image("podcast_icon")
          .renderingMode(.template)
      }
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
