import Foundation

public enum LinkResolution: Equatable, Sendable {
  case anchor(String)
  case markdownDocument(URL, anchor: String?)
  case external(URL)
  case file(URL)
  case unsupported(scheme: String)
  case invalid(String)
}

public struct LinkResolver: Sendable {
  private static let markdownExtensions: Set<String> = ["md", "markdown", "mdown"]
  private static let externalSchemes: Set<String> = ["http", "https", "mailto"]

  public init() {}

  public func resolve(_ destination: String, relativeTo documentURL: URL?) -> LinkResolution {
    let trimmed = destination.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return .invalid(destination) }
    if trimmed.hasPrefix("#") {
      let rawAnchor = String(trimmed.dropFirst())
      return .anchor(rawAnchor.removingPercentEncoding ?? rawAnchor)
    }
    if let url = URL(string: trimmed), let scheme = url.scheme?.lowercased() {
      if Self.externalSchemes.contains(scheme) {
        return .external(url)
      }
      if scheme == "file" {
        return classifyFile(url)
      }
      return .unsupported(scheme: scheme)
    }
    guard let base = documentURL?.deletingLastPathComponent() else {
      return .invalid(destination)
    }
    guard let relative = URL(string: trimmed, relativeTo: base)?.absoluteURL,
      relative.isFileURL
    else {
      return .invalid(destination)
    }
    return classifyFile(relative.standardized)
  }

  private func classifyFile(_ url: URL) -> LinkResolution {
    let anchor = url.fragment(percentEncoded: false).flatMap { $0.isEmpty ? nil : $0 }
    var components = URLComponents(
      url: url.absoluteURL,
      resolvingAgainstBaseURL: true
    )
    components?.query = nil
    components?.fragment = nil
    let navigationURL = (components?.url ?? url).standardized
    if Self.markdownExtensions.contains(navigationURL.pathExtension.lowercased()) {
      return .markdownDocument(navigationURL, anchor: anchor)
    }
    return .file(navigationURL)
  }
}
