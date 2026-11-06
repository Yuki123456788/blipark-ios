import Foundation

actor JSONFileStore<Value: Codable & Sendable> {
  private let fileURL: URL
  private let encoder: JSONEncoder
  private let decoder: JSONDecoder

  init(fileURL: URL) {
    self.fileURL = fileURL
    encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    encoder.dateEncodingStrategy = .iso8601
    decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
  }

  func load(or fallback: @autoclosure () -> Value) throws -> Value {
    guard FileManager.default.fileExists(atPath: fileURL.path) else { return fallback() }
    do {
      return try decoder.decode(Value.self, from: Data(contentsOf: fileURL))
    } catch {
      throw RepositoryError.invalidData("本機資料無法讀取：\(error.localizedDescription)")
    }
  }

  func save(_ value: Value) throws {
    do {
      try FileManager.default.createDirectory(
        at: fileURL.deletingLastPathComponent(),
        withIntermediateDirectories: true
      )
      try encoder.encode(value).write(to: fileURL, options: [.atomic])
    } catch {
      throw RepositoryError.invalidData("本機資料無法儲存：\(error.localizedDescription)")
    }
  }

  func remove() throws {
    guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
    try FileManager.default.removeItem(at: fileURL)
  }
}

enum BliparkStorageDirectory {
  static func applicationSupport(fileManager: FileManager = .default) -> URL {
    let root = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
    return root.appendingPathComponent("Blipark", isDirectory: true)
  }
}

