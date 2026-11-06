import SwiftUI

struct BliparkEmptyState: View {
  let title: String
  let message: String
  let symbol: String
  var actionTitle: String?
  var action: (() -> Void)?

  var body: some View {
    ContentUnavailableView {
      Label(title, systemImage: symbol)
    } description: {
      Text(message)
    } actions: {
      if let actionTitle, let action {
        Button(actionTitle, action: action)
          .buttonStyle(.borderedProminent)
      }
    }
  }
}

