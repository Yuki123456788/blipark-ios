import AVFoundation
import AVKit
import Combine
import CoreMedia

private final class PiPAudioSessionController: @unchecked Sendable {
  private let queue = DispatchQueue(
    label: "com.blipark.iOSOverlayLab.audio-session",
    qos: .userInitiated
  )
  private var isActive = false

  func activate() async throws {
    try await withCheckedThrowingContinuation { continuation in
      queue.async { [self] in
        do {
          let session = AVAudioSession.sharedInstance()
          try session.setCategory(.playback, mode: .moviePlayback, options: [.mixWithOthers])
          if !isActive {
            try session.setActive(true)
            isActive = true
          }
          continuation.resume()
        } catch {
          continuation.resume(throwing: error)
        }
      }
    }
  }

  func deactivate(completion: @escaping @Sendable (Error?) -> Void) {
    queue.async { [self] in
      guard isActive else {
        completion(nil)
        return
      }
      do {
        try AVAudioSession.sharedInstance().setActive(
          false,
          options: [.notifyOthersOnDeactivation]
        )
        isActive = false
        completion(nil)
      } catch {
        completion(error)
      }
    }
  }
}

@MainActor
final class PiPManager: NSObject, ObservableObject {
  enum ExperimentalControlsStyle: Int, CaseIterable, Identifiable {
    case systemDefault = 0
    case hidePlaybackControls = 1
    case hideAllControls = 2

    var id: Int { rawValue }

    var title: String {
      switch self {
      case .systemDefault: "0・系統預設"
      case .hidePlaybackControls: "1・隱藏播放"
      case .hideAllControls: "2・全部隱藏"
      }
    }
  }

  enum Status: String {
    case unsupported = "裝置不支援 PiP"
    case preparing = "準備中"
    case waiting = "等待系統允許 PiP"
    case ready = "可啟動 PiP"
    case starting = "啟動中"
    case active = "PiP 顯示中"
    case stopping = "停止中"
    case stopped = "已停止"
    case failed = "啟動失敗"
  }

  @Published private(set) var status: Status = .preparing
  @Published private(set) var isPossible = false
  @Published private(set) var isActive = false
  @Published private(set) var isPlaying = true
  @Published private(set) var isPreviewReady = false
  @Published private(set) var configuration = PiPConfiguration.standard
  @Published private(set) var lastError: String?
  @Published private(set) var lastSystemRenderSize = "尚未回報"
  @Published private(set) var diagnosticMessage = "尚未準備"
  @Published private(set) var experimentalControlsStyle: ExperimentalControlsStyle = .systemDefault
  @Published private(set) var experimentalControlsStatus = "系統預設控制"

  let contentSource = PiPContentSource()
  var eventSink: ((String) -> Void)?

  private var controller: AVPictureInPictureController?
  private var possibleObservation: NSKeyValueObservation?
  private var automationTask: Task<Void, Never>?
  private var readinessProbeTask: Task<Void, Never>?
  private var audioActivationTask: Task<Void, Never>?
  private let audioSessionController = PiPAudioSessionController()
  private var isContentPrepared = false

  override init() {
    super.init()
    if !AVPictureInPictureController.isPictureInPictureSupported() {
      status = .unsupported
      diagnosticMessage = "此裝置或目前系統環境不支援 Picture in Picture"
    }
  }

  func prepare(configuration: PiPConfiguration, automaticFromInline: Bool = false) {
    self.configuration = configuration
    contentSource.start(configuration: configuration)
    isContentPrepared = true
    finishPreparation(configuration: configuration, automaticFromInline: automaticFromInline)
  }

  func prepareExternal(configuration: PiPConfiguration) {
    self.configuration = configuration
    contentSource.startExternal(configuration: configuration)
    isContentPrepared = true
    finishPreparation(configuration: configuration, automaticFromInline: false)
  }

  @discardableResult
  func submitExternalFrame(_ sampleBuffer: CMSampleBuffer) -> Bool {
    contentSource.enqueueExternal(sampleBuffer)
  }

