import Dependencies
import Foundation
import PodcastTransferCore
import PodcastTransferFeature
import PodcastTransferTelemetry
import SwiftUI

#if os(macOS)
  import AppKit
#endif

public struct PodcastTransferView: View {
  @Environment(\.openURL) private var openURL
  @Environment(\.openWindow) private var openWindow
  @Dependency(\.telemetryClient) private var telemetryClient
  @State private var viewModel: PodcastTransferViewModel
  @State private var isImporterPresented = false
  @State private var importerError: String?
  @StateObject private var artworkLoader = ArtworkLoader()
  @SceneStorage("podcastTransfer.sourcePresentation")
  private var sourcePresentationRaw = SourcePresentation.grouped.rawValue
  @State private var sortOrder: [KeyPathComparator<PodcastEpisode>] = [
    .init(\PodcastEpisode.createdAtSortable, order: .reverse)
  ]
  @State private var tableSelectedEpisodeIDs: Set<String> = []
  @State private var lastTableSelectedEpisodeIDs: Set<String> = []
  @SceneStorage("podcastTransfer.isDestinationInspectorPresented")
  private var isDestinationInspectorPresented = true
  @State private var showTransferSuccess = false
  @State private var successPulse = false
  @State private var ejectError: String?
  @State private var isEjecting = false

  public init(viewModel: PodcastTransferViewModel = PodcastTransferViewModel()) {
    _viewModel = State(initialValue: viewModel)
  }

