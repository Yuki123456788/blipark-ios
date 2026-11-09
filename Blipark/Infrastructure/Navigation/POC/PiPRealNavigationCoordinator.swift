import Combine
import CoreLocation
import MapKit
import SwiftUI
import UIKit

private enum PiPRealNavigationRenderPayload {
  case standby(distanceMeters: CLLocationDistance?)
  case navigating(
    route: PiPNavigationPreparedRoute,
    observation: PiPRealMotionObservation,
    cameraInput: PiPDynamicCameraInput,
    zoomMode: PiPDynamicZoomMode,
    debugTileBoundaries: Bool,
    positionPredictionLimitSeconds: TimeInterval,
    presentationStartedAt: TimeInterval,
    routeOverviewDurationSeconds: TimeInterval,
    routeOverviewTransitionSeconds: TimeInterval,
    presentationPrompt: String,
    navigationOverlay: PiPRealNavigationRenderOverlay
  )
}

private final class PiPRealNavigationRenderRuntime: @unchecked Sendable {
  private let lock = NSLock()
  private var payload: PiPRealNavigationRenderPayload = .standby(distanceMeters: nil)

  func update(_ value: PiPRealNavigationRenderPayload) {
    lock.withLock { payload = value }
  }

  func snapshot() -> PiPRealNavigationRenderPayload {
    lock.withLock { payload }
  }
}

private final class PiPRealMotionRuntime: @unchecked Sendable {
  private let lock = NSLock()
  private var interpolator = PiPRealMotionInterpolator()

  func reset() {
    lock.withLock { interpolator.reset() }
  }

  func sample(
    for observation: PiPRealMotionObservation,
    sourceMetersPerPixel: CGFloat,
    predictionLimitSeconds: TimeInterval,
    at time: TimeInterval
  ) -> PiPNavigationSample {
    lock.withLock {
      interpolator.sample(
        for: observation,
        sourceMetersPerPixel: sourceMetersPerPixel,
        predictionLimitSeconds: predictionLimitSeconds,
        at: time
      )
    }
  }
}

private final class PiPRealHeadingRuntime: @unchecked Sendable {
  private let lock = NSLock()
  private var heading: CLLocationDirection?

  func update(_ value: CLLocationDirection?) {
    lock.withLock { heading = value }
  }

  func snapshot() -> CLLocationDirection? {
    lock.withLock { heading }
  }
}

private enum PiPRealNavigationRenderer {
  static func renderStandby(
    distanceMeters: CLLocationDistance?,
    provider: PiPBenchmarkPixelBufferProvider,
    outputSize: CGSize
  ) throws -> PiPNavigationRenderedFrame {
    let allocationStart = ProcessInfo.processInfo.systemUptime
    let pixelBuffer = try provider.makePixelBuffer()
    let allocationEnd = ProcessInfo.processInfo.systemUptime
    try PiPBenchmarkDrawing.withPixelBufferContext(pixelBuffer) { context, size in
      context.translateBy(x: 0, y: size.height)
      context.scaleBy(x: 1, y: -1)
      context.setFillColor(UIColor(red: 0.035, green: 0.09, blue: 0.16, alpha: 1).cgColor)
      context.fill(CGRect(origin: .zero, size: size))

      UIGraphicsPushContext(context)
      defer { UIGraphicsPopContext() }
      let distance =
        distanceMeters.map {
          $0 >= 1_000 ? String(format: "%.1f km", $0 / 1_000) : "\(Int($0)) m"
        } ?? "定位中"
      let text = "Blipark  •  待機中  •  距離目的地 \(distance)"
      let attributes: [NSAttributedString.Key: Any] = [
        .font: UIFont.systemFont(ofSize: max(24, size.height * 0.31), weight: .semibold),
        .foregroundColor: UIColor.white,
      ]
      let textSize = text.size(withAttributes: attributes)
      text.draw(
        at: CGPoint(
          x: max(20, (size.width - textSize.width) / 2), y: (size.height - textSize.height) / 2),
        withAttributes: attributes
      )
    }
    let end = ProcessInfo.processInfo.systemUptime
    return PiPNavigationRenderedFrame(
      pixelBuffer: pixelBuffer,
      pixelBufferMilliseconds: (allocationEnd - allocationStart) * 1_000,
      renderMilliseconds: (end - allocationEnd) * 1_000
    )
  }
}

@MainActor
final class PiPRealNavigationCoordinator: ObservableObject {
  @Published private(set) var state: PiPRealNavigationState = .idle
  @Published private(set) var settings = PiPRealNavigationSettings()
  @Published private(set) var finalDestination: PiPRealNavigationDestination?
  @Published private(set) var parkingStops: [PiPRealParkingStop] = []
  @Published private(set) var activeParkingIndex = 0
  @Published private(set) var statusMessage = "設定最終目的地與候選停車點後即可開始。"
  @Published private(set) var lastError: String?
  @Published private(set) var debug = PiPRealNavigationDebugSnapshot()
  @Published private(set) var authorizationStatus: CLAuthorizationStatus = .notDetermined
  @Published private(set) var preparedTileCount = 0
  @Published private(set) var failedTileCount = 0

