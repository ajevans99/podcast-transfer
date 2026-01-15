import Foundation
import OSLog
import PodcastTransferCore
import PodcastTransferFeature
import SwiftUI

#if canImport(QuickLookThumbnailing)
  import QuickLookThumbnailing
#endif
#if os(macOS)
  import AppKit
#endif

public struct PodcastTransferView: View {
  @State private var viewModel: PodcastTransferViewModel
  @State private var isImporterPresented = false
  @State private var importerError: String?
  @StateObject private var artworkLoader = ArtworkLoader()
  @State private var sourcePresentation: SourcePresentation = .grouped
  @State private var sortOrder: [KeyPathComparator<PodcastEpisode>] = [
    .init(\PodcastEpisode.createdAtSortable, order: .reverse)
  ]
  @State private var tableSelectedEpisodeIDs: Set<String> = []
  @State private var lastTableSelectedEpisodeIDs: Set<String> = []
  @State private var isDestinationInspectorPresented: Bool = true

  public init(viewModel: PodcastTransferViewModel = PodcastTransferViewModel()) {
    _viewModel = State(initialValue: viewModel)
  }

  public var body: some View {
    NavigationStack {
      VStack(alignment: .leading, spacing: 12) {
        HStack {
          Text("Source")
            .font(.headline)
          Spacer()
          Picker("View", selection: $sourcePresentation) {
            Text("Grouped").tag(SourcePresentation.grouped)
            Text("Table").tag(SourcePresentation.table)
          }
          .pickerStyle(.segmented)
          .frame(maxWidth: 260)
        }

        TransferControlsView(
          selectionCount: viewModel.selectedEpisodeIDs.count,
          canSelectAny: !viewModel.episodes.isEmpty,
          destinationLabel: viewModel.persistedDestination?.lastPathComponent,
          isLoading: viewModel.isLoading,
          isTransferring: isTransferring(from: viewModel.state),
          onTransfer: { Task { await viewModel.transferAll() } },
          onSelectAll: { viewModel.selectAll() },
          onClearSelection: { viewModel.clearSelection() },
          onRefresh: {
            Task {
              await viewModel.loadEpisodes()
              await viewModel.loadDestinationEpisodes()
            }
          },
          onShowDestination: { isDestinationInspectorPresented = true }
        )

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
          }
        )
      }
      .padding()
      .navigationTitle("Podcast Transfer")
      .toolbar {
        ToolbarItem(placement: .automatic) {
          Button {
            isDestinationInspectorPresented.toggle()
          } label: {
            Label(
              isDestinationInspectorPresented ? "Hide Destination" : "Show Destination",
              systemImage: "sidebar.right"
            )
          }
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
      if newValue == .table {
        tableSelectedEpisodeIDs = viewModel.selectedEpisodeIDs
        lastTableSelectedEpisodeIDs = viewModel.selectedEpisodeIDs
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
  }

  private func isTransferring(from state: TransferState) -> Bool {
    if case .inProgress = state { return true }
    return false
  }
}

private enum SourcePresentation: String, CaseIterable, Sendable {
  case grouped
  case table
}

private struct SourceEpisodesView: View {
  let presentation: SourcePresentation
  let episodes: [PodcastEpisode]
  let selectedEpisodeIDs: Set<String>
  @Binding var tableSelectedEpisodeIDs: Set<String>
  let isLoading: Bool
  @Binding var sortOrder: [KeyPathComparator<PodcastEpisode>]
  var artworkLoader: ArtworkLoader
  var onToggle: (PodcastEpisode) -> Void
  var onTableSelectionChanged: (Set<String>) -> Void

  var body: some View {
    switch presentation {
    case .grouped:
      EpisodesListView(
        episodes: episodes,
        selectedEpisodeIDs: selectedEpisodeIDs,
        isLoading: isLoading,
        artworkLoader: artworkLoader,
        onToggle: onToggle
      )

    case .table:
      EpisodesTableView(
        episodes: episodes,
        selectedEpisodeIDs: $tableSelectedEpisodeIDs,
        isLoading: isLoading,
        sortOrder: $sortOrder,
        artworkLoader: artworkLoader,
        onSelectionChanged: onTableSelectionChanged
      )
    }
  }
}

private struct EpisodesTableView: View {
  let episodes: [PodcastEpisode]
  @Binding var selectedEpisodeIDs: Set<String>
  let isLoading: Bool
  @Binding var sortOrder: [KeyPathComparator<PodcastEpisode>]
  var artworkLoader: ArtworkLoader
  var onSelectionChanged: (Set<String>) -> Void

  var body: some View {
    Table(sortedEpisodes, selection: $selectedEpisodeIDs, sortOrder: $sortOrder) {
      TableColumn("Title", value: \.title) { episode in
        EpisodeTableTitleCell(episode: episode, artworkLoader: artworkLoader)
          #if os(macOS)
            .contextMenu {
              Button("Show in Finder", systemImage: "folder") {
                NSWorkspace.shared.activateFileViewerSelecting([episode.fileURL])
              }
            }
          #endif
      }
      .width(min: 220)

      TableColumn("Podcast", value: \.podcastTitle) { episode in
        Text(episode.podcastTitle)
          .lineLimit(1)
      }
      .width(min: 160)

      TableColumn("Date", value: \.createdAtSortable) { episode in
        if let createdAt = episode.createdAt {
          Text(createdAt.formatted(date: .abbreviated, time: .shortened))
        } else {
          Text("–")
            .foregroundStyle(.secondary)
        }
      }
      .width(min: 140)

      TableColumn("Size", value: \.fileSize) { episode in
        Text(byteCountString(episode.fileSize))
      }
      .width(min: 90)

      TableColumn("Length", value: \.durationSortable) { episode in
        if let duration = episode.duration {
          Text(durationString(duration))
        } else {
          Text("–")
            .foregroundStyle(.secondary)
        }
      }
      .width(min: 90)
    }
    .onChange(of: selectedEpisodeIDs) { _, newValue in
      onSelectionChanged(newValue)
    }
    .overlay {
      if episodes.isEmpty && !isLoading {
        ContentUnavailableView(
          "No downloads",
          systemImage: "tray",
          description: Text("We could not find any downloaded Apple Podcasts in your library.")
        )
      }
    }
  }

  private var sortedEpisodes: [PodcastEpisode] {
    if sortOrder.isEmpty {
      return episodes.sorted { (lhs, rhs) in
        (lhs.createdAt ?? .distantPast) > (rhs.createdAt ?? .distantPast)
      }
    }
    return episodes.sorted(using: sortOrder)
  }

  private func byteCountString(_ size: Int64) -> String {
    let formatter = ByteCountFormatter()
    formatter.allowedUnits = [.useMB, .useGB]
    formatter.countStyle = .file
    return formatter.string(fromByteCount: size)
  }

  private func durationString(_ duration: TimeInterval) -> String {
    let totalSeconds = Int(duration)
    let minutes = totalSeconds / 60
    let seconds = totalSeconds % 60
    return String(format: "%dm %02ds", minutes, seconds)
  }
}

private struct EpisodeTableTitleCell: View {
  let episode: PodcastEpisode
  var artworkLoader: ArtworkLoader

  @State private var image: PlatformImage?

  var body: some View {
    HStack(spacing: 8) {
      ArtworkThumbnail(image: image)
        .frame(width: 24, height: 24)
        .cornerRadius(4)
      Text(episode.title)
        .lineLimit(1)
    }
    .task(id: episode.id) {
      if image == nil {
        image = await artworkLoader.thumbnail(
          for: episode.fileURL,
          fallbackArtworkURL: episode.artworkURL
        )
      }
    }
  }
}

extension PodcastEpisode {
  fileprivate var createdAtSortable: Date {
    createdAt ?? .distantPast
  }

  fileprivate var durationSortable: TimeInterval {
    duration ?? 0
  }
}

private struct DestinationControlsView: View {
  let destination: URL?
  var onChooseFolder: () -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text("Destination")
        .font(.headline)
      HStack {
        VStack(alignment: .leading) {
          if let destination {
            Text(destination.lastPathComponent)
              .font(.subheadline)
              .fontWeight(.semibold)
            Text(destination.path)
              .font(.caption)
              .foregroundStyle(.secondary)
              .lineLimit(1)
              .truncationMode(.middle)
              .multilineTextAlignment(.leading)
              .textSelection(.enabled)
          } else {
            Text("No destination selected")
              .font(.subheadline)
              .foregroundStyle(.secondary)
          }
        }
        Spacer()
        Button("Choose Folder") { onChooseFolder() }
          .buttonStyle(.borderedProminent)
      }
    }
  }
}

