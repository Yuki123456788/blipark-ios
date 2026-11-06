import SwiftUI

struct AppEnvironment: Sendable {
  let destinationSearch: any DestinationSearchProviding
  let parkingData: any ParkingDataProviding
  let plans: any PlanRepository
  let preferences: any PreferencesRepository
  let guidanceSessions: any GuidanceSessionRepository

  static func live(directory: URL = BliparkStorageDirectory.applicationSupport()) -> AppEnvironment {
    AppEnvironment(
      destinationSearch: UnavailableDestinationSearchProvider(),
      parkingData: UnavailableParkingDataProvider(),
      plans: LocalPlanRepository(directory: directory),
      preferences: LocalPreferencesRepository(directory: directory),
      guidanceSessions: LocalGuidanceSessionRepository(directory: directory)
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

