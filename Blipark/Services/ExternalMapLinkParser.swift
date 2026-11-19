import Foundation
import MapKit

enum ExternalMapLinkError: LocalizedError, Equatable {
  case invalidLink
  case unsupportedProvider
  case shortenedLinkNeedsResolution
  case missingCoordinate
  case noMatchingPlace

  var errorDescription: String? {
    switch self {
    case .invalidLink: "請貼上有效的 Apple Maps 或 Google Maps 連結。"
    case .unsupportedProvider: "目前只支援 Apple Maps 與 Google Maps 地點連結。"
    case .shortenedLinkNeedsResolution: "無法展開這個地圖短連結，請確認網路後再試一次。"
    case .missingCoordinate: "連結中沒有可辨識的座標或地點資訊。"
    case .noMatchingPlace: "找不到這個連結所代表的地點。"
    }
  }
}

enum ExternalMapLinkParser {
  static func parse(_ value: String) throws -> Destination? {
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    guard let url = URL(string: trimmed), let host = url.host?.lowercased() else { return nil }

    if host == "maps.apple" || host == "maps.app.goo.gl" || host == "goo.gl" {
      throw ExternalMapLinkError.shortenedLinkNeedsResolution
    }
    if host == "maps.apple.com" {
      return try parseAppleMaps(url)
    }
    if isGoogleMapsHost(host) {
      return try parseGoogleMaps(url)
    }
    if url.scheme == "http" || url.scheme == "https" {
      throw ExternalMapLinkError.unsupportedProvider
    }
    return nil
  }

  static func isSupportedLink(_ value: String) -> Bool {
    guard let host = URL(string: value.trimmingCharacters(in: .whitespacesAndNewlines))?
      .host?.lowercased()
    else { return false }
    return host == "maps.apple" || host == "maps.apple.com" || host == "maps.app.goo.gl"
      || host == "goo.gl" || isGoogleMapsHost(host)
  }

  static func searchHint(from url: URL) -> String? {
    let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
    let candidates = ["name", "q", "query", "destination", "daddr", "address"]
    for key in candidates {
      if let value = items.first(where: { $0.name.lowercased() == key })?.value,
        coordinate(from: value) == nil,
        !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      {
        return value
      }
    }
    if let placeIndex = url.pathComponents.firstIndex(of: "place"),
      url.pathComponents.indices.contains(placeIndex + 1)
    {
      return url.pathComponents[placeIndex + 1]
        .replacingOccurrences(of: "+", with: " ")
        .removingPercentEncoding
    }
    return nil
  }

  static func applePlaceIdentifier(from url: URL) -> String? {
    URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?
      .first { $0.name.lowercased() == "place-id" }?.value?.nilIfBlank
  }

  private static func parseAppleMaps(_ url: URL) throws -> Destination {
    let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
    let coordinateValue = firstValue(in: items, names: ["coordinate", "ll", "daddr"])
    guard let coordinate = coordinate(from: coordinateValue) else {
      throw ExternalMapLinkError.missingCoordinate
    }
    let name = firstValue(in: items, names: ["name", "q"])
    let address = firstValue(in: items, names: ["address"])
    let placeID = firstValue(in: items, names: ["place-id"])
    return Destination(
      name: name?.nilIfBlank ?? "Apple Maps 地點",
      address: address?.nilIfBlank,
      coordinate: coordinate,
      externalPlaceID: placeID,
      sourceReference: url.absoluteString
    )
  }

