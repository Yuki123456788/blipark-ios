import CoreLocation
import UIKit

@MainActor
final class PiPRealLocationService: NSObject, ObservableObject {
  @Published private(set) var authorizationStatus: CLAuthorizationStatus
  @Published private(set) var currentLocation: CLLocation?
  @Published private(set) var currentHeading: CLLocationDirection?
  @Published private(set) var currentHeadingTimestamp: Date?
  @Published private(set) var headingOrientationDescription = "直向"
  @Published private(set) var lastError: String?
  @Published private(set) var isTracking = false

  var onLocation: ((CLLocation) -> Void)?
  var onHeading: ((CLLocationDirection) -> Void)?
  var onAuthorizationChange: ((CLAuthorizationStatus) -> Void)?

  private let manager = CLLocationManager()
  private var maximumHorizontalAccuracy = 100.0
  private var stableCourse: CLLocationDirection?
  private var lastAcceptedLocation: CLLocation?
  private var observesDeviceOrientation = false

  override init() {
    authorizationStatus = manager.authorizationStatus
    super.init()
    manager.delegate = self
    manager.desiredAccuracy = kCLLocationAccuracyBest
    manager.activityType = .automotiveNavigation
    manager.distanceFilter = 10
    manager.headingFilter = 2
    manager.pausesLocationUpdatesAutomatically = false
  }

  func configure(distanceFilter: CLLocationDistance, maximumHorizontalAccuracy: CLLocationAccuracy)
  {
    manager.distanceFilter = max(1, distanceFilter)
    self.maximumHorizontalAccuracy = max(20, maximumHorizontalAccuracy)
  }

  func start() {
    lastError = nil
    switch manager.authorizationStatus {
    case .notDetermined:
      manager.requestWhenInUseAuthorization()
    case .authorizedAlways, .authorizedWhenInUse:
      beginUpdates()
    case .denied, .restricted:
      lastError = "定位權限未開啟，請到「設定」允許此 App 使用定位。"
      onAuthorizationChange?(manager.authorizationStatus)
    @unknown default:
      lastError = "無法判斷目前的定位權限。"
    }
  }

  func stop() {
    manager.stopUpdatingLocation()
    manager.stopUpdatingHeading()
    isTracking = false
    stableCourse = nil
    lastAcceptedLocation = nil
    currentHeading = nil
    currentHeadingTimestamp = nil
    stopObservingDeviceOrientation()
  }

  private func beginUpdates() {
    manager.allowsBackgroundLocationUpdates = true
    manager.showsBackgroundLocationIndicator = true
    manager.startUpdatingLocation()
    if CLLocationManager.headingAvailable() {
      startObservingDeviceOrientation()
      updateHeadingOrientation()
      manager.startUpdatingHeading()
    }
    isTracking = true
    if let location = manager.location {
      accept(location)
    }
  }

  private func startObservingDeviceOrientation() {
    guard !observesDeviceOrientation else { return }
    observesDeviceOrientation = true
    UIDevice.current.beginGeneratingDeviceOrientationNotifications()
    NotificationCenter.default.addObserver(
      self,
      selector: #selector(deviceOrientationDidChange),
      name: UIDevice.orientationDidChangeNotification,
      object: nil
    )
  }

  private func stopObservingDeviceOrientation() {
    guard observesDeviceOrientation else { return }
    observesDeviceOrientation = false
    NotificationCenter.default.removeObserver(
      self,
      name: UIDevice.orientationDidChangeNotification,
      object: nil
    )
    UIDevice.current.endGeneratingDeviceOrientationNotifications()
  }

  @objc private func deviceOrientationDidChange() {
    updateHeadingOrientation()
  }

  @discardableResult
  private func updateHeadingOrientation() -> Bool {
    guard
      let orientation = Self.headingOrientation(for: UIDevice.current.orientation)
    else { return false }
    guard manager.headingOrientation != orientation else { return false }
    manager.headingOrientation = orientation
    currentHeading = nil
    currentHeadingTimestamp = nil
    headingOrientationDescription = Self.description(for: orientation)
    return true
  }

  nonisolated static func headingOrientation(
    for deviceOrientation: UIDeviceOrientation
  ) -> CLDeviceOrientation? {
    switch deviceOrientation {
    case .portrait: .portrait
    case .portraitUpsideDown: .portraitUpsideDown
    case .landscapeLeft: .landscapeLeft
    case .landscapeRight: .landscapeRight
    default: nil
    }
  }

  private static func description(for orientation: CLDeviceOrientation) -> String {
    switch orientation {
    case .portrait: "直向"
    case .portraitUpsideDown: "倒置直向"
    case .landscapeLeft: "橫向（左）"
    case .landscapeRight: "橫向（右）"
    default: "沿用前次方向"
    }
  }

  private func accept(_ location: CLLocation) {
    guard abs(location.timestamp.timeIntervalSinceNow) <= 15,
      location.horizontalAccuracy >= 0,
      location.horizontalAccuracy <= maximumHorizontalAccuracy
    else { return }

    if let previous = lastAcceptedLocation {
      let elapsed = location.timestamp.timeIntervalSince(previous.timestamp)
      guard elapsed > 0 else { return }
      let plausibleDistance = max(
        100,
        elapsed * 75 + previous.horizontalAccuracy + location.horizontalAccuracy
      )
      guard location.distance(from: previous) <= plausibleDistance else { return }
    }

    if location.speed >= 2, location.course >= 0 {
      stableCourse = location.course
    }
    let course = stableCourse ?? -1
    let accepted = CLLocation(
      coordinate: location.coordinate,
      altitude: location.altitude,
      horizontalAccuracy: location.horizontalAccuracy,
      verticalAccuracy: location.verticalAccuracy,
      course: course,
      speed: max(location.speed, 0),
      timestamp: location.timestamp
    )
    lastAcceptedLocation = accepted
    currentLocation = accepted
    onLocation?(accepted)
  }
}

extension PiPRealLocationService: @preconcurrency CLLocationManagerDelegate {
  func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
    authorizationStatus = manager.authorizationStatus
    onAuthorizationChange?(authorizationStatus)
    if authorizationStatus == .authorizedAlways || authorizationStatus == .authorizedWhenInUse {
      beginUpdates()
    } else if authorizationStatus == .denied || authorizationStatus == .restricted {
      stop()
      lastError = "定位權限未開啟，無法執行真實定位導航測試。"
    }
  }

  func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
    for location in locations.sorted(by: { $0.timestamp < $1.timestamp }) {
      accept(location)
    }
  }

  func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) {
    if updateHeadingOrientation() { return }
    guard newHeading.headingAccuracy >= 0 else { return }
    let value = newHeading.trueHeading >= 0 ? newHeading.trueHeading : newHeading.magneticHeading
    currentHeading = value
    currentHeadingTimestamp = Date()
    onHeading?(value)
  }

  func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
    guard (error as? CLError)?.code != .locationUnknown else { return }
    lastError = "定位更新失敗：\(error.localizedDescription)"
  }
}
