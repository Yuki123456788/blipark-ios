import SwiftUI

struct ParkingLocationCard: View {
  let item: ExploredParkingLocation
  let isSelected: Bool

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
      Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
        .font(.title3)
        .foregroundStyle(isSelected ? BliparkStyle.brand : Color.secondary.opacity(0.45))
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

