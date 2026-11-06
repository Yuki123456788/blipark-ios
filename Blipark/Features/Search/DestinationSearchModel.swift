import Foundation

@MainActor
final class DestinationSearchModel: ObservableObject {
  @Published private(set) var allResults: [Destination] = []
  @Published private(set) var results: [Destination] = []
  @Published private(set) var isSearching = false
  @Published var errorMessage: String?

  private let provider: any DestinationSearchProviding

  init(provider: any DestinationSearchProviding) {
    self.provider = provider
  }

  func load() async {
    isSearching = true
    errorMessage = nil
    defer { isSearching = false }
    do {
      allResults = try await provider.searchDestinations(matching: "")
      results = allResults
    } catch is CancellationError {
      return
    } catch {
      allResults = []
      results = []
      errorMessage = "讀取測試地點失敗：\(error.localizedDescription)"
    }
  }

  func filter(_ query: String) {
    let normalized = query.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !normalized.isEmpty else {
      results = allResults
      return
    }
    results = allResults.filter {
      $0.name.localizedStandardContains(normalized)
        || ($0.address?.localizedStandardContains(normalized) == true)
    }
  }
}

