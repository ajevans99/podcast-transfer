import SwiftUI

struct ArtworkThumbnail: View {
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
