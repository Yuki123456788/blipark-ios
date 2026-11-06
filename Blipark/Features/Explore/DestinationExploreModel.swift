import Foundation

struct ExploredParkingLocation: Identifiable, Equatable {
  let location: ParkingLocation
  let straightLineDistanceMeters: Double
  var id: UUID { location.id }
}

@MainActor
final class DestinationExploreModel: ObservableObject {
  @Published private(set) var locations: [ExploredParkingLocation] = []
  @Published private(set) var visibleLocations: [ExploredParkingLocation] = []
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
      visibleLocations = locations
      if let selectedID, !locations.contains(where: { $0.id == selectedID }) {
        self.selectedID = nil
      }
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
}