  public var body: some View {
    NavigationStack {
      ZStack(alignment: .bottomTrailing) {
        VStack(alignment: .leading, spacing: 12) {
          HStack {
            Text("Source")
              .font(.headline)
            Spacer()
          }

          StatusSummaryView(state: viewModel.state, isLoading: viewModel.isLoading)

          SourceEpisodesView(
            presentation: sourcePresentation,
            episodes: viewModel.episodes,
            selectedEpisodeIDs: viewModel.selectedEpisodeIDs,
            tableSelectedEpisodeIDs: $tableSelectedEpisodeIDs,
            isLoading: viewModel.isLoading,
            sortOrder: $sortOrder,
            artworkLoader: artworkLoader,
            onToggle: { viewModel.toggleSelection(for: $0) },
            onTableSelectionChanged: { newSelection in
              let oldSelection = lastTableSelectedEpisodeIDs
              let added = newSelection.subtracting(oldSelection)
              let removed = oldSelection.subtracting(newSelection)

              for episodeID in added {
                if let episode = viewModel.episodes.first(where: { $0.id == episodeID }) {
                  viewModel.toggleSelection(for: episode)
                }
              }
              for episodeID in removed {
                if let episode = viewModel.episodes.first(where: { $0.id == episodeID }) {
                  viewModel.toggleSelection(for: episode)
                }
              }

              lastTableSelectedEpisodeIDs = newSelection
            },
            onRefresh: {
              await viewModel.loadEpisodes()
              await viewModel.loadDestinationEpisodes()
            }
          )
        }
        .padding()

        VStack(alignment: .trailing, spacing: 10) {
          if showTransferSuccess {
            Image(systemName: "checkmark.circle.fill")
              .font(.system(size: 28))
              .foregroundStyle(.green)
              .scaleEffect(successPulse ? 1.0 : 0.6)
              .opacity(successPulse ? 1.0 : 0.0)
              .animation(.spring(response: 0.35, dampingFraction: 0.6), value: successPulse)
              .transition(.scale.combined(with: .opacity))
          }

          Button {
            Task { await viewModel.transferAll() }
          } label: {
            Label(transferToolbarTitle, systemImage: "externaldrive.fill")
              .font(.headline)
              .padding(.horizontal, 16)
              .padding(.vertical, 10)
              .background(Color.accentColor)
              .foregroundStyle(.white)
              .clipShape(Capsule())
              .shadow(color: .black.opacity(0.2), radius: 8, x: 0, y: 4)
          }
          .buttonStyle(.plain)
          .disabled(!isTransferEnabled)
          .opacity(isTransferEnabled ? 1.0 : 0.6)
        }
        .padding(.trailing, 22)
        .padding(.bottom, 22)
      }
      .navigationTitle("Podcast Transfer")
      .toolbar {
        ToolbarItemGroup(placement: .navigation) {
          Menu {
            ViewModePickerContent(sourcePresentation: sourcePresentationBinding)
          } label: {
            Label("View", systemImage: "line.3.horizontal.decrease.circle")
          }
          .help("Change list view")

          Menu {
            SelectionMenuContent(
              selectAll: {
                telemetryClient.track(.selectionAction(.selectAll))
                viewModel.selectAll()
              },
              clearSelection: {
                telemetryClient.track(.selectionAction(.clearSelection))
                viewModel.clearSelection()
              }
            )
          } label: {
            Label("Selection", systemImage: "checkmark.circle")
          }
          .help("Select or clear episodes")
        }

        ToolbarItem(placement: .primaryAction) {
          RefreshButton {
            telemetryClient.track(.toolbarAction(.refresh))
            Task {
              await viewModel.loadEpisodes()
              await viewModel.loadDestinationEpisodes()
            }
          }
          .help("Refresh episodes")
        }

        ToolbarItem(placement: .primaryAction) {
          OpenPodcastsButton {
            telemetryClient.track(.toolbarAction(.openPodcasts))
            Task { await PodcastsAppLauncher.open(openURL: openURL) }
          }
          .help("Open Apple Podcasts")
        }

        ToolbarItem(placement: .primaryAction) {
          Button {
            telemetryClient.track(.toolbarAction(.appInfo))
            openWindow(id: "about")
          } label: {
            Label("App Info", systemImage: "info.circle")
              .labelStyle(.iconOnly)
          }
          .help("Show app information")
        }

        if let ejectableVolumeURL {
          ToolbarItem(placement: .primaryAction) {
            Button {
              telemetryClient.track(.toolbarAction(.eject))
              Task { await ejectDestinationVolume(at: ejectableVolumeURL) }
            } label: {
              Label("Eject", systemImage: "eject")
            }
            .disabled(isEjecting || isTransferring(from: viewModel.state))
            .help("Eject destination")
          }
        }

        ToolbarItem(placement: .automatic) {
          DestinationInspectorButton(isPresented: $isDestinationInspectorPresented)
            .help(
              isDestinationInspectorPresented
                ? "Hide destination inspector"
                : "Show destination inspector"
            )
        }
      }
    }
    .inspector(isPresented: $isDestinationInspectorPresented) {
      DestinationInspectorView(
        destination: viewModel.persistedDestination,
        episodes: viewModel.destinationEpisodes,
        artworkLoader: artworkLoader,
        onChooseFolder: { isImporterPresented = true },
        onDelete: { episode in
          Task { await viewModel.deleteDestinationEpisode(episode) }
        }
      )
      // The inspector host can clip content near the rounded corners.
      // Provide extra inset and a wider minimum width for readability.
      .padding(.top, 6)
      .padding(.leading, 6)
      .inspectorColumnWidth(min: 420, ideal: 560, max: 760)
    }
    .task {
      await viewModel.loadEpisodes()
      await viewModel.loadDestinationEpisodes()
    }
    .onChange(of: viewModel.selectedEpisodeIDs) { _, newValue in
      tableSelectedEpisodeIDs = newValue
      lastTableSelectedEpisodeIDs = newValue
    }
    .onChange(of: sourcePresentation) { _, newValue in
      telemetryClient.track(
        .viewModeChanged(newValue == .table ? .table : .grouped)
      )
      if newValue == .table {
        tableSelectedEpisodeIDs = viewModel.selectedEpisodeIDs
        lastTableSelectedEpisodeIDs = viewModel.selectedEpisodeIDs
      }
    }
    .onChange(of: isDestinationInspectorPresented) { _, newValue in
      telemetryClient.track(.destinationInspectorToggled(isPresented: newValue))
    }
    .onChange(of: viewModel.state) { _, newValue in
      if case .finished = newValue {
        playCompletionSound()
        showTransferSuccess = true
        successPulse = false
        withAnimation(.spring(response: 0.35, dampingFraction: 0.6)) {
          successPulse = true
        }
        Task {
          try? await Task.sleep(for: .seconds(1.5))
          withAnimation(.easeOut(duration: 0.3)) {
            showTransferSuccess = false
            successPulse = false
          }
        }
      }
    }
    .fileImporter(
      isPresented: $isImporterPresented,
      allowedContentTypes: [.folder],
      allowsMultipleSelection: false
    ) { result in
      switch result {
      case .success(let urls):
        if let destination = urls.first {
          viewModel.setDestination(destination)
        }
      case .failure(let error):
        importerError = error.localizedDescription
      }
    }
    .alert(
      "Unable to select folder",
      isPresented: Binding(
        get: { importerError != nil },
        set: { presenting in
          if presenting == false {
            importerError = nil
          }
        }
      )
    ) {
      Button("OK", role: .cancel) { importerError = nil }
    } message: {
      if let importerError {
        Text(importerError)
      }
    }
    .alert(
      "Unable to eject destination",
      isPresented: Binding(
        get: { ejectError != nil },
        set: { presenting in
          if presenting == false {
            ejectError = nil
          }
        }
      )
    ) {
      Button("OK", role: .cancel) { ejectError = nil }
    } message: {
      if let ejectError {
        Text(ejectError)
      }
    }
    .focusedValue(\.sourcePresentation, sourcePresentationBinding)
    .focusedValue(\.isDestinationInspectorPresented, $isDestinationInspectorPresented)
  }

