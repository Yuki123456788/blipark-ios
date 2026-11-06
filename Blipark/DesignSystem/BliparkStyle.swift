import SwiftUI

enum BliparkStyle {
  static let brand = Color(red: 0.04, green: 0.44, blue: 0.76)
  static let accent = Color(red: 0.03, green: 0.58, blue: 0.55)
  static let cardCornerRadius: CGFloat = 18
}

struct BliparkCardModifier: ViewModifier {
  func body(content: Content) -> some View {
    content
      .padding(16)
      .background(.background, in: RoundedRectangle(cornerRadius: BliparkStyle.cardCornerRadius))
      .overlay {
        RoundedRectangle(cornerRadius: BliparkStyle.cardCornerRadius)
          .stroke(.quaternary, lineWidth: 1)
      }
  }
}

extension View {
  func bliparkCard() -> some View { modifier(BliparkCardModifier()) }
}