  let locationService = PiPRealLocationService()

  private weak var manager: PiPManager?
  private var subscriptions = Set<AnyCancellable>()
  private var mapSource: (any PiPNavigationProjectionSource)?
  private var route: PiPNavigationPreparedRoute?
  private var preparationTask: Task<Void, Never>?
  private var rerouteTask: Task<Void, Never>?
  private var nextRouteTask: Task<Void, Never>?
  private var pipStartTask: Task<Void, Never>?
  private var renderTimer: DispatchSourceTimer?
  private var activeRunID: UUID?
  private let renderQueue = DispatchQueue(
    label: "com.blipark.iOSOverlayLab.real-navigation",
    qos: .userInitiated
  )
  private let renderRuntime = PiPRealNavigationRenderRuntime()
  private let cameraRuntime = PiPDynamicCameraRuntime()
  private let motionRuntime = PiPRealMotionRuntime()
  private let headingRuntime = PiPRealHeadingRuntime()
  private let submissionSlot = DispatchSemaphore(value: 1)
  private var offRouteCount = 0
  private var lastRerouteAt: Date?
  private var didActivatePiP = false
  private var isEnding = false
  private var renderFrameCount = 0
  private var renderFPSStartedAt = ProcessInfo.processInfo.systemUptime
  private var navigationPresentationStartedAt: TimeInterval?
  private var nextRoute: PiPNavigationPreparedRoute?
  private var nextRouteLastAttemptAt: Date?
  private var parkingAdvanceDetector = PiPRealParkingAdvanceDetector()
  private var activeOverviewDurationSeconds = 2.0
  private var activeOverviewTransitionSeconds = 1.2
  private var activeOverviewPrompt = "開始導航・先看完整路線"
  private var usesCourseForVehicleHeading = false

  var canEditConfiguration: Bool { state == .idle || state == .ended || state == .failed }
  var isSessionRunning: Bool {
    [.preparingSession, .standby, .preparingNavigation, .navigating].contains(state)
  }
  var activeParkingStop: PiPRealParkingStop? {
    parkingStops.indices.contains(activeParkingIndex) ? parkingStops[activeParkingIndex] : nil
  }

  init() {
    locationService.onLocation = { [weak self] location in self?.handle(location: location) }
    locationService.onHeading = { [weak self] heading in self?.handle(heading: heading) }
    locationService.onAuthorizationChange = { [weak self] status in
      guard let self else { return }
      authorizationStatus = status
      if status == .denied || status == .restricted {
        fail("定位權限未開啟，無法開始測試。")
      }
    }
    authorizationStatus = locationService.authorizationStatus
  }

  func attach(manager: PiPManager) {
    guard self.manager !== manager else { return }
    self.manager = manager
    subscriptions.removeAll()
    manager.$isActive
      .removeDuplicates()
      .sink { [weak self] active in
        guard let self else { return }
        if active {
          didActivatePiP = true
          if state == .preparingSession { enterStandbyAndOpenMaps() }
        } else if didActivatePiP, isSessionRunning, !isEnding {
          endSession(message: "PiP 已由使用者或系統關閉，本次測試已結束。")
        }
      }
      .store(in: &subscriptions)
    manager.$status
      .sink { [weak self] status in
        guard let self, isSessionRunning, status == .failed else { return }
        fail(manager.lastError ?? "PiP 啟動失敗。")
      }
      .store(in: &subscriptions)
  }

  func setTriggerDistance(_ meters: CLLocationDistance) {
    settings.triggerDistanceMeters = min(max(meters, 100), 10_000)
  }

  func setZoomMode(_ mode: PiPDynamicZoomMode) {
    settings.zoomMode = mode
    refreshRenderPayload()
  }

  func setRenderMode(_ mode: PiPRealNavigationRenderMode) {
    guard canEditConfiguration else { return }
    settings.renderMode = mode
  }

  func setTileGrid(_ grid: PiPTileNavigationGridPreset) {
    guard canEditConfiguration else { return }
    settings.tileGrid = grid
  }

  func setCustomTriggerKilometers(_ value: Double) {
    setTriggerDistance(value * 1_000)
  }

  func setLocationDistanceFilter(_ value: Double) {
    settings.locationDistanceFilter = min(max(value, 1), 100)
  }

  func setPositionPredictionLimit(_ value: Double) {
    settings.positionPredictionLimitSeconds = min(max(value, 0), 4)
    debug.displayedPositionMode =
      settings.positionPredictionLimitSeconds > 0
      ? "GPS＋最多 \(String(format: "%.1f", settings.positionPredictionLimitSeconds)) 秒推估"
      : "GPS 原始點"
    refreshRenderPayload()
  }

  func setMaximumAccuracy(_ value: Double) {
    settings.maximumHorizontalAccuracy = min(max(value, 20), 250)
  }

  func setOffRouteThreshold(_ value: Double) {
    settings.offRouteThresholdMeters = min(max(value, 30), 250)
  }

  func setDebugTileBoundaries(_ value: Bool) {
    settings.showsDebugTileBoundaries = value
    refreshRenderPayload()
  }