  private func isTransferring(from state: TransferState) -> Bool {
    if case .inProgress = state { return true }
    return false
  }

  private func playCompletionSound() {
    #if os(macOS)
      NSSound(named: "Glass")?.play()
    #endif
  }

  private var isTransferEnabled: Bool {
    viewModel.persistedDestination != nil
      && viewModel.isLoading == false
      && isTransferring(from: viewModel.state) == false
      && viewModel.selectedEpisodeIDs.isEmpty == false
  }

  private var transferToolbarTitle: String {
    let count = viewModel.selectedEpisodeIDs.count
    guard count > 0 else { return "Transfer" }
    return "Transfer \(count)"
  }

  private var ejectableVolumeURL: URL? {
    guard let destination = viewModel.persistedDestination else { return nil }
    let keys: Set<URLResourceKey> = [
      .volumeURLKey,
      .volumeIsEjectableKey,
      .volumeIsRemovableKey,
      .volumeIsInternalKey,
    ]
    let values = try? destination.resourceValues(forKeys: keys)

    let nsDestination = destination as NSURL
    var volumeURLObject: AnyObject?
    try? nsDestination.getResourceValue(&volumeURLObject, forKey: URLResourceKey.volumeURLKey)
    guard let volumeURL = volumeURLObject as? URL else { return nil }

    let isEjectable = values?.volumeIsEjectable == true
    let isRemovable = values?.volumeIsRemovable == true
    let isExternal = values?.volumeIsInternal == false
    guard isEjectable || isRemovable || isExternal else { return nil }
    return volumeURL
  }

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

  @MainActor
  private func ejectDestinationVolume(at volumeURL: URL) async {
    isEjecting = true
    defer { isEjecting = false }

    #if os(macOS)
      let error = await unmountAndEject(volumeURL)
      if let error {
        ejectError = error.localizedDescription
      }
    #else
      ejectError = "Eject is only available on macOS."
    #endif
  }

  @MainActor
  private func unmountAndEject(_ volumeURL: URL) async -> Error? {
    #if os(macOS)
      do {
        try NSWorkspace.shared.unmountAndEjectDevice(at: volumeURL)
        return nil
      } catch {
        return error
      }
    #else
      return nil
    #endif
  }
}
