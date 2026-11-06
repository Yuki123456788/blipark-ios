import SwiftUI

struct PlanCard: View {
  let plan: ParkingPlan

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack(alignment: .top) {
        Image(systemName: "mappin.and.ellipse")
          .foregroundStyle(BliparkStyle.brand)
        VStack(alignment: .leading, spacing: 3) {
          Text(plan.name).font(.headline)
          Text(plan.destination.address ?? plan.destination.name)
            .font(.subheadline).foregroundStyle(.secondary).lineLimit(2)
        }
        Spacer()
      }
      if let departure = plan.scheduledDepartureAt {
        Label(departure.formatted(date: .abbreviated, time: .shortened), systemImage: "calendar")
          .font(.subheadline)
      }
      HStack(spacing: 12) {
        Label(plan.vehicleType.title, systemImage: plan.vehicleType.symbolName)
        Label("\(plan.candidates.count) 個候選", systemImage: "parkingsign")
      }
      .font(.caption)
      .foregroundStyle(.secondary)
      Text(plan.strategy.conciseSummary)
        .font(.caption)
        .foregroundStyle(.secondary)
      if let first = plan.candidates.first {
        Divider()
        Label("第一候選：\(first.name)", systemImage: "1.circle.fill")
          .font(.subheadline.weight(.medium))
      }
    }
    .bliparkCard()
  }
}

