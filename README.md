## Podcast Transfer (macOS SwiftUI)

Transfer your Apple Podcasts downloads to any folder.

A Swift 6 macOS SwiftUI app that scans downloaded Apple Podcasts from
`~/Library/Group Containers/243LU875E5.groups.com.apple.podcasts/Library/Podcasts`
and copies them to an external MP3 device in one click. The codebase is fully modular
with swift-dependencies, swift-sharing, and snapshot-ready SwiftUI views.

### Modules

- PodcastTransferCore — models, library scanning client, transfer client, shared destination key
- PodcastTransferFeature — `@Observable` view model orchestration using swift-dependencies
- PodcastTransferUI — SwiftUI views (list, destination picker, transfer status)
- PodcastTransferApp — macOS app entry point
- Playground — simple CLI harness for preview data

### Quick start

1. Generate the Xcode project (kept out of git):

```
cd App
xcodegen generate
open PodcastTransfer.xcodeproj
```

2. Build and run the macOS app target `PodcastTransfer`.

3. CLI sample: `swift run --package-path . Playground`

### Testing

- Unit tests: `swift test --filter PodcastTransferCoreTests`
- Snapshot tests: set `SNAPSHOT_TESTING_RECORD=all` to record baselines, then re-run without it to verify

### Tooling

- Format: `make format`
- Lint: `make lint`

### Dependencies

- [swift-dependencies](https://github.com/pointfreeco/swift-dependencies) (>= 1.10.0)
- [swift-sharing](https://github.com/pointfreeco/swift-sharing) (>= 2.7.4)
- [swift-snapshot-testing](https://github.com/pointfreeco/swift-snapshot-testing) (>= 1.18.7) for UI snapshots
