import SwiftUI

struct ParkingLocationCard: View {
  let item: ExploredParkingLocation
  let selectionOrder: Int?

  private var isSelected: Bool { selectionOrder != nil }

  var body: some View {
    HStack(alignment: .top, spacing: 12) {
      Image(systemName: item.location.type.symbolName)
        .font(.title3)
        .foregroundStyle(isSelected ? .white : BliparkStyle.brand)
        .frame(width: 34, height: 34)
        .background(isSelected ? BliparkStyle.brand : BliparkStyle.brand.opacity(0.12), in: Circle())
      VStack(alignment: .leading, spacing: 5) {
        Text(item.location.name)
          .font(.headline)
          .foregroundStyle(.primary)
        HStack(spacing: 8) {
          Text(item.location.type.title)
          Text(distanceText)
          Text(item.location.charge.title)
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        if let spaces = item.location.totalSpaceCount {
          Text("總格位 \(spaces)・不代表即時空位")
            .font(.caption)
            .foregroundStyle(.secondary)
        }
      }
      Spacer(minLength: 4)
      if let selectionOrder {
        Text("\(selectionOrder)")
          .font(.caption.bold())
          .foregroundStyle(.white)
          .frame(width: 26, height: 26)
          .background(BliparkStyle.brand, in: Circle())
          .accessibilityLabel("第 \(selectionOrder) 順位")
      } else {
        Image(systemName: "plus.circle")
          .font(.title3)
          .foregroundStyle(Color.secondary.opacity(0.55))
      }
    }
    .padding(14)
    .background(.background, in: RoundedRectangle(cornerRadius: 16))
    .overlay {
      RoundedRectangle(cornerRadius: 16)
        .stroke(isSelected ? BliparkStyle.brand : Color.secondary.opacity(0.16), lineWidth: isSelected ? 2 : 1)
    }
  }

  private var distanceText: String {
    let meters = item.straightLineDistanceMeters
    return meters >= 1_000
      ? String(format: "直線約 %.1f km", meters / 1_000)
      : "直線約 \(Int(meters.rounded())) m"
  }
}