  private static func parseGoogleMaps(_ url: URL) throws -> Destination {
    let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
    let queryValue = firstValue(in: items, names: ["destination", "daddr", "query", "q", "ll"])
    var parsedCoordinate = coordinate(from: queryValue)
    if parsedCoordinate == nil {
      parsedCoordinate = coordinate(matching: #"@(-?\d+(?:\.\d+)?),(-?\d+(?:\.\d+)?)"#, in: url.absoluteString)
    }
    if parsedCoordinate == nil {
      parsedCoordinate = coordinate(matching: #"!3d(-?\d+(?:\.\d+)?)!4d(-?\d+(?:\.\d+)?)"#, in: url.absoluteString)
    }
    guard let parsedCoordinate else { throw ExternalMapLinkError.missingCoordinate }
    let pathName = searchHint(from: url)
    return Destination(
      name: pathName?.nilIfBlank ?? "Google Maps 地點",
      coordinate: parsedCoordinate,
      sourceReference: url.absoluteString
    )
  }

  private static func isGoogleMapsHost(_ host: String) -> Bool {
    host == "google.com" || host.contains("google.")
  }

  private static func firstValue(in items: [URLQueryItem], names: [String]) -> String? {
    for name in names {
      if let value = items.first(where: { $0.name.lowercased() == name })?.value { return value }
    }
    return nil
  }

  private static func coordinate(from value: String?) -> GeoCoordinate? {
    guard let value else { return nil }
    let parts = value.split(separator: ",", maxSplits: 1).map(String.init)
    guard parts.count == 2,
      let latitude = Double(parts[0].trimmingCharacters(in: .whitespacesAndNewlines)),
      let longitude = Double(parts[1].trimmingCharacters(in: .whitespacesAndNewlines))
    else { return nil }
    let coordinate = GeoCoordinate(latitude: latitude, longitude: longitude)
    return coordinate.isValid ? coordinate : nil
  }

  private static func coordinate(matching pattern: String, in value: String) -> GeoCoordinate? {
    guard let expression = try? NSRegularExpression(pattern: pattern),
      let match = expression.firstMatch(in: value, range: NSRange(value.startIndex..., in: value)),
      let latitudeRange = Range(match.range(at: 1), in: value),
      let longitudeRange = Range(match.range(at: 2), in: value),
      let latitude = Double(value[latitudeRange]),
      let longitude = Double(value[longitudeRange])
    else { return nil }
    let coordinate = GeoCoordinate(latitude: latitude, longitude: longitude)
    return coordinate.isValid ? coordinate : nil
  }
}

enum ExternalMapLinkImporter {
  static func importLocation(from value: String) async throws -> Destination {
    let original = value.trimmingCharacters(in: .whitespacesAndNewlines)
    guard ExternalMapLinkParser.isSupportedLink(original), let originalURL = URL(string: original) else {
      throw ExternalMapLinkError.invalidLink
    }
    let resolvedURL = try await resolveShortLinkIfNeeded(originalURL)
    if #available(iOS 18.0, *),
      let rawIdentifier = ExternalMapLinkParser.applePlaceIdentifier(from: resolvedURL),
      let identifier = MKMapItem.Identifier(rawValue: rawIdentifier),
      let item = try? await MKMapItemRequest(mapItemIdentifier: identifier).mapItem
    {
      let coordinate = item.placemark.coordinate
      return Destination(
        name: item.name?.nilIfBlank ?? "Apple Maps 地點",
        address: item.placemark.title?.nilIfBlank,
        coordinate: GeoCoordinate(latitude: coordinate.latitude, longitude: coordinate.longitude),
        externalPlaceID: rawIdentifier,
        sourceReference: original
      )
    }
    do {
      if let destination = try ExternalMapLinkParser.parse(resolvedURL.absoluteString) {
        return destination
      }
    } catch ExternalMapLinkError.missingCoordinate {
      // Some shared links contain only a place name. Resolve those through MapKit below.
    }

    guard let query = ExternalMapLinkParser.searchHint(from: resolvedURL)?.nilIfBlank else {
      throw ExternalMapLinkError.missingCoordinate
    }
    let request = MKLocalSearch.Request()
    request.naturalLanguageQuery = query
    let response = try await MKLocalSearch(request: request).start()
    guard let item = response.mapItems.first else { throw ExternalMapLinkError.noMatchingPlace }
    let coordinate = item.placemark.coordinate
    return Destination(
      name: item.name?.nilIfBlank ?? query,
      address: item.placemark.title?.nilIfBlank,
      coordinate: GeoCoordinate(latitude: coordinate.latitude, longitude: coordinate.longitude),
      sourceReference: original
    )
  }

  private static func resolveShortLinkIfNeeded(_ url: URL) async throws -> URL {
    guard let host = url.host?.lowercased(),
      host == "maps.apple" || host == "maps.app.goo.gl" || host == "goo.gl"
    else { return url }
    let (_, response) = try await URLSession.shared.data(from: url)
    guard let resolvedURL = response.url, resolvedURL != url else {
      throw ExternalMapLinkError.shortenedLinkNeedsResolution
    }
    return resolvedURL
  }
}
