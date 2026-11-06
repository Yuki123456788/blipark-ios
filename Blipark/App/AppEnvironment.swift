import SwiftUI

struct AppEnvironment: Sendable {
  let destinationSearch: any DestinationSearchProviding
  let parkingData: any ParkingDataProviding
  let plans: any PlanRepository
  let preferences: any PreferencesRepository
  let guidanceSessions: any GuidanceSessionRepository
  let testDatasets: any TestDatasetRepository
  let developerSettings: any DeveloperSettingsRepository

  static func live(directory: URL = BliparkStorageDirectory.applicationSupport()) -> AppEnvironment {
    let testDatasets = LocalTestDatasetRepository(directory: directory)
    return AppEnvironment(
      destinationSearch: TestDatasetDestinationSearchProvider(repository: testDatasets),
      parkingData: TestDatasetParkingDataProvider(repository: testDatasets),
      plans: LocalPlanRepository(directory: directory),
      preferences: LocalPreferencesRepository(directory: directory),
      guidanceSessions: LocalGuidanceSessionRepository(directory: directory),
      testDatasets: testDatasets,
      developerSettings: LocalDeveloperSettingsRepository(directory: directory)
    )
  }
}

private struct AppEnvironmentKey: EnvironmentKey {
  static let defaultValue = AppEnvironment.live()
}

extension EnvironmentValues {
  var appEnvironment: AppEnvironment {
    get { self[AppEnvironmentKey.self] }
    set { self[AppEnvironmentKey.self] = newValue }
  }
}

