import MapKit

enum ParkingGuidancePiPAdapter {
  struct Payload {
    let destination: PiPRealNavigationDestination
    let parkingStops: [PiPRealParkingStop]
  }

  static func payload(for session: ParkingGuidanceSession) -> Payload {
    let candidates = Array(session.orderedCandidates.dropFirst(session.currentCandidateIndex))
    return Payload(
      destination: destination(
        name: session.destination.name,
        address: session.destination.address,
        coordinate: session.destination.coordinate
      ),
      parkingStops: candidates.enumerated().map { index, candidate in
        PiPRealParkingStop(
          id: candidate.id,
          destination: destination(
            name: candidate.name,
            address: candidate.address,
            coordinate: candidate.coordinate
          ),
          kind: candidate.type == .parkingLot ? .parkingLot : .onStreet,
          color: .ordered(at: index)
        )
      }
    )
  }

  private static func destination(
    name: String,
    address: String?,
    coordinate: GeoCoordinate
  ) -> PiPRealNavigationDestination {
    let placemark = MKPlacemark(coordinate: coordinate.clLocationCoordinate)
    let item = MKMapItem(placemark: placemark)
    item.name = name
    return PiPRealNavigationDestination(mapItem: item, fallbackAddress: address)
  }
}
