import Foundation
import SwiftUI

struct DestinationControlsView: View {
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
        Button {
          onChooseFolder()
        } label: {
          Label("Choose Folder", systemImage: "folder")
        }
        .buttonStyle(.bordered)
      }
    }
  }
}
