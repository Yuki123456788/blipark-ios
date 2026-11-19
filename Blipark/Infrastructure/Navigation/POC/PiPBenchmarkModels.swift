import CoreGraphics
import Foundation
import UIKit

enum PiPBenchmarkFPS: Int, CaseIterable, Identifiable {
  case fps5 = 5
  case fps10 = 10
  case fps15 = 15
  case fps20 = 20
  case fps30 = 30

  var id: Int { rawValue }
  var title: String { "\(rawValue) FPS" }
  var frameInterval: TimeInterval { 1 / Double(rawValue) }
}

enum PiPBenchmarkResolution: String, CaseIterable, Identifiable {
  case full = "1280 × 720"
  case medium = "960 × 540"
  case compact = "854 × 480"
  case low = "640 × 360"

  var id: String { rawValue }

  var size: CGSize {
    switch self {
    case .full: CGSize(width: 1_280, height: 720)
    case .medium: CGSize(width: 960, height: 540)
    case .compact: CGSize(width: 854, height: 480)
    case .low: CGSize(width: 640, height: 360)
    }
  }
}

enum PiPBenchmarkAnimationMode: String, CaseIterable, Identifiable {
  case translation = "只有平移"
  case rotation = "只有旋轉"
  case combined = "平移＋旋轉"
  case navigation = "固定導航視角"

  var id: String { rawValue }
}

enum PiPBenchmarkMotionSpeed: String, CaseIterable, Identifiable {
  case slow = "慢速"
  case normal = "中速"
  case fast = "快速"

  var id: String { rawValue }

  var multiplier: Double {
    switch self {
    case .slow: 0.5
    case .normal: 1
    case .fast: 2
    }
  }

  var rotationDegreesPerSecond: Double {
    switch self {
    case .slow: 15
    case .normal: 45
    case .fast: 90
    }
  }
}

enum PiPBenchmarkRendererKind: String, CaseIterable, Identifiable {
  case legacy = "Legacy（中間 UIImage）"
  case direct = "Direct CGImage"
  case directPool = "Direct ＋ PixelBufferPool"

  var id: String { rawValue }
  var usesPixelBufferPool: Bool { self == .directPool }
  var usesLegacyPipeline: Bool { self == .legacy }
}

struct PiPBenchmarkConfiguration: Equatable {
  let fps: PiPBenchmarkFPS
  let resolution: PiPBenchmarkResolution
  let animationMode: PiPBenchmarkAnimationMode
  let motionSpeed: PiPBenchmarkMotionSpeed
  let renderer: PiPBenchmarkRendererKind
}

struct MapAnimationState: Equatable {
  let translation: CGPoint
  let rotationRadians: CGFloat
  let vehiclePoint: CGPoint
  let showsVehicle: Bool
}

enum MapAnimationSimulator {
  static func state(
    elapsed: TimeInterval,
    mode: PiPBenchmarkAnimationMode,
    speed: PiPBenchmarkMotionSpeed
  ) -> MapAnimationState {
    let time = max(0, elapsed) * speed.multiplier
    let vehicle = CGPoint(x: 0.5, y: 0.72)

    switch mode {
    case .translation:
      return MapAnimationState(
        translation: CGPoint(
          x: 0.14 * sin(time * 0.72),
          y: 0.08 * sin(time * 0.41)
        ),
        rotationRadians: 0,
        vehiclePoint: vehicle,
        showsVehicle: false
      )
    case .rotation:
      let degrees = speed.rotationDegreesPerSecond * max(0, elapsed)
      return MapAnimationState(
        translation: .zero,
        rotationRadians: CGFloat(-degrees * .pi / 180),
        vehiclePoint: vehicle,
        showsVehicle: false
      )
    case .combined:
      let phase = time.truncatingRemainder(dividingBy: 18)
      let moving = min(1, max(0, (15 - phase) / 2))
      return MapAnimationState(
        translation: CGPoint(
          x: moving * 0.12 * sin(time * 0.62),
          y: moving * 0.07 * cos(time * 0.39)
        ),
        rotationRadians: CGFloat(moving * (0.38 * sin(time * 0.47) + 0.16 * sin(time * 1.13))),
        vehiclePoint: vehicle,
        showsVehicle: false
      )
    case .navigation:
      return MapAnimationState(
        translation: CGPoint(
          x: 0.11 * sin(time * 0.52),
          y: 0.09 * cos(time * 0.31)
        ),
        rotationRadians: CGFloat(-(0.48 * sin(time * 0.43) + 0.18 * sin(time * 0.91))),
        vehiclePoint: vehicle,
        showsVehicle: true
      )
    }
  }
}

