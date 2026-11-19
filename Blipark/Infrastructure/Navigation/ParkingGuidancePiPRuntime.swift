import AVFoundation
import Combine
import Foundation

@MainActor
final class ParkingGuidancePiPRuntime: ObservableObject {
  enum RuntimeError: LocalizedError {
    case unsupported
    case noCandidates
    case failed(String)

    var errorDescription: String? {
      switch self {
      case .unsupported:
        "此裝置不支援系統子母畫面。請使用實體 iPhone，並確認系統已開啟『自動開始子母畫面』。"
      case .noCandidates:
        "這個計畫沒有可供引導的停車候選。"
      case .failed(let message):
        message
      }
    }
  }

  @Published private(set) var statusMessage = "PiP 尚未啟動"
  @Published private(set) var diagnosticMessage = "尚未準備 PiP preview"
  @Published private(set) var isActive = false
  @Published private(set) var previewAspectRatio: CGFloat = 8

  var previewDisplayLayer: AVSampleBufferDisplayLayer {
    manager.contentSource.displayLayer
  }

  private let manager = PiPManager()
  private let coordinator = PiPRealNavigationCoordinator()
  private var observers = Set<AnyCancellable>()
  private var launchObservers = Set<AnyCancellable>()
  private var launchContinuation: CheckedContinuation<Void, Error>?

  init() {
    coordinator.attach(manager: manager)
    coordinator.$statusMessage
      .sink { [weak self] message in self?.statusMessage = message }
      .store(in: &observers)
    manager.$isActive
      .removeDuplicates()
      .sink { [weak self] active in self?.isActive = active }
      .store(in: &observers)
    manager.$diagnosticMessage
      .removeDuplicates()
      .sink { [weak self] message in self?.diagnosticMessage = message }
      .store(in: &observers)
    manager.$configuration
      .map(\.aspectRatio)
      .removeDuplicates()
      .sink { [weak self] ratio in self?.previewAspectRatio = ratio }
      .store(in: &observers)
  }

  func start(
    session: ParkingGuidanceSession,
    settings: DeveloperNavigationSettings,
    triggerDistanceMeters: Double
  ) async throws {
    guard !session.orderedCandidates.dropFirst(session.currentCandidateIndex).isEmpty else {
      throw RuntimeError.noCandidates
    }
    guard manager.status != .unsupported else { throw RuntimeError.unsupported }

    try await stopExistingSession()
    coordinator.reset()
    coordinator.attach(manager: manager)
    apply(settings, triggerDistanceMeters: triggerDistanceMeters)

    let payload = ParkingGuidancePiPAdapter.payload(for: session)
    try await withTaskCancellationHandler {
      try await withCheckedThrowingContinuation { continuation in
        launchContinuation = continuation
        observeLaunchResult()
        coordinator.start(
          finalDestination: payload.destination,
          parkingStops: payload.parkingStops
        )
      }
    } onCancel: {
      Task { @MainActor [weak self] in self?.cancelPendingLaunch() }
    }
  }

  func stop() {
    cancelPendingLaunch()
    launchObservers.removeAll()
    if coordinator.isSessionRunning {
      coordinator.endSession(message: "停車引導已結束。")
    } else {
      manager.stop()
    }
    isActive = false
  }

  func resume(
    session: ParkingGuidanceSession,
    settings: DeveloperNavigationSettings,
    triggerDistanceMeters: Double
  ) async throws {
    guard manager.status != .unsupported else { throw RuntimeError.unsupported }
    if manager.isActive { return }

    guard coordinator.isSessionRunning else {
      try await start(
        session: session,
        settings: settings,
        triggerDistanceMeters: triggerDistanceMeters
      )
      return
    }

    try await withTaskCancellationHandler {
      try await withCheckedThrowingContinuation { continuation in
        launchContinuation = continuation
        observeLaunchResult()
        manager.refreshReadiness()
        Task { @MainActor [weak self] in
          await self?.requestPiPResumeWhenReady()
        }
      }
    } onCancel: {
      Task { @MainActor [weak self] in self?.cancelPendingLaunch() }
    }
  }