private struct TransferControlsView: View {
  let selectionCount: Int
  let canSelectAny: Bool
  let destinationLabel: String?
  let isLoading: Bool
  let isTransferring: Bool
  var onTransfer: () -> Void
  var onSelectAll: () -> Void
  var onClearSelection: () -> Void
  var onRefresh: () -> Void
  var onShowDestination: () -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      Button {
        onTransfer()
      } label: {
        HStack(spacing: 10) {
          Image(systemName: isTransferring ? "arrow.triangle.2.circlepath" : "externaldrive.fill")
          VStack(alignment: .leading, spacing: 2) {
            Text(primaryTransferLabel)
              .font(.headline)
            Text(secondaryTransferLabel)
              .font(.subheadline)
              .foregroundStyle(.secondary)
              .lineLimit(1)
          }
          Spacer()
        }
        .frame(maxWidth: .infinity, minHeight: 44)
      }
      .buttonStyle(.borderedProminent)
      .controlSize(.large)
      .disabled(!isTransferEnabled)

      HStack(spacing: 12) {
        Button {
          onSelectAll()
        } label: {
          Label("Select All", systemImage: "checkmark.circle")
        }
        .buttonStyle(.bordered)
        .disabled(!canSelectAny)

        Button {
          onClearSelection()
        } label: {
          Label("Clear", systemImage: "xmark.circle")
        }
        .buttonStyle(.bordered)
        .disabled(selectionCount == 0)

        Button {
          onRefresh()
        } label: {
          Label("Refresh", systemImage: "arrow.clockwise")
        }
        .buttonStyle(.bordered)
        .disabled(isLoading)

        Spacer()

        Button {
          onShowDestination()
        } label: {
          Label("Destination", systemImage: "sidebar.right")
        }
        .buttonStyle(.bordered)
      }

