import PodcastTransferTelemetry
import Testing

struct TelemetryEventTests {
  @Test
  func transferStartedSignal() {
    let event = TelemetryEvent.transferStarted(selectedCount: 3)

    #expect(event.signalName == "transfer.started")
    #expect(event.parameters == ["selectedCount": "3"])
  }

  @Test
  func transferCompletedSignal() {
    let event = TelemetryEvent.transferCompleted(copied: 2, skipped: 1, failed: 0)

    #expect(event.signalName == "transfer.completed")
    #expect(
      event.parameters == [
        "copied": "2",
        "skipped": "1",
        "failed": "0",
      ]
    )
  }

  @Test
  func toolbarActionSignal() {
    let event = TelemetryEvent.toolbarAction(.refresh)

    #expect(event.signalName == "toolbar.action.refresh")
    #expect(event.parameters.isEmpty)
  }
}
