import SwiftUI

private enum SourcePresentationFocusedKey: FocusedValueKey {
  typealias Value = Binding<SourcePresentation>
}

private enum DestinationInspectorPresentedFocusedKey: FocusedValueKey {
  typealias Value = Binding<Bool>
}

extension FocusedValues {
  var sourcePresentation: Binding<SourcePresentation>? {
    get { self[SourcePresentationFocusedKey.self] }
    set { self[SourcePresentationFocusedKey.self] = newValue }
  }

  var isDestinationInspectorPresented: Binding<Bool>? {
    get { self[DestinationInspectorPresentedFocusedKey.self] }
    set { self[DestinationInspectorPresentedFocusedKey.self] = newValue }
  }
}
