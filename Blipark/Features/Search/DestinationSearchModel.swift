import Foundation

@MainActor
final class DestinationSearchModel: ObservableObject {
  @Published private(set) var results: [Destination] = []
  @Published private(set) var isSearching = false
  @Published var errorMessage: String?

  private let provider: any DestinationSearchProviding

  init(provider: any DestinationSearchProviding) {
    self.provider = provider
  }

  func search(_ query: String) async {
    let normalized = query.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !normalized.isEmpty else {
      results = []
      errorMessage = nil
      return
    }

    do {
      if let linkedDestination = try ExternalMapLinkParser.parse(normalized) {
        results = [linkedDestination]
        errorMessage = nil
        return
      }
    } catch {
      results = []
      errorMessage = error.localizedDescription
      return
    }

    guard normalized.count >= 2 else {
      results = []
      errorMessage = nil
      return
    }

    isSearching = true
    errorMessage = nil
    defer { isSearching = false }
    do {
      results = try await provider.searchDestinations(matching: normalized)
    } catch is CancellationError {
      return
    } catch {
      results = []
      errorMessage = "搜尋失敗：\(error.localizedDescription)"
    }
  }
}