  func setLookAheadSeconds(_ value: Double) {
    settings.cameraConfiguration.lookAheadSeconds = min(max(value, 10), 40)
    cameraRuntime.updateConfiguration(settings.cameraConfiguration)
  }

  func setResponseDuration(_ value: Double) {
    settings.cameraConfiguration.responseDuration = min(max(value, 0.3), 2)
    cameraRuntime.updateConfiguration(settings.cameraConfiguration)
  }

  func setFixedLookAhead(_ value: Double) {
    settings.cameraConfiguration.fixedLookAheadMeters = min(max(value, 80), 1_500)
    cameraRuntime.updateConfiguration(settings.cameraConfiguration)
  }

  func setCameraPitch(_ value: Double) {
    settings.cameraConfiguration.pitchDegrees = min(max(value, 0), 55)
    cameraRuntime.updateConfiguration(settings.cameraConfiguration)
  }

  func setRouteOverviewDuration(_ value: Double) {
    settings.routeOverviewDurationSeconds = min(max(value, 1), 3)
  }

  func setRerouteOverviewDuration(_ value: Double) {
    settings.rerouteOverviewDurationSeconds = min(max(value, 0.3), 1.5)
  }

  func setNextRoutePreviewDistance(_ value: Double) {
    settings.nextRoutePreviewDistanceMeters = min(max(value, 50), 250)
  }

  func restoreDefaults() {
    guard canEditConfiguration else { return }
    settings = PiPRealNavigationSettings()
  }

  func start(
    finalDestination: PiPRealNavigationDestination,
    parkingStops: [PiPRealParkingStop]
  ) {
    guard let manager else {
      fail("PiP Manager 尚未連接。")
      return
    }
    guard !isSessionRunning else { return }
    guard !parkingStops.isEmpty else {
      fail("請至少加入一個停車點。")
      return
    }
    cleanupResources(cleanupPiP: true)
    self.finalDestination = finalDestination
    self.parkingStops = parkingStops
    activeParkingIndex = 0
    state = .preparingSession
    statusMessage = "正在要求定位並預先準備最終目的地周邊地圖。"
    lastError = nil
    debug = PiPRealNavigationDebugSnapshot()
    didActivatePiP = false
    isEnding = false
    preparedTileCount = 0
    failedTileCount = 0
    offRouteCount = 0
    lastRerouteAt = nil
    nextRoute = nil
    nextRouteLastAttemptAt = nil
    parkingAdvanceDetector.reset()
    cameraRuntime.updateConfiguration(settings.cameraConfiguration)
    cameraRuntime.reset()
    motionRuntime.reset()
    let hasFreshHeading =
      locationService.currentHeadingTimestamp.map {
        abs($0.timeIntervalSinceNow) <= 2
      } ?? false
    headingRuntime.update(hasFreshHeading ? locationService.currentHeading : nil)
    usesCourseForVehicleHeading = false
    debug.vehicleHeadingSource = hasFreshHeading ? "裝置羅盤" : "等待方向"
    navigationPresentationStartedAt = nil
    activeOverviewDurationSeconds = settings.routeOverviewDurationSeconds
    activeOverviewTransitionSeconds = settings.routeOverviewTransitionSeconds
    activeOverviewPrompt = "開始導航・先看完整路線"
    debug.displayedPositionMode =
      settings.positionPredictionLimitSeconds > 0
      ? "GPS＋最多 \(String(format: "%.1f", settings.positionPredictionLimitSeconds)) 秒推估"
      : "GPS 原始點"
    locationService.configure(
      distanceFilter: settings.locationDistanceFilter,
      maximumHorizontalAccuracy: settings.maximumHorizontalAccuracy
    )
    locationService.start()
    authorizationStatus = locationService.authorizationStatus
    if manager.isActive { manager.stop() }
    if let location = locationService.currentLocation,
      abs(location.timestamp.timeIntervalSinceNow) <= 15
    {
      handle(location: location)
    }
  }

  func endSession(message: String = "測試已由使用者結束。") {
    guard state != .idle, state != .ended else { return }
    isEnding = true
    cleanupResources(cleanupPiP: true)
    state = .ended
    statusMessage = message
    isEnding = false
  }

  func reset() {
    cleanupResources(cleanupPiP: true)
    finalDestination = nil
    parkingStops = []
    activeParkingIndex = 0
    state = .idle
    statusMessage = "設定最終目的地與候選停車點後即可開始。"
    lastError = nil
    debug = PiPRealNavigationDebugSnapshot()
  }

  func detach() {
    if isSessionRunning { endSession(message: "離開測試畫面，Session 已結束。") }
    subscriptions.removeAll()
    manager = nil
  }

  func updateApplicationState(_ phase: ScenePhase) {
    switch phase {
    case .active: debug.applicationState = "active"
    case .inactive: debug.applicationState = "inactive"
    case .background: debug.applicationState = "background"
    @unknown default: debug.applicationState = "unknown"
    }
  }