struct PiPBenchmarkFrameRecord {
  let sequence: Int
  let scheduledUptime: TimeInterval
  let startedUptime: TimeInterval
  let completedUptime: TimeInterval?
  var submittedUptime: TimeInterval?
  let pixelBufferMilliseconds: Double
  let renderMilliseconds: Double
  let sampleBufferMilliseconds: Double
  var submissionMilliseconds: Double
  let schedulingDelayMilliseconds: Double
  let wasInBackground: Bool
  let pipWasActive: Bool
  var dropReason: String?
}

struct PiPBenchmarkMetricsSnapshot: Equatable {
  static let empty = PiPBenchmarkMetricsSnapshot(
    elapsedSeconds: 0,
    targetFPS: 0,
    recentCompletedFPS: 0,
    recentSubmittedFPS: 0,
    completedFrames: 0,
    submittedFrames: 0,
    droppedFrames: 0,
    averageRenderMilliseconds: 0,
    p50RenderMilliseconds: 0,
    p95RenderMilliseconds: 0,
    maximumRenderMilliseconds: 0,
    averagePixelBufferMilliseconds: 0,
    p50PixelBufferMilliseconds: 0,
    p95PixelBufferMilliseconds: 0,
    maximumPixelBufferMilliseconds: 0,
    averageSampleBufferMilliseconds: 0,
    p50SampleBufferMilliseconds: 0,
    p95SampleBufferMilliseconds: 0,
    maximumSampleBufferMilliseconds: 0,
    averageSubmissionMilliseconds: 0,
    p50SubmissionMilliseconds: 0,
    p95SubmissionMilliseconds: 0,
    maximumSubmissionMilliseconds: 0,
    averageSchedulingDelayMilliseconds: 0,
    p50SchedulingDelayMilliseconds: 0,
    p95SchedulingDelayMilliseconds: 0,
    maximumSchedulingDelayMilliseconds: 0,
    backgroundSubmittedFrames: 0
  )

  let elapsedSeconds: TimeInterval
  let targetFPS: Int
  let recentCompletedFPS: Double
  let recentSubmittedFPS: Double
  let completedFrames: Int
  let submittedFrames: Int
  let droppedFrames: Int
  let averageRenderMilliseconds: Double
  let p50RenderMilliseconds: Double
  let p95RenderMilliseconds: Double
  let maximumRenderMilliseconds: Double
  let averagePixelBufferMilliseconds: Double
  let p50PixelBufferMilliseconds: Double
  let p95PixelBufferMilliseconds: Double
  let maximumPixelBufferMilliseconds: Double
  let averageSampleBufferMilliseconds: Double
  let p50SampleBufferMilliseconds: Double
  let p95SampleBufferMilliseconds: Double
  let maximumSampleBufferMilliseconds: Double
  let averageSubmissionMilliseconds: Double
  let p50SubmissionMilliseconds: Double
  let p95SubmissionMilliseconds: Double
  let maximumSubmissionMilliseconds: Double
  let averageSchedulingDelayMilliseconds: Double
  let p50SchedulingDelayMilliseconds: Double
  let p95SchedulingDelayMilliseconds: Double
  let maximumSchedulingDelayMilliseconds: Double
  let backgroundSubmittedFrames: Int
}

struct PiPBenchmarkRunReport: Identifiable {
  let id: UUID
  let startedAt: Date
  let endedAt: Date
  let configuration: PiPBenchmarkConfiguration
  let device: DeviceContext
  let thermalState: String
  let snapshot: PiPBenchmarkMetricsSnapshot
  let records: [PiPBenchmarkFrameRecord]
}

enum PiPBenchmarkCSVExporter {
  static func data(for reports: [PiPBenchmarkRunReport]) -> Data {
    Data(csv(for: reports).utf8)
  }

