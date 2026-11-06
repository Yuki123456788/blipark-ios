import Foundation

@MainActor
final class PlanComposerModel: ObservableObject {
  @Published var planName: String
  @Published var strategy: ParkingStrategy
  @Published var selectedLocationIDs: [UUID] = []
  @Published private(set) var availableLocations: [ParkingLocation]
  @Published var hasScheduledDeparture: Bool
  @Published var scheduledDepartureAt: Date
  @Published private(set) var isLoading = true
  @Published private(set) var isSaving = false
  @Published var errorMessage: String?

  let destination: Destination
  private let existingPlan: ParkingPlan?
  private let parkingProvider: any ParkingDataProviding
  private let preferencesRepository: any PreferencesRepository
  private let planRepository: any PlanRepository
  private let recommendationService = ParkingRecommendationService()
  private var globalStrategy = ParkingStrategy.standard

  init(
    destination: Destination,
    knownLocations: [ParkingLocation],
    existingPlan: ParkingPlan? = nil,
    parkingProvider: any ParkingDataProviding,
    preferencesRepository: any PreferencesRepository,
    planRepository: any PlanRepository
  ) {
    self.destination = destination
    self.existingPlan = existingPlan
    self.parkingProvider = parkingProvider
    self.preferencesRepository = preferencesRepository
    self.planRepository = planRepository
    planName = existingPlan?.name ?? destination.name
    strategy = existingPlan?.strategy ?? .standard
    hasScheduledDeparture = existingPlan?.scheduledDepartureAt != nil
    scheduledDepartureAt = existingPlan?.scheduledDepartureAt ?? .now.addingTimeInterval(3_600)

    var merged = Dictionary(uniqueKeysWithValues: knownLocations.map { ($0.id, $0) })
    if let existingPlan {
      for snapshot in existingPlan.candidates {
        let location = snapshot.parkingLocation
        merged[location.id] = location
      }
      selectedLocationIDs = existingPlan.candidates.map { $0.sourceParkingLocationID ?? $0.id }
    }
    availableLocations = Array(merged.values)
  }

  var selectedLocations: [ParkingLocation] {
    let lookup = Dictionary(uniqueKeysWithValues: availableLocations.map { ($0.id, $0) })
    return selectedLocationIDs.compactMap { lookup[$0] }
  }

  var unselectedLocations: [ParkingLocation] {
    let selected = Set(selectedLocationIDs)
    return availableLocations
      .filter { !selected.contains($0.id) }
      .sorted { distance(for: $0) < distance(for: $1) }
  }

  var usesGlobalStrategy: Bool { strategy == globalStrategy }

  func load() async {
    do {
      let preferences = try await preferencesRepository.preferences()
      globalStrategy = preferences.globalParkingStrategy
      if existingPlan == nil { strategy = globalStrategy }

      let currentLocations = try await parkingProvider.parkingLocations(near: destination)
      var merged = Dictionary(uniqueKeysWithValues: currentLocations.map { ($0.id, $0) })
      for location in availableLocations { merged[location.id] = location }
      availableLocations = Array(merged.values)

      if existingPlan == nil { applyRecommendation() }
    } catch {
      errorMessage = error.localizedDescription
      if existingPlan == nil { applyRecommendation() }
    }
    isLoading = false
  }

  func applyRecommendation() {
    selectedLocationIDs = recommendationService
      .recommend(availableLocations, near: destination, using: strategy)
      .map(\.id)
  }

  func add(_ location: ParkingLocation) {
    guard !selectedLocationIDs.contains(location.id) else { return }
    selectedLocationIDs.append(location.id)
  }

  func remove(at offsets: IndexSet) {
    selectedLocationIDs.remove(atOffsets: offsets)
  }

  func move(from offsets: IndexSet, to destination: Int) {
    selectedLocationIDs.move(fromOffsets: offsets, toOffset: destination)
  }

  func distance(for location: ParkingLocation) -> Double {
    location.coordinate.map { destination.coordinate.straightLineDistance(to: $0) }
      ?? .greatestFiniteMagnitude
  }

  func save() async -> ParkingPlan? {
    guard !selectedLocations.isEmpty else {
      errorMessage = "請至少選擇一個候選停車點。"
      return nil
    }
    isSaving = true
    defer { isSaving = false }
    let now = Date()
    let plan = ParkingPlan(
      id: existingPlan?.id ?? UUID(),
      name: planName.nilIfBlank ?? destination.name,
      destination: destination,
      vehicleType: strategy.vehicleType,
      candidates: selectedLocations.map(ParkingCandidateSnapshot.init(location:)),
      strategy: strategy,
      usesGlobalStrategy: usesGlobalStrategy,
      scheduledDepartureAt: hasScheduledDeparture ? scheduledDepartureAt : nil,
      createdAt: existingPlan?.createdAt ?? now,
      updatedAt: now,
      lastUsedAt: existingPlan?.lastUsedAt
    )
    do {
      try await planRepository.save(plan)
      return plan
    } catch {
      errorMessage = error.localizedDescription
      return nil
    }
  }
}

extension ParkingCandidateSnapshot {
  var parkingLocation: ParkingLocation {
    ParkingLocation(
      id: sourceParkingLocationID ?? id,
      name: name,
      address: address,
      type: type,
      coordinate: coordinate,
      supportedVehicleTypes: supportedVehicleTypes,
      totalSpaceCount: totalSpaceCount,
      charge: charge,
      pricingSummary: pricingSummary,
      notes: notes,
      sourceReference: "plan-snapshot"
    )
  }
}