  private func handle(location: CLLocation) {
    let hasFreshHeading =
      locationService.currentHeadingTimestamp.map {
        abs($0.timeIntervalSinceNow) <= 2
      } ?? false
    if location.speed >= 2, location.course >= 0 {
      usesCourseForVehicleHeading = true
      headingRuntime.update(location.course)
      debug.vehicleHeadingSource = "GPS 行進方向"
    } else {
      usesCourseForVehicleHeading = false
      if hasFreshHeading, let heading = locationService.currentHeading {
        headingRuntime.update(heading)
        debug.vehicleHeadingSource = "裝置羅盤"
      } else if location.course >= 0 {
        headingRuntime.update(location.course)
        debug.vehicleHeadingSource = "最近 GPS 方向"
      }
    }
    updateDebug(location: location)
    guard let finalDestination else { return }
    let distance = location.distance(
      from: CLLocation(
        latitude: finalDestination.coordinate.latitude,
        longitude: finalDestination.coordinate.longitude
      ))
    debug.straightLineDistanceMeters = distance

    switch state {
    case .preparingSession:
      prepareSessionIfNeeded()
    case .standby:
      renderRuntime.update(.standby(distanceMeters: distance))
      if distance <= settings.triggerDistanceMeters {
        prepareNavigation(from: location, isReroute: false)
      }
    case .navigating:
      handleNavigatingLocation(location)
    default:
      break
    }
  }

  private func handle(heading: CLLocationDirection) {
    debug.deviceHeading = heading
    guard !usesCourseForVehicleHeading else { return }
    headingRuntime.update(heading)
    debug.vehicleHeadingSource = "裝置羅盤"
  }

  private func prepareSessionIfNeeded() {
    guard preparationTask == nil, let finalDestination else { return }
    let renderMode = settings.renderMode
    let tileConfiguration = settings.tileGrid.realNavigationSquareConfiguration
    preparationTask = Task { [weak self] in
      guard let self else { return }
      do {
        let source: any PiPNavigationProjectionSource
        switch renderMode {
        case .singleSnapshot:
          let asset = try await PreCapturedRasterNavigationRenderer.capture(
            center: finalDestination.coordinate,
            widthMeters: PiPRealNavigationSettings.snapshotCoverageWidthMeters,
            pixelSize: PiPRealNavigationSettings.snapshotPixelSize,
            hidesPointsOfInterest: true
          )
          guard let image = asset.image.cgImage else {
            throw PiPNavigationPreparationError.missingImage
          }
          source = PiPNavigationMapSource(
            image: image,
            mapRect: asset.mapRect,
            geographicWidthMeters: asset.geographicWidthMeters,
            center: finalDestination.coordinate,
            projection: asset.projection
          )
        case .tileGrid:
          source = try await PiPTileNavigationSnapshotService.capture(
            center: finalDestination.coordinate,
            configuration: tileConfiguration
          ) { [weak self] progress in
            self?.preparedTileCount = progress.succeeded
            self?.failedTileCount = progress.failed
            self?.statusMessage = progress.message
          }
        }
        try Task.checkCancellation()
        mapSource = source
        debug.mapCoverage = "最終目的地周邊 4 × 4 km 已預擷取"
        statusMessage = "地圖已就緒，正在建立 8:1 PiP 待機畫面。"
        configureOutput(size: CGSize(width: 1_600, height: 200), framesPerSecond: 2)
        renderRuntime.update(.standby(distanceMeters: debug.straightLineDistanceMeters))
        preparationTask = nil
        await startPiPWhenReady()
      } catch is CancellationError {
        preparationTask = nil
      } catch {
        preparationTask = nil
        fail("地圖準備失敗：\(error.localizedDescription)")
      }
    }
  }

  private func startPiPWhenReady() async {
    guard let manager else { return }
    guard manager.status != .unsupported else {
      fail("此裝置不支援系統子母畫面，無法啟動搭配地圖導航。")
      return
    }
    for _ in 0..<24 {
      guard state == .preparingSession else { return }
      if manager.isPreviewReady, manager.isPossible {
        manager.startFromUserAction()
        statusMessage = "已要求啟動 PiP，等待系統確認。"
        return
      }
      try? await Task.sleep(for: .milliseconds(250))
    }
    fail("PiP 準備逾時，請確認畫面中的 PiP 預覽可見，且沒有其他 App 正在使用 PiP 後重試。")
  }

  private func enterStandbyAndOpenMaps() {
    guard state == .preparingSession else { return }
    state = .standby
    statusMessage = "8:1 PiP 待機中；持續監控與最終目的地的直線距離。"
    if let distance = debug.straightLineDistanceMeters,
      distance <= settings.triggerDistanceMeters,
      let location = locationService.currentLocation
    {
      prepareNavigation(from: location, isReroute: false)
      return
    }
  }

