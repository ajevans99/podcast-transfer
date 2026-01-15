import PodcastTransferCore
import SwiftUI

struct TransferProgressView: View {
  let progress: TransferState.Progress
  @State private var displayedFraction: Double = 0

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      ProgressView(value: displayedFraction, total: 1)
        .progressViewStyle(.linear)

      Text("Copying \(progress.completed + 1)/\(progress.total)")
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