      Text("Choose a destination folder, select episodes, then transfer.")
        .font(.caption)
        .foregroundStyle(.secondary)
    }
  }

  private var isTransferEnabled: Bool {
    destinationLabel != nil && !isLoading && !isTransferring && selectionCount > 0
  }

  private var primaryTransferLabel: String {
    if isTransferring {
      return "Transferring…"
    }
    if selectionCount > 0 {
      return "Transfer \(selectionCount) episode\(selectionCount == 1 ? "" : "s")"
    }
    return "Transfer"
  }

  private var secondaryTransferLabel: String {
    if destinationLabel == nil {
      return "Choose a destination to enable"
    }
    if selectionCount == 0 {
      return "Select episodes from your library"
    }
    if let destinationLabel {
      return "Copies into \(destinationLabel)"
    }
    return ""
  }
}

private struct StatusSummaryView: View {
  let state: TransferState
  let isLoading: Bool

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      switch state {
      case .idle:
        if isLoading {
          HStack {
            ProgressView()
            Text("Scanning library…")
          }
        } else {
          Text("Ready to transfer")
            .foregroundStyle(.secondary)
        }
      case .inProgress(let progress):
        TransferProgressView(progress: progress)
      case .finished(let outcome):
        VStack(alignment: .leading, spacing: 4) {
          Text("Transfer complete to \(outcome.destination.lastPathComponent)")
            .font(.subheadline)
          Text("Copied: \(outcome.copied) · Skipped: \(outcome.skipped)")
            .foregroundStyle(.secondary)
          if !outcome.failed.isEmpty {
            Text("Failed: \(outcome.failed.count)")
              .foregroundStyle(.red)
          }
        }
      case .failed(let message):
        Text(message)
          .foregroundStyle(.red)
      }
    }
  }
}

private struct TransferProgressView: View {
  let progress: TransferState.Progress
  @State private var displayedFraction: Double = 0

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      ProgressView(value: displayedFraction, total: 1)
        .progressViewStyle(.linear)

      Text("Copying \(progress.completed)/\(progress.total)")
        .font(.subheadline)
        .foregroundStyle(.secondary)
    }
    .task(id: taskKey) {
      displayedFraction = max(displayedFraction, baseFraction)
      while !Task.isCancelled {
        let next = min(capFraction, displayedFraction + 0.01)
        if next > displayedFraction {
          withAnimation(.linear(duration: 0.12)) {
            displayedFraction = next
          }
        }
        try? await Task.sleep(for: .milliseconds(120))
      }
    }
    .onChange(of: progress.completed) { _, _ in
      let base = baseFraction
      if base > displayedFraction {
        withAnimation(.easeOut(duration: 0.25)) {
          displayedFraction = base
        }
      }
    }
  }

  private var taskKey: String {
    "\(progress.completed)|\(progress.total)"
  }

  private var baseFraction: Double {
    guard progress.total > 0 else { return 0 }
    return Double(progress.completed) / Double(progress.total)
  }

  private var capFraction: Double {
    guard progress.total > 0 else { return baseFraction }
    // Keep the bar moving slowly within the current item, but never claim completion.
    let cap = (Double(progress.completed) + 0.9) / Double(progress.total)
    return min(max(baseFraction, cap), 0.995)
  }
}