  private func prepareNavigation(from location: CLLocation, isReroute: Bool) {
    guard rerouteTask == nil, let source = mapSource, let parkingStop = activeParkingStop else {
      return
    }
    if !isReroute {
      guard state == .standby else { return }
      state = .preparingNavigation
      statusMessage = "已進入觸發距離，正在取得 MKDirections 路線。"
    }
    let startedInBackground = UIApplication.shared.applicationState == .background
    debug.routeStatus = isReroute ? "背景重算中" : "首次路線查詢中"
    rerouteTask = Task { [weak self] in
      guard let self else { return }
      do {
        let prepared = try await calculateRoute(
          from: location.coordinate,
          to: parkingStop.destination,
          source: source
        )
        try Task.checkCancellation()
        route = prepared
        nextRoute = nil
        nextRouteTask?.cancel()
        nextRouteTask = nil
        parkingAdvanceDetector.reset()
        offRouteCount = 0
        if isReroute {
          lastRerouteAt = Date()
          debug.lastRerouteAt = lastRerouteAt
        }
        let completedInBackground = UIApplication.shared.applicationState == .background
        debug.routeStatus =
          "路線成功（\(startedInBackground ? "背景" : "前景")開始／\(completedInBackground ? "背景" : "前景")完成）"
        debug.routeDistanceMeters = prepared.routeDistanceMeters
        debug.activeParkingStop = parkingStop.name
        debug.nextRouteStatus =
          activeParkingIndex + 1 < parkingStops.count
          ? "等待接近目前停車點" : "沒有下一個停車點"
        if !source.contains(prepared.coordinates) {
          debug.mapCoverage = "部分路線超出預擷取範圍，將顯示可用區域"
        }
        navigationPresentationStartedAt = ProcessInfo.processInfo.systemUptime
        if isReroute {
          activeOverviewDurationSeconds = settings.rerouteOverviewDurationSeconds
          activeOverviewTransitionSeconds = settings.rerouteOverviewTransitionSeconds
          activeOverviewPrompt = "路線已更新・先看完整路線"
          statusMessage = "偏航路線已更新；短暫顯示完整路線後回到即時導航。"
        } else {
          activeOverviewDurationSeconds = settings.routeOverviewDurationSeconds
          activeOverviewTransitionSeconds = settings.routeOverviewTransitionSeconds
          activeOverviewPrompt = "開始導航・先看完整路線"
        }
        if state == .preparingNavigation {
          configureOutput(size: CGSize(width: 1_280, height: 720), framesPerSecond: 15)
          state = .navigating
          statusMessage = "已切換為 16:9；先顯示完整路線，再進入即時導航。"
        }
        rerouteTask = nil
        handleNavigatingLocation(location)
      } catch is CancellationError {
        rerouteTask = nil
      } catch {
        rerouteTask = nil
        let completedInBackground = UIApplication.shared.applicationState == .background
        debug.routeStatus =
          "路線失敗（\(startedInBackground ? "背景" : "前景")開始／\(completedInBackground ? "背景" : "前景")結束）：\(error.localizedDescription)"
        if isReroute, route != nil {
          lastError = "背景路線重算失敗，保留目前路線：\(error.localizedDescription)"
          lastRerouteAt = Date()
          debug.lastRerouteAt = lastRerouteAt
        } else {
          fail("無法準備導航路線：\(error.localizedDescription)")
        }
      }
    }
  }

  private func calculateRoute(
    from coordinate: CLLocationCoordinate2D,
    to destination: PiPRealNavigationDestination,
    source: any PiPNavigationProjectionSource
  ) async throws -> PiPNavigationPreparedRoute {
    let request = MKDirections.Request()
    request.source = MKMapItem(placemark: MKPlacemark(coordinate: coordinate))
    request.destination = destination.mapItem
    request.transportType = .automobile
    request.requestsAlternateRoutes = false
    let directions = MKDirections(request: request)
    return try await withTaskCancellationHandler {
      let response = try await directions.calculate()
      try Task.checkCancellation()
      guard let mkRoute = response.routes.first else {
        throw PiPNavigationPreparationError.noRoute(destination.name)
      }
      var coordinates = [CLLocationCoordinate2D](
        repeating: CLLocationCoordinate2D(), count: mkRoute.polyline.pointCount
      )
      mkRoute.polyline.getCoordinates(
        &coordinates,
        range: NSRange(location: 0, length: mkRoute.polyline.pointCount)
      )
      guard coordinates.count >= 2 else {
        throw PiPNavigationPreparationError.tooFewRoutePoints(destination.name)
      }
      let steps = mkRoute.steps.compactMap { step -> PiPNavigationRouteStep? in
        guard step.distance > 0, step.polyline.pointCount >= 2 else { return nil }
        var values = [CLLocationCoordinate2D](
          repeating: CLLocationCoordinate2D(), count: step.polyline.pointCount
        )
        step.polyline.getCoordinates(
          &values, range: NSRange(location: 0, length: step.polyline.pointCount))
        return PiPNavigationRouteStep(distanceMeters: step.distance, coordinates: values)
      }
      let scenario = PiPNavigationScenario(
        id: "real-\(UUID().uuidString)",
        title: destination.name,
        detail: destination.address,
        source: coordinate,
        destination: destination.coordinate
      )
      return PiPNavigationPreparedRoute(
        scenario: scenario,
        source: source,
        coordinates: coordinates,
        steps: steps,
        expectedTravelTime: mkRoute.expectedTravelTime
      )
    } onCancel: {
      directions.cancel()
    }
  }

