import Foundation

enum ParkingListFilter: String, CaseIterable, Identifiable {
  case all
  case parkingLot
  case onStreet

  var id: String { rawValue }
  var title: String {
    switch self {
    case .all: "全部"
    case .parkingLot: "停車場"
    case .onStreet: "路邊"
    }
  }
}

enum ParkingListSort: String, CaseIterable, Identifiable {
  case distance
  case name

  var id: String { rawValue }
  var title: String { self == .distance ? "距離" : "名稱" }
}

struct ExploredParkingLocation: Identifiable, Equatable {
  let location: ParkingLocation
  let straightLineDistanceMeters: Double
  var id: UUID { location.id }
}

@MainActor
final class DestinationExploreModel: ObservableObject {
  @Published private(set) var locations: [ExploredParkingLocation] = []
  @Published private(set) var visibleLocations: [ExploredParkingLocation] = []
  @Published var filter: ParkingListFilter = .all { didSet { applyPresentation() } }
  @Published var sort: ParkingListSort = .distance { didSet { applyPresentation() } }
  @Published var selectedID: UUID?
  @Published private(set) var isLoading = false
  @Published var errorMessage: String?

  let destination: Destination
  private let provider: any ParkingDataProviding

  init(destination: Destination, provider: any ParkingDataProviding) {
    self.destination = destination
    self.provider = provider
  }

  func load() async {
    isLoading = true
    errorMessage = nil
    defer { isLoading = false }
    do {
      locations = try await provider.parkingLocations(near: destination).compactMap { location in
        guard let coordinate = location.coordinate else { return nil }
        return ExploredParkingLocation(
          location: location,
          straightLineDistanceMeters: destination.coordinate.straightLineDistance(to: coordinate)
        )
      }
      applyPresentation()
    } catch {
      locations = []
      visibleLocations = []
      errorMessage = error.localizedDescription
    }
  }

  func item(id: UUID?) -> ExploredParkingLocation? {
    guard let id else { return nil }
    return locations.first { $0.id == id }
  }

  private func applyPresentation() {
    var values = locations.filter { item in
      switch filter {
      case .all: true
      case .parkingLot: item.location.type == .parkingLot
      case .onStreet: item.location.type == .onStreet
      }
    }
    switch sort {
    case .distance:
      values.sort {
        if $0.straightLineDistanceMeters == $1.straightLineDistanceMeters {
          return $0.location.id.uuidString < $1.location.id.uuidString
        }
        return $0.straightLineDistanceMeters < $1.straightLineDistanceMeters
      }
    case .name:
      values.sort { $0.location.name.localizedStandardCompare($1.location.name) == .orderedAscending }
    }
    visibleLocations = values
    if let selectedID, !values.contains(where: { $0.id == selectedID }) {
      self.selectedID = values.first?.id
    } else if selectedID == nil {
      selectedID = values.first?.id
    }
  }
}

