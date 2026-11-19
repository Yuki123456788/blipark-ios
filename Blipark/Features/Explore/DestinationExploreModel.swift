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
  @Published var strategy = ParkingStrategy.standard { didSet { applyStrategy() } }
  @Published var selectedLocationIDs: [UUID] = []
  @Published var focusedID: UUID?
  @Published private(set) var isLoading = false
  @Published var errorMessage: String?

  let destination: Destination
  private let provider: any ParkingDataProviding

  init(destination: Destination, provider: any ParkingDataProviding) {
    self.destination = destination
    self.provider = provider
  }

  var explorationAreaWidthMeters: Double {
    min(strategy.informationRangeWidthMeters ?? 2_000, ParkingSelectionCoverage.widthMeters)
  }

  var selectedLocations: [ExploredParkingLocation] {
    let lookup = Dictionary(uniqueKeysWithValues: locations.map { ($0.id, $0) })
    return selectedLocationIDs.compactMap { lookup[$0] }
  }

  func load(preferencesRepository: any PreferencesRepository) async {
    isLoading = true
    errorMessage = nil
    defer { isLoading = false }

    do {
      let preferences = try await preferencesRepository.preferences()
      strategy = preferences.globalParkingStrategy
      if strategy.informationRangeWidthMeters == nil {
        strategy.informationRangeWidthMeters = preferences.guidanceTriggerDistanceMeters
      }
    } catch {
      errorMessage = "無法讀取預設偏好：\(error.localizedDescription)"
    }

    do {
      locations = try await provider.parkingLocations(near: destination).compactMap { location in
        guard let coordinate = location.coordinate else { return nil }
        return ExploredParkingLocation(
          location: location,
          straightLineDistanceMeters: destination.coordinate.straightLineDistance(to: coordinate)
        )
      }
      applyStrategy()
      if focusedID == nil { focusedID = visibleLocations.first?.id }
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

  func selectionOrder(for id: UUID) -> Int? {
    selectedLocationIDs.firstIndex(of: id).map { $0 + 1 }
  }

  func toggleSelection(_ id: UUID) {
    focusedID = id
    if let index = selectedLocationIDs.firstIndex(of: id) {
      selectedLocationIDs.remove(at: index)
    } else {
      selectedLocationIDs.append(id)
    }
  }

  func moveSelected(id: UUID, offset: Int) {
    guard let index = selectedLocationIDs.firstIndex(of: id) else { return }
    let target = index + offset
    guard selectedLocationIDs.indices.contains(target) else { return }
    selectedLocationIDs.swapAt(index, target)
  }

  private func applyStrategy() {
    let values = locations.filter { item in
      guard let coordinate = item.location.coordinate else { return false }
      return item.location.supportedVehicleTypes.contains(strategy.vehicleType)
        && strategy.preferredParkingTypes.contains(item.location.type)
        && SquareMapCoverage.contains(
          coordinate,
          centeredAt: destination.coordinate,
          widthMeters: explorationAreaWidthMeters
        )
    }

    visibleLocations = values
    let visibleIDs = Set(values.map(\.id))
    selectedLocationIDs.removeAll { !visibleIDs.contains($0) }
    if let focusedID, !visibleIDs.contains(focusedID) {
      self.focusedID = values.first?.id
    }
  }
}