  private func handleNavigatingLocation(
    _ location: CLLocation,
    evaluatesNavigationDecisions: Bool = true
  ) {
    guard let route, let source = mapSource, let parkingStop = activeParkingStop else { return }
    let match = PiPRealNavigationRouteMatcher.match(coordinate: location.coordinate, route: route)
    debug.distanceFromRouteMeters = match.distanceFromRouteMeters
    debug.mapCoverage =
      source.contains([location.coordinate])
      ? "目前位置在預擷取範圍內" : "目前位置超出預擷取範圍"

    let destinationDistance = location.distance(
      from: CLLocation(
        latitude: parkingStop.coordinate.latitude,
        longitude: parkingStop.coordinate.longitude
      ))
    let routeRemaining = max(0, route.routeDistanceMeters - match.distanceAlongRouteMeters)
    let speedKmh = max(location.speed, 0) * 3.6
    let heading = location.course >= 0 ? location.course : match.routeHeadingDegrees
    let sample = PiPNavigationSample(
      distanceMeters: match.distanceAlongRouteMeters,
      coordinate: location.coordinate,
      imagePoint: source.imagePoint(for: location.coordinate),
      headingDegrees: heading,
      progress: route.routeDistanceMeters > 0
        ? match.distanceAlongRouteMeters / route.routeDistanceMeters : 1
    )
    let uptime = ProcessInfo.processInfo.systemUptime
    let observation = PiPRealMotionObservation(
      sample: sample,
      speedMetersPerSecond: max(location.speed, 0),
      hasMeasuredCourse: location.course >= 0,
      observedAtUptime: uptime + min(location.timestamp.timeIntervalSinceNow, 0)
    )
    let nextTurnDistance = nextTurnDistance(route: route, traveled: match.distanceAlongRouteMeters)
    let input = PiPDynamicCameraInput(
      speedKmh: speedKmh,
      roadEnvironment: speedKmh >= 80 ? .highway : .city,
      nextTurnDistanceMeters: nextTurnDistance,
      complexManeuverSpanMeters: nil,
      remainingDistanceMeters: min(routeRemaining, destinationDistance),
      isDestinationFocused: destinationDistance
        <= settings.cameraConfiguration.destinationTriggerMeters,
      bearingDegrees: heading
    )
    let upcomingStops = parkingStops.dropFirst(activeParkingIndex + 1).map { stop in
      PiPRealParkingRenderStop(
        name: stop.name,
        kind: stop.kind,
        color: stop.color,
        imagePoint: source.imagePoint(for: stop.coordinate),
        isCurrent: false
      )
    }
    let navigationOverlay = PiPRealNavigationRenderOverlay(
      currentStop: PiPRealParkingRenderStop(
        name: parkingStop.name,
        kind: parkingStop.kind,
        color: parkingStop.color,
        imagePoint: source.imagePoint(for: parkingStop.coordinate),
        isCurrent: true
      ),
      upcomingStops: upcomingStops,
      remainingRouteDistanceMeters: routeRemaining,
      previewRoute: nextRoute
    )
    renderRuntime.update(
      .navigating(
        route: route,
        observation: observation,
        cameraInput: input,
        zoomMode: settings.zoomMode,
        debugTileBoundaries: settings.showsDebugTileBoundaries,
        positionPredictionLimitSeconds: settings.positionPredictionLimitSeconds,
        presentationStartedAt: navigationPresentationStartedAt ?? uptime,
        routeOverviewDurationSeconds: activeOverviewDurationSeconds,
        routeOverviewTransitionSeconds: activeOverviewTransitionSeconds,
        presentationPrompt: activeOverviewPrompt,
        navigationOverlay: navigationOverlay
      ))

    debug.routeDistanceMeters = routeRemaining
    guard evaluatesNavigationDecisions else { return }
    if min(routeRemaining, destinationDistance) <= settings.nextRoutePreviewDistanceMeters,
      activeParkingIndex + 1 < parkingStops.count
    {
      prepareNextParkingRoute()
    }

    let shouldAdvance = parkingAdvanceDetector.observe(
      distanceMeters: destinationDistance,
      speedMetersPerSecond: max(location.speed, 0),
      arrivalRadiusMeters: settings.parkingArrivalRadiusMeters,
      departureDeltaMeters: settings.parkingDepartureDeltaMeters,
      confirmationCount: settings.parkingDepartureConfirmationCount
    )
    if shouldAdvance, nextRoute != nil {
      advanceToNextParkingStop(from: location)
      return
    }

    if match.distanceFromRouteMeters >= settings.offRouteThresholdMeters {
      offRouteCount += 1
    } else {
      offRouteCount = 0
    }
    let cooldownElapsed = Date().timeIntervalSince(lastRerouteAt ?? .distantPast)
    if offRouteCount >= settings.offRouteConfirmationCount,
      cooldownElapsed >= settings.rerouteCooldownSeconds,
      rerouteTask == nil
    {
      lastRerouteAt = Date()
      debug.lastRerouteAt = lastRerouteAt
      prepareNavigation(from: location, isReroute: true)
    }
  }