  private func finishPreparation(
    configuration: PiPConfiguration,
    automaticFromInline: Bool
  ) {

    guard AVPictureInPictureController.isPictureInPictureSupported() else {
      status = .unsupported
      lastError = nil
      diagnosticMessage = "此環境不支援系統 PiP；App 內 preview 仍會持續渲染"
      probePreviewWithoutPiP()
      emit("此環境不支援系統 PiP；僅驗證 App 內 preview")
      return
    }

    status = .preparing
    lastError = nil
    diagnosticMessage = "正在設定 Audio Session 與第一個 frame"

    audioActivationTask?.cancel()
    audioActivationTask = Task { [weak self] in
      guard let self else { return }
      do {
        try await audioSessionController.activate()
        try Task.checkCancellation()
        completePreparation(
          configuration: configuration,
          automaticFromInline: automaticFromInline
        )
      } catch is CancellationError {
        return
      } catch {
        fail("Audio Session 準備失敗：\(error.localizedDescription)")
      }
    }
  }

  private func completePreparation(
    configuration: PiPConfiguration,
    automaticFromInline: Bool
  ) {
    audioActivationTask = nil
    guard isContentPrepared else { return }

    if controller == nil {
      let source = AVPictureInPictureController.ContentSource(
        sampleBufferDisplayLayer: contentSource.displayLayer,
        playbackDelegate: self
      )
      let controller = AVPictureInPictureController(contentSource: source)
      controller.delegate = self
      self.controller = controller
      possibleObservation = controller.observe(
        \.isPictureInPicturePossible,
        options: [.initial, .new]
      ) { [weak self] _, change in
        Task { @MainActor [weak self] in
          guard let self else { return }
          isPossible = change.newValue ?? false
          if isContentPrepared, isPossible, !isActive {
            status = .ready
            diagnosticMessage = "預覽與系統 PiP controller 均已就緒"
          }
        }
      }
    }

    if let controller {
      configureLiveLinearPlayback(for: controller)
      applyExperimentalControlsStyle(to: controller)
    }
    controller?.canStartPictureInPictureAutomaticallyFromInline = automaticFromInline
    synchronizeControllerState()
    probeReadiness()
    emit(
      "PiP 內容已準備：\(configuration.resolutionText)，比例 "
        + String(format: "%.2f:1", configuration.aspectRatio)
    )
  }

  func startFromUserAction() {
    guard let controller else {
      fail("PiP 尚未準備，請等待預覽載入")
      return
    }
    guard isPossible else {
      fail("系統目前尚未允許啟動 PiP；請確認預覽可見並稍候再試")
      return
    }

    configureLiveLinearPlayback(for: controller)
    applyExperimentalControlsStyle(to: controller)
    readinessProbeTask?.cancel()
    readinessProbeTask = nil
    status = .starting
    diagnosticMessage = "已向系統送出 PiP 啟動要求"
    emit("使用者按下啟動系統 PiP")
    controller.startPictureInPicture()
  }

  private func configureLiveLinearPlayback(for controller: AVPictureInPictureController) {
    // Navigation is a continuously produced live feed, not seekable media.
    // Reapply this policy because the controller is reused across test sessions.
    controller.requiresLinearPlayback = true
    controller.invalidatePlaybackState()
  }

  func setExperimentalControlsStyle(_ style: ExperimentalControlsStyle) {
    experimentalControlsStyle = style
    guard let controller else {
      experimentalControlsStatus =
        style == .systemDefault ? "系統預設控制" : "等待 PiP Controller 建立後套用"
      return
    }
    applyExperimentalControlsStyle(to: controller)
  }

