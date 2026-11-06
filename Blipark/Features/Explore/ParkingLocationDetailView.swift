import MapKit
import SwiftUI

struct ParkingLocationDetailView: View {
  @Environment(\.dismiss) private var dismiss
  let item: ExploredParkingLocation

  var body: some View {
    NavigationStack {
      List {
        ParkingStreetViewPlaceholder(locationName: item.location.name, height: 190)
          .listRowInsets(EdgeInsets())

        if let coordinate = item.location.coordinate {
          Map(initialPosition: .region(
            MKCoordinateRegion(
              center: coordinate.clLocationCoordinate,
              latitudinalMeters: 700,
              longitudinalMeters: 700
            )
          )) {
            Marker(item.location.name, coordinate: coordinate.clLocationCoordinate)
              .tint(BliparkStyle.brand)
          }
          .frame(height: 220)
          .listRowInsets(EdgeInsets())
        }

        Section("停車資訊") {
          LabeledContent("類型", value: item.location.type.title)
          LabeledContent("與目的地距離", value: distanceText)
          LabeledContent("收費", value: item.location.charge.title)
          if let spaces = item.location.totalSpaceCount {
            LabeledContent("總格位", value: "\(spaces)")
          } else {
            LabeledContent("總格位", value: "未知")
          }
          if let pricing = item.location.pricingSummary {
            LabeledContent("費率", value: pricing)
          }
        }

        Section("適用車種") {
          Text(item.location.supportedVehicleTypes.map(\.title).sorted().joined(separator: "、"))
        }

        if let address = item.location.address {
          Section("位置") { Text(address) }
        }
        if let notes = item.location.notes {
          Section("備註") { Text(notes) }
        }
        Section {
          Label("格位數是靜態資料，不代表目前仍有空位。", systemImage: "info.circle")
            .font(.footnote)
            .foregroundStyle(.secondary)
        }
      }
      .navigationTitle(item.location.name)
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } }
      }
    }
  }

  private var distanceText: String {
    item.straightLineDistanceMeters >= 1_000
      ? String(format: "直線約 %.1f km", item.straightLineDistanceMeters / 1_000)
      : "直線約 \(Int(item.straightLineDistanceMeters.rounded())) m"
  }
}