  private func prepareNextParkingRoute() {
    guard nextRoute == nil, nextRouteTask == nil, let source = mapSource,
      parkingStops.indices.contains(activeParkingIndex + 1),
      let currentStop = activeParkingStop
    else { return }
    if let lastAttempt = nextRouteLastAttemptAt,
      Date().timeIntervalSince(lastAttempt) < 20
    {
      return
    }

    let expectedIndex = activeParkingIndex
    let nextStop = parkingStops[expectedIndex + 1]
    nextRouteLastAttemptAt = Date()
    debug.nextRouteStatus = "正在預載：\(nextStop.name)"
    nextRouteTask = Task { [weak self] in
      guard let self else { return }
      do {
        let prepared = try await calculateRoute(
          from: currentStop.coordinate,
          to: nextStop.destination,
          source: source
        )
        try Task.checkCancellation()
        guard activeParkingIndex == expectedIndex else {
          nextRouteTask = nil
          return
        }
        nextRoute = prepared
        nextRouteTask = nil
        debug.nextRouteStatus = "已預載：\(nextStop.name)"
        lastError = nil
        statusMessage = "接近目前停車點；下一條路線已用淡色顯示。"
        refreshRenderPayload()
      } catch is CancellationError {
        nextRouteTask = nil
      } catch {
        nextRouteTask = nil
        debug.nextRouteStatus = "預載失敗：\(error.localizedDescription)"
        lastError = "下一停車點路線暫時無法預載，稍後會重試：\(error.localizedDescription)"
      }
    }
  }

  private func advanceToNextParkingStop(from location: CLLocation) {
    guard let prepared = nextRoute, parkingStops.indices.contains(activeParkingIndex + 1) else {
      return
    }
    activeParkingIndex += 1
    route = prepared
    nextRoute = nil
    nextRouteLastAttemptAt = nil
    nextRouteTask?.cancel()
    nextRouteTask = nil
    parkingAdvanceDetector.reset()
    offRouteCount = 0
    cameraRuntime.reset()
    motionRuntime.reset()
    navigationPresentationStartedAt = ProcessInfo.processInfo.systemUptime - 1
    activeOverviewDurationSeconds = 0
    activeOverviewTransitionSeconds = 0.01
    activeOverviewPrompt = ""
    let stop = parkingStops[activeParkingIndex]
    debug.activeParkingStop = stop.name
    debug.nextRouteStatus =
      activeParkingIndex + 1 < parkingStops.count ? "等待接近目前停車點" : "沒有下一個停車點"
    debug.routeStatus = "已離開前一停車點，預載路線已接手"
    statusMessage = "已明顯離開前一停車點，改為導航至 \(stop.name)。"
    handleNavigatingLocation(location)
  }

  private func nextTurnDistance(
    route: PiPNavigationPreparedRoute,
    traveled: CLLocationDistance
  ) -> CLLocationDistance? {
    var cumulative: CLLocationDistance = 0
    for step in route.steps {
      cumulative += step.distanceMeters
      if cumulative > traveled + 5 { return cumulative - traveled }
    }
    return nil
  }

  private func refreshRenderPayload() {
    guard state == .navigating, let location = locationService.currentLocation else { return }
    handleNavigatingLocation(location, evaluatesNavigationDecisions: false)
  }

