import CoreGraphics
import Foundation

struct PiPDynamicCameraController {
  private(set) var configuration: PiPDynamicCameraConfiguration
  private var currentMode: PiPDynamicCameraMode?
  private var currentLookAheadMeters: Double?
  private var acceptedTargetMeters: Double?
  private var smoothedBearingDegrees: Double?
  private var lastUpdateTime: TimeInterval?
  private var lastModeChangeTime: TimeInterval?

  init(configuration: PiPDynamicCameraConfiguration = .init()) {
    self.configuration = configuration
  }

  mutating func updateConfiguration(_ configuration: PiPDynamicCameraConfiguration) {
    self.configuration = configuration
  }

  mutating func reset() {
    currentMode = nil
    currentLookAheadMeters = nil
    acceptedTargetMeters = nil
    smoothedBearingDegrees = nil
    lastUpdateTime = nil
    lastModeChangeTime = nil
  }

  mutating func update(
    input: PiPDynamicCameraInput,
    outputSize: CGSize,
    zoomMode: PiPDynamicZoomMode,
    at time: TimeInterval
  ) -> PiPDynamicCameraState {
    let decision = decision(for: input, zoomMode: zoomMode)
    let deltaTime = max(0, min(0.25, time - (lastUpdateTime ?? time)))
    let previousMode = currentMode
    let heldDuration = time - (lastModeChangeTime ?? -.infinity)
    let previousTarget = acceptedTargetMeters ?? decision.targetMeters
    let targetDifference = abs(decision.targetMeters - previousTarget) / max(previousTarget, 1)
    let isHigherPriority = decision.mode.priority > (previousMode?.priority ?? -1)
    let mayChangeState =
      previousMode == nil || decision.mode == previousMode
      || isHigherPriority || heldDuration >= configuration.minimumStateDuration
    let bypassesHysteresis =
      decision.mode.priority >= PiPDynamicCameraMode.turnApproach.priority
      && decision.mode != previousMode

    if mayChangeState
      && (acceptedTargetMeters == nil || targetDifference >= configuration.hysteresisRatio
        || bypassesHysteresis)
    {
      acceptedTargetMeters = decision.targetMeters
    }
    if mayChangeState, decision.mode != previousMode {
      currentMode = decision.mode
      lastModeChangeTime = time
    }

    let target = acceptedTargetMeters ?? decision.targetMeters
    if currentLookAheadMeters == nil {
      currentLookAheadMeters = target
    } else if deltaTime > 0 {
      let timeConstant = max(configuration.responseDuration / 3, 0.05)
      let alpha = 1 - exp(-deltaTime / timeConstant)
      currentLookAheadMeters! += (target - currentLookAheadMeters!) * alpha
    }

    if smoothedBearingDegrees == nil {
      smoothedBearingDegrees = input.bearingDegrees
    } else if deltaTime > 0 {
      let alpha = 1 - exp(-deltaTime / 0.18)
      let delta = Self.shortestAngle(
        from: smoothedBearingDegrees!,
        to: input.bearingDegrees
      )
      smoothedBearingDegrees = Self.normalized(smoothedBearingDegrees! + delta * alpha)
    }

    lastUpdateTime = time
    let lookAhead = currentLookAheadMeters ?? target
    let forwardPoints = max(outputSize.height * PiPNavigationRenderer.vehiclePoint.y, 1)
    return PiPDynamicCameraState(
      mode: currentMode ?? decision.mode,
      bearingDegrees: smoothedBearingDegrees ?? input.bearingDegrees,
      metersPerPoint: CGFloat(lookAhead) / forwardPoints,
      currentLookAheadMeters: lookAhead,
      targetLookAheadMeters: target,
      pitchDegrees: min(max(configuration.pitchDegrees, 0), 60)
    )
  }

  private func decision(
    for input: PiPDynamicCameraInput,
    zoomMode: PiPDynamicZoomMode
  ) -> (mode: PiPDynamicCameraMode, targetMeters: Double) {
    if zoomMode == .fixed {
      return (.fixed, configuration.fixedLookAheadMeters)
    }

    if input.remainingDistanceMeters <= 8 {
      return (.arrived, 120)
    }
    if input.isDestinationFocused
      || input.remainingDistanceMeters <= configuration.destinationTriggerMeters
    {
      return (
        .destinationApproach,
        Self.clamp(input.remainingDistanceMeters * 1.15 + 70, minimum: 100, maximum: 400)
      )
    }
    if let span = input.complexManeuverSpanMeters {
      return (
        .complexManeuver,
        Self.clamp(span + 180, minimum: 350, maximum: 1_400)
      )
    }

    let speedMps = max(0, input.speedKmh / 3.6)
    if let nextTurn = input.nextTurnDistanceMeters,
      nextTurn / max(speedMps, 1) <= configuration.turnTriggerSeconds
        || nextTurn <= 350
    {
      let routeContext = nextTurn + 160
      return (
        .turnApproach,
        Self.clamp(
          routeContext,
          minimum: configuration.turnMinimumLookAheadMeters,
          maximum: 650
        )
      )
    }

    let rawCruise =
      speedMps * configuration.lookAheadSeconds
      + configuration.safetyDistanceMeters
    switch input.roadEnvironment {
    case .city:
      return (
        .cruise,
        Self.clamp(
          rawCruise,
          minimum: configuration.cityMinimumLookAheadMeters,
          maximum: 900
        )
      )
    case .highway:
      return (.highway, Self.clamp(rawCruise * 1.25, minimum: 1_200, maximum: 3_500))
    }
  }

  private static func clamp(_ value: Double, minimum: Double, maximum: Double) -> Double {
    min(max(value, minimum), maximum)
  }

  private static func shortestAngle(from start: Double, to end: Double) -> Double {
    (end - start + 540).truncatingRemainder(dividingBy: 360) - 180
  }

  private static func normalized(_ value: Double) -> Double {
    (value + 360).truncatingRemainder(dividingBy: 360)
  }
}

final class PiPDynamicCameraRuntime: @unchecked Sendable {
  private let lock = NSLock()
  private var controller = PiPDynamicCameraController()

  func updateConfiguration(_ configuration: PiPDynamicCameraConfiguration) {
    lock.withLock { controller.updateConfiguration(configuration) }
  }

  func reset() {
    lock.withLock { controller.reset() }
  }

  func update(
    input: PiPDynamicCameraInput,
    outputSize: CGSize,
    zoomMode: PiPDynamicZoomMode,
    at time: TimeInterval
  ) -> PiPDynamicCameraState {
    lock.withLock {
      controller.update(input: input, outputSize: outputSize, zoomMode: zoomMode, at: time)
    }
  }
}