private struct DestinationInspectorView: View {
  let destination: URL?
  let episodes: [PodcastEpisode]
  var artworkLoader: ArtworkLoader
  var onChooseFolder: () -> Void
  var onDelete: (PodcastEpisode) -> Void

  var body: some View {
    VStack(alignment: .center, spacing: 12) {
      DestinationControlsView(destination: destination, onChooseFolder: onChooseFolder)

      Divider()

      if destination == nil {
        ContentUnavailableView(
          "No destination",
          systemImage: "externaldrive",
          description: Text("Choose a folder to see what's already on the device.")
        )
      } else if episodes.isEmpty {
        ContentUnavailableView(
          "Nothing found",
          systemImage: "tray",
          description: Text("No podcast files were found at this destination.")
        )
      } else {
        VStack(alignment: .leading, spacing: 8) {
          Text("On Destination")
            .font(.headline)

          List {
            ForEach(sortedDestinationEpisodes) { episode in
              DestinationEpisodeRow(episode: episode, artworkLoader: artworkLoader) {
                onDelete(episode)
              }
            }
          }
          .listStyle(.inset)
        }
      }
    }
    .padding(16)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
  }

  private var sortedDestinationEpisodes: [PodcastEpisode] {
    episodes.sorted { lhs, rhs in
      (lhs.createdAt ?? .distantPast) > (rhs.createdAt ?? .distantPast)
    }
  }
}

private struct EpisodesListView: View {
  let episodes: [PodcastEpisode]
  let selectedEpisodeIDs: Set<String>
  let isLoading: Bool
  var artworkLoader: ArtworkLoader
  var onToggle: (PodcastEpisode) -> Void

  var body: some View {
    List {
      ForEach(podcastSections, id: \.podcast) { section in
        Section(section.podcast) {
          ForEach(section.episodes) { episode in
            Button {
              onToggle(episode)
            } label: {
              EpisodeRow(
                episode: episode,
                isSelected: selectedEpisodeIDs.contains(episode.id),
                artworkLoader: artworkLoader
              )
            }
            .buttonStyle(.plain)
          }
        }
      }
    }
    .overlay {
      if episodes.isEmpty && !isLoading {
        ContentUnavailableView(
          "No downloads",
          systemImage: "tray",
          description: Text("We could not find any downloaded Apple Podcasts in your library.")
        )
      }
    }
  }

  private var podcastSections: [(podcast: String, episodes: [PodcastEpisode])] {
    Dictionary(grouping: episodes, by: { $0.podcastTitle })
      .map { podcast, episodes in
        let sortedEpisodes = episodes.sorted { lhs, rhs in
          (lhs.createdAt ?? .distantPast) > (rhs.createdAt ?? .distantPast)
        }
        let newest = sortedEpisodes.first?.createdAt ?? .distantPast
        return (podcast: podcast, episodes: sortedEpisodes, newestDate: newest)
      }
      .sorted { $0.newestDate > $1.newestDate }
      .map { ($0.podcast, $0.episodes) }
  }
}

private struct DestinationListView: View {
  let destination: URL?
  let episodes: [PodcastEpisode]
  var artworkLoader: ArtworkLoader
  var onDelete: (PodcastEpisode) -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      if let destination {
        if episodes.isEmpty {
          Text("No podcasts found at \(destination.lastPathComponent)")
            .foregroundStyle(.secondary)
        } else {
          List {
            ForEach(sortedDestinationEpisodes) { episode in
              HStack(alignment: .top, spacing: 10) {
                EpisodeRow(
                  episode: episode,
                  isSelected: false,
                  artworkLoader: artworkLoader,
                  showSelection: false
                )
                Spacer()
                Button(role: .destructive) {
                  onDelete(episode)
                } label: {
                  Label("Delete", systemImage: "trash")
                }
                .buttonStyle(.borderless)
              }
            }
          }
        }
      } else {
        Text("Select a destination to view existing files.")
          .foregroundStyle(.secondary)
      }
    }
  }

  private var sortedDestinationEpisodes: [PodcastEpisode] {
    episodes.sorted { lhs, rhs in
      (lhs.createdAt ?? .distantPast) > (rhs.createdAt ?? .distantPast)
    }
  }
}

private struct DestinationEpisodeRow: View {
  let episode: PodcastEpisode
  var artworkLoader: ArtworkLoader
  var onDelete: () -> Void

  @State private var image: PlatformImage?