  private func apply(
    _ settings: DeveloperNavigationSettings,
    triggerDistanceMeters: Double
  ) {
    coordinator.setTriggerDistance(triggerDistanceMeters)
    coordinator.setRenderMode(settings.renderMode == .tileGrid ? .tileGrid : .singleSnapshot)
    coordinator.setTileGrid(gridPreset(for: settings.tileGridSize))
    coordinator.setZoomMode(settings.zoomMode == .dynamic ? .dynamic : .fixed)
    coordinator.setFixedLookAhead(settings.fixedLookAheadMeters)
    coordinator.setLocationDistanceFilter(settings.locationDistanceFilterMeters)
    coordinator.setPositionPredictionLimit(settings.positionPredictionLimitSeconds)
    coordinator.setMaximumAccuracy(settings.maximumHorizontalAccuracyMeters)
    coordinator.setOffRouteThreshold(settings.offRouteThresholdMeters)
    coordinator.setNextRoutePreviewDistance(settings.nextRoutePreviewDistanceMeters)
    coordinator.setCameraPitch(settings.pitchDegrees)
    coordinator.setDebugTileBoundaries(settings.showsTileBoundaries)
    manager.setExperimentalControlsStyle(
      PiPManager.ExperimentalControlsStyle(rawValue: settings.pipControlsStyle) ?? .systemDefault
    )
  }

  private func stopExistingSession() async throws {
    let wasActive = manager.isActive
    stop()
    guard wasActive else { return }

    for _ in 0..<20 {
      if !manager.isActive { return }
      try await Task.sleep(for: .milliseconds(100))
    }
    throw RuntimeError.failed("前一次 PiP 尚未完全關閉，請稍候再開始新的行程。")
  }

  private func gridPreset(for size: Int) -> PiPTileNavigationGridPreset {
    PiPTileNavigationGridPreset(rawValue: size) ?? .five
  }

  private func observeLaunchResult() {
    launchObservers.removeAll()
    manager.$isActive
      .filter { $0 }
      .prefix(1)
      .sink { [weak self] _ in self?.finishLaunch() }
      .store(in: &launchObservers)

    coordinator.$state
      .filter { $0 == .failed }
      .prefix(1)
      .sink { [weak self] _ in
        guard let self else { return }
        failLaunch(coordinator.lastError ?? "PiP 啟動失敗。")
      }
      .store(in: &launchObservers)
  }

  private func requestPiPResumeWhenReady() async {
    for _ in 0..<24 {
      guard launchContinuation != nil else { return }
      if manager.isActive {
        finishLaunch()
        return
      }
      if manager.isPreviewReady, manager.isPossible {
        manager.startFromUserAction()
        statusMessage = "已要求重新啟動 PiP，等待系統確認。"
        return
      }
      try? await Task.sleep(for: .milliseconds(250))
    }
    failLaunch("PiP 尚未恢復可啟動狀態，請確認沒有其他 App 正在使用 PiP 後再試。")
  }

  private func finishLaunch() {
    guard let continuation = launchContinuation else { return }
    launchContinuation = nil
    launchObservers.removeAll()
    continuation.resume()
  }

  private func failLaunch(_ message: String) {
    guard let continuation = launchContinuation else { return }
    launchContinuation = nil
    launchObservers.removeAll()
    let diagnostic = manager.lastError ?? manager.diagnosticMessage
    let details = diagnostic.isEmpty || message.contains(diagnostic)
      ? message : "\(message)\n\(diagnostic)"
    continuation.resume(throwing: RuntimeError.failed(details))
  }

  private func cancelPendingLaunch() {
    guard let continuation = launchContinuation else { return }
    launchContinuation = nil
    launchObservers.removeAll()
    continuation.resume(throwing: CancellationError())
  }
}
