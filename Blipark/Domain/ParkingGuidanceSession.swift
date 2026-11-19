import Foundation

enum GuidanceMode: Codable, Equatable, Sendable {
  case externalMaps(provider: ExternalMapProvider)
  case bliparkOnly
}

enum ExternalMapProvider: String, Codable, CaseIterable, Sendable {
  case appleMaps
  case googleMaps
}

enum GuidanceSessionStatus: String, Codable, Sendable {
  case preparing
  case active
  case paused
  case completed
  case cancelled
  case failed
}

struct ParkingGuidanceSession: Codable, Identifiable, Sendable {
  let id: UUID
  var sourcePlanID: UUID?
  var destination: Destination
  var orderedCandidates: [ParkingCandidateSnapshot]
  var currentCandidateIndex: Int
  var mode: GuidanceMode
  var status: GuidanceSessionStatus
  let startedAt: Date
  var updatedAt: Date

  var currentCandidate: ParkingCandidateSnapshot? {
    orderedCandidates.indices.contains(currentCandidateIndex)
      ? orderedCandidates[currentCandidateIndex] : nil
  }
}