  var body: some View {
    HStack(alignment: .top, spacing: 10) {
      ArtworkThumbnail(image: image)
        .frame(width: 32, height: 32)
        .cornerRadius(6)

      VStack(alignment: .leading, spacing: 4) {
        Text(episode.title)
          .font(.subheadline)
          .lineLimit(2)

        Text(episode.podcastTitle)
          .font(.caption)
          .foregroundStyle(.secondary)
          .lineLimit(1)

        HStack(spacing: 10) {
          if let createdAt = episode.createdAt {
            Label(
              createdAt.formatted(date: .abbreviated, time: .shortened),
              systemImage: "calendar"
            )
          }
          if let duration = episode.duration {
            Label(durationString(duration), systemImage: "clock")
          }
          Label(byteCountString(episode.fileSize), systemImage: "externaldrive")
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
      }

      Spacer(minLength: 0)

      Button(role: .destructive) {
        onDelete()
      } label: {
        Image(systemName: "trash")
      }
      .buttonStyle(.borderless)
      .help("Delete")
    }
    .task(id: episode.id) {
      if image == nil {
        image = await artworkLoader.thumbnail(
          for: episode.fileURL,
          fallbackArtworkURL: episode.artworkURL
        )
      }
    }
  }

  private func byteCountString(_ size: Int64) -> String {
    let formatter = ByteCountFormatter()
    formatter.allowedUnits = [.useMB, .useGB]
    formatter.countStyle = .file
    return formatter.string(fromByteCount: size)
  }

  private func durationString(_ duration: TimeInterval) -> String {
    let totalSeconds = Int(duration)
    let minutes = totalSeconds / 60
    let seconds = totalSeconds % 60
    return String(format: "%dm %02ds", minutes, seconds)
  }
}

struct EpisodeRow: View {
  let episode: PodcastEpisode
  var isSelected: Bool
  var artworkLoader: ArtworkLoader
  var showSelection: Bool = true

  @State private var image: PlatformImage?

  var body: some View {
    HStack(alignment: .top, spacing: 10) {
      if showSelection {
        Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
          .foregroundStyle(isSelected ? Color.accentColor : .secondary)
      }
      ArtworkThumbnail(image: image)
        .frame(width: 44, height: 44)
        .cornerRadius(6)
      VStack(alignment: .leading, spacing: 4) {
        Text(episode.title)
          .font(.headline)
        Text(episode.podcastTitle)
          .font(.subheadline)
          .foregroundStyle(.secondary)
        HStack(spacing: 12) {
          if let duration = episode.duration {
            Label(durationString(duration), systemImage: "clock")
              .font(.caption)
              .foregroundStyle(.secondary)
          }
          Label(byteCountString(episode.fileSize), systemImage: "externaldrive")
            .font(.caption)
            .foregroundStyle(.secondary)
          if let createdAt = episode.createdAt {
            Label(
              createdAt.formatted(date: .abbreviated, time: .shortened),
              systemImage: "calendar"
            )
            .font(.caption)
            .foregroundStyle(.secondary)
          }
        }
      }
    }
    #if os(macOS)
      .contextMenu {
        Button("Show in Finder", systemImage: "folder") {
          NSWorkspace.shared.activateFileViewerSelecting([episode.fileURL])
        }
      }
    #endif
    .task {
      if image == nil {
        image = await artworkLoader.thumbnail(
          for: episode.fileURL,
          fallbackArtworkURL: episode.artworkURL
        )
      }
    }
  }

  private func byteCountString(_ size: Int64) -> String {
    let formatter = ByteCountFormatter()
    formatter.allowedUnits = [.useMB, .useGB]
    formatter.countStyle = .file
    return formatter.string(fromByteCount: size)
  }

  private func durationString(_ duration: TimeInterval) -> String {
    let totalSeconds = Int(duration)
    let minutes = totalSeconds / 60
    let seconds = totalSeconds % 60
    return String(format: "%dm %02ds", minutes, seconds)
  }
}

private struct ArtworkThumbnail: View {
  let image: PlatformImage?

  var body: some View {
    Group {
      #if os(macOS)
        if let image {
          Image(nsImage: image)
            .resizable()
            .scaledToFill()
        } else {
          placeholder
        }
      #else
        if let image {
          Image(uiImage: image)
            .resizable()
            .scaledToFill()
        } else {
          placeholder
        }
      #endif
    }
    .background(Color.gray.opacity(0.1))
  }

  private var placeholder: some View {
    ZStack {
      RoundedRectangle(cornerRadius: 6)
        .fill(Color.gray.opacity(0.08))
      Image(systemName: "music.note")
        .foregroundStyle(.secondary)
    }
  }
}

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

#if os(macOS)
  typealias PlatformImage = NSImage
#else
  import UIKit
  typealias PlatformImage = UIImage
#endif