  private func applyExperimentalControlsStyle(to controller: AVPictureInPictureController) {
    let setter = NSSelectorFromString("setControlsStyle:")
    guard controller.responds(to: setter) else {
      experimentalControlsStatus =
        experimentalControlsStyle == .systemDefault
        ? "系統預設控制" : "此 iOS 未提供內部 controlsStyle setter"
      if experimentalControlsStyle != .systemDefault {
        emit("實驗性 PiP 控制樣式無法套用：目前系統沒有 controlsStyle setter")
      }
      return
    }

    // `controlsStyle` is an undocumented AVPictureInPictureController property.
    // Community-observed values: 0 = default, 1 = hide transport, 2 = hide all.
    controller.setValue(experimentalControlsStyle.rawValue, forKey: "controlsStyle")
    controller.invalidatePlaybackState()
    switch experimentalControlsStyle {
    case .systemDefault:
      experimentalControlsStatus = "系統預設控制"
      emit("已恢復系統預設 PiP 控制")
    case .hidePlaybackControls:
      experimentalControlsStatus = "已套用私有 controlsStyle = 1"
      emit("已套用實驗性精簡 PiP 播放控制")
    case .hideAllControls:
      experimentalControlsStatus = "已套用私有 controlsStyle = 2"
      emit("已套用實驗性隱藏全部 PiP 控制")
    }
  }

  func stop() {
    cancelAutomation()
    guard let controller, controller.isPictureInPictureActive else {
      status = .stopped
      emit("PiP 未在顯示；已停止自動更新")
      return
    }
    status = .stopping
    emit("要求系統停止 PiP")
    controller.stopPictureInPicture()
  }

  func cleanup() {
    cancelAutomation()
    readinessProbeTask?.cancel()
    readinessProbeTask = nil
    audioActivationTask?.cancel()
    audioActivationTask = nil
    isContentPrepared = false
    controller?.canStartPictureInPictureAutomaticallyFromInline = false
    let controllerWasActive = controller?.isPictureInPictureActive == true
    if controllerWasActive {
      status = .stopping
      controller?.stopPictureInPicture()
    }
    contentSource.stop()
    // Keep these values aligned with the reusable system controller. In
    // particular, do not force isPossible to false: that property may remain
    // true and therefore produce no new KVO event during the next prepare.
    isPossible = controller?.isPictureInPicturePossible ?? false
    isActive = controllerWasActive
    isPreviewReady = false
    if controllerWasActive {
      diagnosticMessage = "正在等待系統完成 PiP 停止"
    } else {
      status = .stopped
      diagnosticMessage = "PiP 資源已清理"
    }
    deactivateAudioSession()
    emit("PiP 資源已清理")
  }

  func update(configuration: PiPConfiguration, reason: String) {
    let dimensionsChanged =
      self.configuration.width != configuration.width
      || self.configuration.height != configuration.height
    self.configuration = configuration
    contentSource.update(configuration: configuration, flushFirst: dimensionsChanged)
    controller?.invalidatePlaybackState()
    emit("\(reason)：\(configuration.resolutionText)")
  }

  func runConfigurationSequence(
    _ configurations: [PiPConfiguration],
    interval: TimeInterval,
    reason: String
  ) {
    cancelAutomation()
    emit("開始自動序列；每 \(Int(interval)) 秒更新")
    automationTask = Task { [weak self] in
      guard let self else { return }
      for configuration in configurations {
        guard !Task.isCancelled else { return }
        update(configuration: configuration, reason: reason)
        try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
      }
      emit("自動序列完成")
    }
  }

  func runParkingUpdates(interval: TimeInterval) {
    let values = [(12, 500), (11, 350), (9, 200), (7, 100)]
    let base = configuration
    let sequence = values.map { spaces, distance in
      var item = base
      item.remainingSpaces = spaces
      item.distanceMeters = distance
      return item
    }
    runConfigurationSequence(sequence, interval: interval, reason: "更新停車資訊")
  }

