import PodcastTransferCore
import SwiftUI

struct StatusSummaryView: View {
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
          SelectionHintView()
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
