import Foundation

enum ExternalMapLinkError: LocalizedError, Equatable {
  case unsupportedProvider
  case shortenedLinkNeedsResolution
  case missingCoordinate

  var errorDescription: String? {
    switch self {
    case .unsupportedProvider: "目前只支援 Apple Maps 與 Google Maps 地點連結。"
    case .shortenedLinkNeedsResolution: "這是短連結，目前無法在裝置端安全解析；請貼上展開後的完整地圖連結。"
    case .missingCoordinate: "連結中沒有可辨識的地點座標，請改用地點名稱或地址搜尋。"
    }
  }
}

enum ExternalMapLinkParser {
  static func parse(_ value: String) throws -> Destination? {
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    guard let url = URL(string: trimmed), let host = url.host?.lowercased() else { return nil }

    if host == "maps.apple.com" {
      return try parseAppleMaps(url)
    }
    if host == "maps.app.goo.gl" || host == "goo.gl" {
      throw ExternalMapLinkError.shortenedLinkNeedsResolution
    }
    if host.contains("google.") || host == "google.com" {
      return try parseGoogleMaps(url)
    }
    if url.scheme == "http" || url.scheme == "https" {
      throw ExternalMapLinkError.unsupportedProvider
    }
    return nil
  }

  private static func parseAppleMaps(_ url: URL) throws -> Destination {
    let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
    let query = components?.queryItems?.first(where: { $0.name == "q" })?.value
    let coordinateValue = components?.queryItems?.first(where: { $0.name == "ll" })?.value
    guard let coordinate = coordinate(from: coordinateValue) else {
      throw ExternalMapLinkError.missingCoordinate
    }
    return Destination(
      name: query?.removingPercentEncoding ?? query ?? "Apple Maps 地點",
      coordinate: coordinate,
      sourceReference: url.absoluteString
    )
  }

  private static func parseGoogleMaps(_ url: URL) throws -> Destination {
    let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
    let queryValue = components?.queryItems?
      .first(where: { ["query", "q", "destination"].contains($0.name) })?.value
    var parsedCoordinate = coordinate(from: queryValue)
    if parsedCoordinate == nil {
      let pattern = #"@(-?\d+(?:\.\d+)?),(-?\d+(?:\.\d+)?)"#
      if let match = url.absoluteString.range(of: pattern, options: .regularExpression) {
        parsedCoordinate = coordinate(from: String(url.absoluteString[match]).dropFirst().description)
      }
    }
    guard let parsedCoordinate else { throw ExternalMapLinkError.missingCoordinate }
    let pathName = url.pathComponents
      .drop(while: { $0 != "place" })
      .dropFirst()
      .first?
      .replacingOccurrences(of: "+", with: " ")
      .removingPercentEncoding
    return Destination(
      name: pathName ?? "Google Maps 地點",
      coordinate: parsedCoordinate,
      sourceReference: url.absoluteString
    )
  }

  private static func coordinate(from value: String?) -> GeoCoordinate? {
    guard let value else { return nil }
    let parts = value.split(separator: ",", maxSplits: 1).map(String.init)
    guard parts.count == 2,
      let latitude = Double(parts[0]),
      let longitude = Double(parts[1])
    else { return nil }
    let coordinate = GeoCoordinate(latitude: latitude, longitude: longitude)
    return coordinate.isValid ? coordinate : nil
  }
}