  func advanceNavigation(reason: String = "更新導航資訊") {
    guard var navigation = configuration.navigation else {
      fail("目前 PiP 內容不是導航模式")
      return
    }

    let nextProgress = navigation.progress + 0.1
    navigation.progress = nextProgress > 1 ? 0 : nextProgress
    let maneuverIndex = min(
      ManeuverType.allCases.count - 1,
      Int((navigation.progress * CGFloat(ManeuverType.allCases.count)).rounded(.down))
    )
    let maneuver = ManeuverType.allCases[maneuverIndex]
    navigation.maneuver = maneuver
    navigation.distanceMeters = max(30, Int(350 * (1 - navigation.progress)))
    navigation.instruction = maneuver.sampleInstruction

    var nextConfiguration = configuration
    nextConfiguration.navigation = navigation
    update(configuration: nextConfiguration, reason: reason)
  }

  func runNavigationUpdates(interval: TimeInterval, duration: TimeInterval = 30) {
    cancelAutomation()
    guard configuration.navigation != nil else {
      fail("請先準備導航 PiP 內容")
      return
    }

    emit(
      "開始導航 PiP 更新：每 \(formatInterval(interval)) 更新，共 \(Int(duration)) 秒"
    )
    automationTask = Task { [weak self] in
      guard let self else { return }
      let deadline = Date().addingTimeInterval(duration)
      while !Task.isCancelled, Date() < deadline {
        advanceNavigation(reason: "導航動態更新")
        try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
      }
      if !Task.isCancelled {
        emit("導航 PiP 自動更新完成")
      }
    }
  }

  func cancelAutomation() {
    automationTask?.cancel()
    automationTask = nil
  }

  func refreshReadiness() {
    controller?.invalidatePlaybackState()
    synchronizeControllerState()
    probeReadiness()
  }

  private func deactivateAudioSession() {
    audioSessionController.deactivate { [weak self] error in
      guard let error else { return }
      Task { @MainActor [weak self] in
        self?.emit("Audio Session 結束失敗：\(error.localizedDescription)")
      }
    }
  }

  private func probeReadiness() {
    readinessProbeTask?.cancel()
    readinessProbeTask = Task { [weak self] in
      guard let self else { return }

      for _ in 0..<12 {
        guard !Task.isCancelled else { return }
        try? await Task.sleep(for: .milliseconds(250))
        guard !Task.isCancelled else { return }

        isPreviewReady = contentSource.isRendering
        controller?.invalidatePlaybackState()
        synchronizeControllerState()
        if isPossible {
          if isActive {
            status = .active
            diagnosticMessage = "系統 PiP 視窗顯示中"
          } else {
            status = .ready
            diagnosticMessage = "\(contentSource.readinessDescription)；系統允許啟動 PiP"
          }
          return
        }
        diagnosticMessage = "\(contentSource.readinessDescription)；等待系統 PiP controller"
      }

      status = .waiting
      diagnosticMessage =
        "\(contentSource.readinessDescription)；系統仍未允許 PiP。請確認沒有其他 App 正在使用 PiP，然後按「重新準備」。"
      emit("PiP 準備逾時：\(diagnosticMessage)")
    }
  }

  private func probePreviewWithoutPiP() {
    readinessProbeTask?.cancel()
    readinessProbeTask = Task { [weak self] in
      guard let self else { return }

      for _ in 0..<12 {
        guard !Task.isCancelled else { return }
        try? await Task.sleep(for: .milliseconds(250))
        guard !Task.isCancelled else { return }

        isPreviewReady = contentSource.isRendering
        if isPreviewReady {
          diagnosticMessage = "App 內 preview 已就緒；此環境不支援系統 PiP"
          return
        }
      }

      diagnosticMessage = "App 內 preview 尚未收到 frame；此環境不支援系統 PiP"
    }
  }

  private func synchronizeControllerState() {
    guard let controller else {
      isPossible = false
      isActive = false
      return
    }

    isPossible = controller.isPictureInPicturePossible
    isActive = controller.isPictureInPictureActive
    guard isContentPrepared else { return }

    if isActive {
      status = .active
      diagnosticMessage = "系統 PiP 視窗顯示中"
    } else if isPossible {
      status = .ready
      diagnosticMessage = "預覽與系統 PiP controller 均已就緒"
    }
  }

  private func emit(_ message: String) {
    eventSink?(message)
  }

