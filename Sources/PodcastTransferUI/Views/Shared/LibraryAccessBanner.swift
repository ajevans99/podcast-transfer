import SwiftUI

/// Prompts the user to grant Podcast Transfer access to the Apple Podcasts library.
///
/// Recent macOS releases protect the Podcasts Group Container, so reading it returns
/// "authorization denied" until the user explicitly grants access via the system file
/// picker. Selecting the folder creates a security-scoped bookmark we reuse on launch.
struct LibraryAccessBanner: View {
  let onGrantAccess: () -> Void

  var body: some View {
    HStack(alignment: .top, spacing: 12) {
      Image(systemName: "lock.shield")
        .font(.title2)
        .foregroundStyle(.orange)

      VStack(alignment: .leading, spacing: 4) {
        Text("Allow access to your Apple Podcasts downloads")
          .font(.subheadline.weight(.semibold))
        Text(
          "macOS protects the Podcasts library. Grant access once so Podcast Transfer "
            + "can read your downloaded episodes."
        )
        .font(.caption)
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
      }

      Spacer(minLength: 8)

      Button("Grant Access…", action: onGrantAccess)
        .buttonStyle(.borderedProminent)
    }
    .padding(12)
    .background(
      RoundedRectangle(cornerRadius: 10, style: .continuous)
        .fill(Color.orange.opacity(0.12))
    )
    .overlay(
      RoundedRectangle(cornerRadius: 10, style: .continuous)
        .strokeBorder(Color.orange.opacity(0.35))
    )
  }
}
