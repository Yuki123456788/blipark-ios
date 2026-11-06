import SwiftUI

struct ParkingStreetViewPlaceholder: View {
  let locationName: String
  var height: CGFloat = 150

  var body: some View {
    ZStack {
      LinearGradient(
        colors: [Color.cyan.opacity(0.28), Color.blue.opacity(0.16), Color.green.opacity(0.18)],
        startPoint: .top,
        endPoint: .bottom
      )
      VStack(spacing: 8) {
        Image(systemName: "view.3d")
          .font(.system(size: 34, weight: .medium))
          .foregroundStyle(BliparkStyle.brand)
        Text("街景預覽")
          .font(.headline)
        Text("\(locationName) 的環景資料尚待技術驗證")
          .font(.caption)
          .foregroundStyle(.secondary)
          .multilineTextAlignment(.center)
      }
      .padding()
    }
    .frame(maxWidth: .infinity)
    .frame(height: height)
    .clipShape(RoundedRectangle(cornerRadius: 14))
    .overlay {
      RoundedRectangle(cornerRadius: 14)
        .stroke(Color.secondary.opacity(0.18))
    }
    .accessibilityElement(children: .combine)
    .accessibilityLabel("\(locationName) 街景預覽尚未提供")
  }
}