  private func configureOutput(size: CGSize, framesPerSecond: Int) {
    guard let manager else { return }
    stopRenderTimer()
    let provider: PiPBenchmarkPixelBufferProvider
    do {
      provider = try PiPBenchmarkPixelBufferProvider(size: size, usesPool: true)
    } catch {
      fail(error.localizedDescription)
      return
    }
    let factory = PiPBenchmarkSampleBufferFactory(
      targetFPS: framesPerSecond, cachesFormatDescription: true)
    var configuration = PiPConfiguration.standard
    configuration.width = Int(size.width)
    configuration.height = Int(size.height)
    configuration.contentMode = .simpleGraphic
    manager.prepareExternal(configuration: configuration)

    let runID = UUID()
    activeRunID = runID
    renderFrameCount = 0
    renderFPSStartedAt = ProcessInfo.processInfo.systemUptime
    let timer = DispatchSource.makeTimerSource(queue: renderQueue)
    timer.schedule(
      deadline: .now(),
      repeating: 1 / Double(framesPerSecond),
      leeway: .milliseconds(framesPerSecond <= 2 ? 50 : 2)
    )
    timer.setEventHandler { [weak self] in
      guard let self, self.activeRunID == runID else { return }
      do {
        let frame: PiPNavigationRenderedFrame
        var cameraDebug: PiPDynamicCameraState?
        var vehicleWorldHeadingDebug: CLLocationDirection?
        var mapBearingDebug: CLLocationDirection?
        var vehicleScreenRotationDebug: CLLocationDirection?
        switch self.renderRuntime.snapshot() {
        case .standby(let distance):
          frame = try PiPRealNavigationRenderer.renderStandby(
            distanceMeters: distance,
            provider: provider,
            outputSize: size
          )
        case .navigating(
          let route,
          let observation,
          let input,
          let zoomMode,
          let boundaries,
          let predictionLimit,
          let presentationStartedAt,
          let overviewDuration,
          let transitionDuration,
          let presentationPrompt,
          let navigationOverlay
        ):
          let now = ProcessInfo.processInfo.systemUptime
          let sample = self.motionRuntime.sample(
            for: observation,
            sourceMetersPerPixel: route.sourceMetersPerPixel,
            predictionLimitSeconds: predictionLimit,
            at: now
          )
          let camera = self.cameraRuntime.update(
            input: input,
            outputSize: size,
            zoomMode: zoomMode,
            at: now
          )
          let presentation = PiPRealRoutePresentationTimeline.presentation(
            startedAt: presentationStartedAt,
            overviewDuration: overviewDuration,
            transitionDuration: transitionDuration,
            at: now
          )
          let vehicleWorldHeading = self.headingRuntime.snapshot()
          let mapBearing = PiPDynamicNavigationRenderer.presentationMapBearing(
            cameraBearing: camera.bearingDegrees,
            progress: presentation.overviewToNavigationProgress
          )
          vehicleWorldHeadingDebug = vehicleWorldHeading ?? sample.headingDegrees
          mapBearingDebug = mapBearing
          vehicleScreenRotationDebug =
            PiPDynamicNavigationRenderer.resolvedVehicleRotationDegrees(
              vehicleWorldHeading: vehicleWorldHeading,
              sampleHeading: sample.headingDegrees,
              mapBearing: mapBearing
            )
          cameraDebug = camera
          frame = try PiPDynamicNavigationRenderer.render(
            route: route,
            sample: sample,
            camera: camera,
            provider: provider,
            outputSize: size,
            debugTileBoundaries: boundaries,
            presentation: presentation,
            vehicleWorldHeadingDegrees: vehicleWorldHeading,
            presentationPrompt: presentationPrompt,
            navigationOverlay: navigationOverlay
          )
        }
        let sampleBuffer = try factory.makeSampleBuffer(from: frame.pixelBuffer)
        guard self.submissionSlot.wait(timeout: .now()) == .success else { return }
        DispatchQueue.main.async { [weak self] in
          guard let self else { return }
          defer { self.submissionSlot.signal() }
          guard self.activeRunID == runID else { return }
          _ = self.manager?.submitExternalFrame(sampleBuffer)
          self.renderFrameCount += 1
          let elapsed = ProcessInfo.processInfo.systemUptime - self.renderFPSStartedAt
          if elapsed >= 1 {
            self.debug.renderFPS = Double(self.renderFrameCount) / elapsed
            self.renderFrameCount = 0
            self.renderFPSStartedAt = ProcessInfo.processInfo.systemUptime
          }
          if let cameraDebug {
            self.debug.cameraMode = cameraDebug.mode.rawValue
            self.debug.cameraLookAheadMeters = cameraDebug.currentLookAheadMeters
            self.debug.cameraPitchDegrees = cameraDebug.pitchDegrees
            self.debug.cameraBearingDegrees = mapBearingDebug
            self.debug.vehicleWorldHeadingDegrees = vehicleWorldHeadingDebug
            self.debug.vehicleScreenRotationDegrees = vehicleScreenRotationDebug
          }
        }
      } catch {
        DispatchQueue.main.async { [weak self] in
          self?.lastError = "畫面渲染失敗：\(error.localizedDescription)"
        }
      }
    }
    renderTimer = timer
    timer.resume()
  }

  private func updateDebug(location: CLLocation) {
    debug.latitude = location.coordinate.latitude
    debug.longitude = location.coordinate.longitude
    debug.horizontalAccuracy = location.horizontalAccuracy
    debug.speedKmh = max(location.speed, 0) * 3.6
    debug.course = location.course >= 0 ? location.course : nil
    debug.locationTimestamp = location.timestamp
  }

  private func stopRenderTimer() {
    activeRunID = nil
    renderTimer?.setEventHandler {}
    renderTimer?.cancel()
    renderTimer = nil
  }

  private func cleanupResources(cleanupPiP: Bool) {
    preparationTask?.cancel()
    preparationTask = nil
    rerouteTask?.cancel()
    rerouteTask = nil
    nextRouteTask?.cancel()
    nextRouteTask = nil
    pipStartTask?.cancel()
    pipStartTask = nil
    stopRenderTimer()
    locationService.stop()
    route = nil
    nextRoute = nil
    nextRouteLastAttemptAt = nil
    mapSource = nil
    navigationPresentationStartedAt = nil
    motionRuntime.reset()
    headingRuntime.update(nil)
    usesCourseForVehicleHeading = false
    parkingAdvanceDetector.reset()
    if cleanupPiP { manager?.cleanup() }
  }

  private func fail(_ message: String) {
    guard state != .failed else {
      lastError = message
      return
    }
    isEnding = true
    cleanupResources(cleanupPiP: true)
    state = .failed
    lastError = message
    statusMessage = message
    isEnding = false
  }
}