  static func csv(for reports: [PiPBenchmarkRunReport]) -> String {
    let header = [
      "runId", "startedAt", "endedAt", "environment", "device", "ios", "thermalState",
      "renderer", "animation", "motionSpeed", "targetFps", "resolution",
      "sequence", "scheduledSeconds", "startedSeconds", "completedSeconds",
      "submittedSeconds", "schedulingDelayMs", "pixelBufferMs", "renderMs",
      "sampleBufferMs", "submissionMs", "background", "pipActive", "dropReason",
      "runCompletedFps", "runSubmittedFps", "runDroppedFrames", "runAverageRenderMs",
      "runP50RenderMs", "runP95RenderMs", "runMaxRenderMs", "runAveragePixelBufferMs",
      "runP50PixelBufferMs", "runP95PixelBufferMs", "runMaxPixelBufferMs",
      "runAverageSampleBufferMs", "runP50SampleBufferMs", "runP95SampleBufferMs",
      "runMaxSampleBufferMs", "runAverageSubmissionMs", "runP50SubmissionMs",
      "runP95SubmissionMs", "runMaxSubmissionMs", "runAverageSchedulingDelayMs",
      "runP50SchedulingDelayMs", "runP95SchedulingDelayMs", "runMaxSchedulingDelayMs",
    ]
    let formatter = ISO8601DateFormatter()
    var rows = [header.map(escape).joined(separator: ",")]

    for report in reports {
      let base = [
        report.id.uuidString,
        formatter.string(from: report.startedAt),
        formatter.string(from: report.endedAt),
        report.device.environment,
        report.device.model,
        report.device.systemVersion,
        report.thermalState,
        report.configuration.renderer.rawValue,
        report.configuration.animationMode.rawValue,
        report.configuration.motionSpeed.rawValue,
        "\(report.configuration.fps.rawValue)",
        report.configuration.resolution.rawValue,
      ]
      let records: [PiPBenchmarkFrameRecord?] =
        report.records.isEmpty
        ? [nil] : report.records.map(Optional.some)
      let origin = report.records.first?.scheduledUptime
      for record in records {
        var frame: [String] = []
        frame.append(record.map { "\($0.sequence)" } ?? "")
        frame.append(seconds(record?.scheduledUptime, relativeTo: origin))
        frame.append(seconds(record?.startedUptime, relativeTo: origin))
        frame.append(seconds(record?.completedUptime, relativeTo: origin))
        frame.append(seconds(record?.submittedUptime, relativeTo: origin))
        frame.append(number(record?.schedulingDelayMilliseconds))
        frame.append(number(record?.pixelBufferMilliseconds))
        frame.append(number(record?.renderMilliseconds))
        frame.append(number(record?.sampleBufferMilliseconds))
        frame.append(number(record?.submissionMilliseconds))
        frame.append(record.map { $0.wasInBackground ? "true" : "false" } ?? "")
        frame.append(record.map { $0.pipWasActive ? "true" : "false" } ?? "")
        frame.append(record?.dropReason ?? "")
        let summary = [
          number(
            report.snapshot.elapsedSeconds > 0
              ? Double(report.snapshot.completedFrames) / report.snapshot.elapsedSeconds : 0),
          number(
            report.snapshot.elapsedSeconds > 0
              ? Double(report.snapshot.submittedFrames) / report.snapshot.elapsedSeconds : 0),
          "\(report.snapshot.droppedFrames)",
          number(report.snapshot.averageRenderMilliseconds),
          number(report.snapshot.p50RenderMilliseconds),
          number(report.snapshot.p95RenderMilliseconds),
          number(report.snapshot.maximumRenderMilliseconds),
          number(report.snapshot.averagePixelBufferMilliseconds),
          number(report.snapshot.p50PixelBufferMilliseconds),
          number(report.snapshot.p95PixelBufferMilliseconds),
          number(report.snapshot.maximumPixelBufferMilliseconds),
          number(report.snapshot.averageSampleBufferMilliseconds),
          number(report.snapshot.p50SampleBufferMilliseconds),
          number(report.snapshot.p95SampleBufferMilliseconds),
          number(report.snapshot.maximumSampleBufferMilliseconds),
          number(report.snapshot.averageSubmissionMilliseconds),
          number(report.snapshot.p50SubmissionMilliseconds),
          number(report.snapshot.p95SubmissionMilliseconds),
          number(report.snapshot.maximumSubmissionMilliseconds),
          number(report.snapshot.averageSchedulingDelayMilliseconds),
          number(report.snapshot.p50SchedulingDelayMilliseconds),
          number(report.snapshot.p95SchedulingDelayMilliseconds),
          number(report.snapshot.maximumSchedulingDelayMilliseconds),
        ]
        rows.append((base + frame + summary).map(escape).joined(separator: ","))
      }
    }
    return rows.joined(separator: "\n") + "\n"
  }

  private static func seconds(_ value: TimeInterval?, relativeTo origin: TimeInterval?) -> String {
    guard let value, let origin else { return "" }
    return number(value - origin)
  }

  private static func number(_ value: Double?) -> String {
    guard let value, value.isFinite else { return "" }
    return String(format: "%.4f", value)
  }

  private static func escape(_ value: String) -> String {
    "\"\(value.replacingOccurrences(of: "\"", with: "\"\""))\""
  }
}

extension ProcessInfo.ThermalState {
  var benchmarkDescription: String {
    switch self {
    case .nominal: "nominal"
    case .fair: "fair"
    case .serious: "serious"
    case .critical: "critical"
    @unknown default: "unknown"
    }
  }
}