  private func formatInterval(_ interval: TimeInterval) -> String {
    interval < 1 ? String(format: "%.1f 秒", interval) : "\(Int(interval)) 秒"
  }

  private func fail(_ message: String) {
    lastError = message
    status = .failed
    diagnosticMessage = message
    emit(message)
  }
}

extension PiPManager: @preconcurrency AVPictureInPictureSampleBufferPlaybackDelegate {
  func pictureInPictureController(
    _ pictureInPictureController: AVPictureInPictureController,
    setPlaying playing: Bool
  ) {
    isPlaying = playing
    contentSource.setPlaying(playing)
    pictureInPictureController.invalidatePlaybackState()
    emit(playing ? "使用系統控制繼續播放" : "使用系統控制暫停播放")
  }

  func pictureInPictureControllerTimeRangeForPlayback(
    _ pictureInPictureController: AVPictureInPictureController
  ) -> CMTimeRange {
    // An unbounded range with a positive-infinite duration tells AVKit that
    // this is live content and has no meaningful progress timeline.
    CMTimeRange(start: .negativeInfinity, duration: .positiveInfinity)
  }

  func pictureInPictureControllerIsPlaybackPaused(
    _ pictureInPictureController: AVPictureInPictureController
  ) -> Bool {
    !isPlaying
  }

  func pictureInPictureController(
    _ pictureInPictureController: AVPictureInPictureController,
    didTransitionToRenderSize newRenderSize: CMVideoDimensions
  ) {
    lastSystemRenderSize = "\(newRenderSize.width) × \(newRenderSize.height)"
    emit("系統 PiP render size：\(lastSystemRenderSize)")
  }

  func pictureInPictureController(
    _ pictureInPictureController: AVPictureInPictureController,
    skipByInterval skipInterval: CMTime,
    completion: @escaping () -> Void
  ) {
    completion()
  }

  func pictureInPictureControllerShouldProhibitBackgroundAudioPlayback(
    _ pictureInPictureController: AVPictureInPictureController
  ) -> Bool {
    true
  }
}

extension PiPManager: @preconcurrency AVPictureInPictureControllerDelegate {
  func pictureInPictureControllerWillStartPictureInPicture(
    _ pictureInPictureController: AVPictureInPictureController
  ) {
    status = .starting
    emit("系統即將顯示 PiP")
  }

  func pictureInPictureControllerDidStartPictureInPicture(
    _ pictureInPictureController: AVPictureInPictureController
  ) {
    isActive = true
    status = .active
    diagnosticMessage = "系統 PiP 視窗顯示中"
    emit("系統 PiP 已啟動")
  }

  func pictureInPictureController(
    _ pictureInPictureController: AVPictureInPictureController,
    failedToStartPictureInPictureWithError error: Error
  ) {
    isActive = false
    fail("PiP 啟動失敗：\(error.localizedDescription)")
  }

  func pictureInPictureControllerWillStopPictureInPicture(
    _ pictureInPictureController: AVPictureInPictureController
  ) {
    status = .stopping
    emit("系統即將停止 PiP")
  }

  func pictureInPictureControllerDidStopPictureInPicture(
    _ pictureInPictureController: AVPictureInPictureController
  ) {
    isActive = false
    isPossible = pictureInPictureController.isPictureInPicturePossible
    if isContentPrepared {
      status = isPossible ? .ready : .waiting
      diagnosticMessage = isPossible ? "可再次啟動 PiP" : "PiP 已停止，等待系統重新允許"
    } else {
      status = .stopped
      diagnosticMessage = "PiP 資源已清理，可準備下一次測試"
    }
    emit("系統 PiP 已停止")
  }

  func pictureInPictureController(
    _ pictureInPictureController: AVPictureInPictureController,
    restoreUserInterfaceForPictureInPictureStopWithCompletionHandler completionHandler: @escaping (
      Bool
    ) -> Void
  ) {
    emit("系統要求回到 App 內的 PiP 測試頁")
    completionHandler(true)
  }
}
