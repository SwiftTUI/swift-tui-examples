public import Foundation
import Synchronization

#if canImport(FoundationNetworking)
  // Linux splits URLSession out of Foundation. `ImageResourceLoader.init` is
  // public and takes a `URLSessionConfiguration`, so this import must be public
  // too — an internal import makes that initializer illegal on Linux only.
  public import FoundationNetworking
#endif

public struct LoadedImage: Equatable, Sendable {
  public var data: Data
  public var url: URL
  public var image: InspectedImage
  var localVersion: RegularFileIdentity?

  public init(data: Data, url: URL, image: InspectedImage) {
    self.data = data
    self.url = url
    self.image = image
    localVersion = nil
  }

  init(
    data: Data,
    url: URL,
    image: InspectedImage,
    localVersion: RegularFileIdentity?
  ) {
    self.data = data
    self.url = url
    self.image = image
    self.localVersion = localVersion
  }
}

public enum ResourceLoadError: Error, Sendable, LocalizedError {
  case invalidURL(String)
  case unsupportedScheme(String)
  case remoteImagesDisabled(URL)
  case remoteDestinationBlocked(URL, String)
  case missing(URL)
  case encodedImageTooLarge(URL, Int)
  case requestFailed(URL, String)
  case badHTTPStatus(URL, Int)
  case invalidImage(URL, String)

  public var errorDescription: String? {
    switch self {
    case .invalidURL(let source):
      "invalid image URL '\(source)'"
    case .unsupportedScheme(let scheme):
      "image scheme '\(scheme)' is unsupported"
    case .remoteImagesDisabled(let url):
      "remote image blocked: \(url.absoluteString) (use --allow-remote-images)"
    case .remoteDestinationBlocked(let url, let reason):
      "remote image blocked: \(url.absoluteString) (\(reason))"
    case .missing(let url):
      "image does not exist: \(url.path)"
    case .encodedImageTooLarge(let url, let count):
      "\(url.absoluteString) is \(count) bytes; encoded image maximum is 10 MiB"
    case .requestFailed(let url, let reason):
      "image request failed for \(url.absoluteString): \(reason)"
    case .badHTTPStatus(let url, let status):
      "image request returned HTTP \(status) for \(url.absoluteString)"
    case .invalidImage(let url, let reason):
      "invalid image \(url.absoluteString): \(reason)"
    }
  }
}

public struct ResourceLoader: Sendable {
  public static let maximumEncodedBytes = 10 * 1_024 * 1_024

  public var allowsRemoteImages: Bool
  private let inspector: ImageHeaderInspector
  private let remoteSessionConfiguration: @Sendable () -> URLSessionConfiguration
  private let remoteURLValidator: RemoteImageURLValidator
  private let remotePeerValidator: RemoteImagePeerValidator
  private let requiresPublicPeerValidation: Bool

  public init(
    allowsRemoteImages: Bool,
    inspector: ImageHeaderInspector = ImageHeaderInspector(),
    remoteSessionConfiguration:
      @escaping @Sendable () -> URLSessionConfiguration = {
        URLSessionConfiguration.ephemeral
      }
  ) {
    self.allowsRemoteImages = allowsRemoteImages
    self.inspector = inspector
    self.remoteSessionConfiguration = remoteSessionConfiguration
    remoteURLValidator = RemoteImageNetworkPolicy.validate
    remotePeerValidator = RemoteImageNetworkPolicy.validatePeerAddress
    requiresPublicPeerValidation = true
  }

  init(
    allowsRemoteImages: Bool,
    inspector: ImageHeaderInspector,
    remoteSessionConfiguration: @escaping @Sendable () -> URLSessionConfiguration,
    remoteURLValidator: @escaping RemoteImageURLValidator,
    remotePeerValidator: @escaping RemoteImagePeerValidator,
    requiresPublicPeerValidation: Bool
  ) {
    self.allowsRemoteImages = allowsRemoteImages
    self.inspector = inspector
    self.remoteSessionConfiguration = remoteSessionConfiguration
    self.remoteURLValidator = remoteURLValidator
    self.remotePeerValidator = remotePeerValidator
    self.requiresPublicPeerValidation = requiresPublicPeerValidation
  }

  public func load(source: String, relativeTo documentURL: URL?) async throws -> LoadedImage {
    let url = try resolvedURL(source, relativeTo: documentURL)
    let scheme = url.scheme?.lowercased()
    let data: Data
    let localVersion: RegularFileIdentity?
    switch scheme {
    case "http"?, "https"?:
      guard allowsRemoteImages else {
        throw ResourceLoadError.remoteImagesDisabled(url)
      }
      data = try await loadRemote(url)
      localVersion = nil
    case "file"?, nil:
      let local = try loadLocal(url)
      data = local.data
      localVersion = local.identity
    case let scheme?:
      throw ResourceLoadError.unsupportedScheme(scheme)
    }
    let image: InspectedImage
    do {
      image = try inspector.inspect(data)
    } catch {
      throw ResourceLoadError.invalidImage(url, error.localizedDescription)
    }
    return LoadedImage(
      data: data,
      url: url,
      image: image,
      localVersion: localVersion
    )
  }

  public static func fingerprint(_ data: Data) -> UInt64 {
    data.reduce(1_469_598_103_934_665_603) { partial, byte in
      (partial ^ UInt64(byte)) &* 1_099_511_628_211
    }
  }

  func resolvedURL(_ source: String, relativeTo documentURL: URL?) throws -> URL {
    try Self.resolveURL(source, relativeTo: documentURL)
  }

  static func resolveURL(_ source: String, relativeTo documentURL: URL?) throws -> URL {
    let trimmed = source.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { throw ResourceLoadError.invalidURL(source) }
    if let absolute = URL(string: trimmed), absolute.scheme != nil {
      return absolute
    }
    guard let base = documentURL?.deletingLastPathComponent() else {
      throw ResourceLoadError.invalidURL(source)
    }
    guard let relative = URL(string: trimmed, relativeTo: base)?.absoluteURL,
      relative.isFileURL
    else {
      throw ResourceLoadError.invalidURL(source)
    }
    return relative.standardizedFileURL
  }

  private func loadLocal(_ url: URL) throws -> BoundedRegularFileReadResult {
    do {
      return try BoundedRegularFileReader.readWithIdentity(
        url,
        maximumBytes: Self.maximumEncodedBytes
      )
    } catch BoundedRegularFileReadError.tooLarge(let count) {
      throw ResourceLoadError.encodedImageTooLarge(url, count)
    } catch {
      throw ResourceLoadError.requestFailed(url, error.localizedDescription)
    }
  }

  private func loadRemote(_ url: URL) async throws -> Data {
    try remoteURLValidator(url)
    let configuration = remoteSessionConfiguration()
    configuration.timeoutIntervalForRequest = Self.boundedTimeout(
      configuration.timeoutIntervalForRequest
    )
    configuration.timeoutIntervalForResource = Self.boundedTimeout(
      configuration.timeoutIntervalForResource
    )
    configuration.urlCache = nil
    configuration.connectionProxyDictionary = [:]
    let transferTimeout = min(
      configuration.timeoutIntervalForRequest,
      configuration.timeoutIntervalForResource
    )
    let transfer = RemoteImageTransfer()
    do {
      return try await withTaskCancellationHandler {
        try await withCheckedThrowingContinuation { continuation in
          let delegate = RemoteImageDataDelegate(
            url: url,
            remoteURLValidator: remoteURLValidator,
            remotePeerValidator: remotePeerValidator,
            requiresPublicPeerValidation: requiresPublicPeerValidation
          ) { result in
            transfer.finish(result)
          }
          let session = URLSession(
            configuration: configuration,
            delegate: delegate,
            delegateQueue: nil
          )
          transfer.start(
            session: session,
            task: session.dataTask(with: url),
            timeout: transferTimeout,
            url: url
          ) { result in
            continuation.resume(with: result)
          }
        }
      } onCancel: {
        transfer.cancel()
      }
    } catch let error as ResourceLoadError {
      throw error
    } catch is CancellationError {
      throw CancellationError()
    } catch {
      throw ResourceLoadError.requestFailed(url, error.localizedDescription)
    }
  }

  private static func boundedTimeout(_ configured: TimeInterval) -> TimeInterval {
    guard configured.isFinite, configured > 0 else { return 10 }
    return min(configured, 10)
  }
}

private final class RemoteImageTransfer: Sendable {
  private struct State {
    var session: URLSession?
    var task: URLSessionDataTask?
    var timeoutTask: Task<Void, Never>?
    var completion: (@Sendable (Result<Data, Error>) -> Void)?
    var cancellationRequested = false
    var isFinished = false
  }

  private let state = Mutex(State())

  func start(
    session: URLSession,
    task: URLSessionDataTask,
    timeout: TimeInterval,
    url: URL,
    completion: @escaping @Sendable (Result<Data, Error>) -> Void
  ) {
    let cancelAfterStarting = state.withLock {
      $0.session = session
      $0.task = task
      $0.completion = completion
      return $0.cancellationRequested
    }
    guard !cancelAfterStarting else {
      finish(.failure(CancellationError()), cancellingTransport: true)
      return
    }

    task.resume()
    let milliseconds = max(1, Int64((timeout * 1_000).rounded(.up)))
    let timeoutTask = Task { [weak self] in
      do {
        try await Task.sleep(for: .milliseconds(milliseconds))
      } catch {
        return
      }
      self?.finish(
        .failure(ResourceLoadError.requestFailed(url, "request timed out")),
        cancellingTransport: true
      )
    }
    let transferAlreadyFinished = state.withLock {
      guard !$0.isFinished else { return true }
      $0.timeoutTask = timeoutTask
      return false
    }
    if transferAlreadyFinished {
      timeoutTask.cancel()
    }
  }

  func cancel() {
    let hasStarted = state.withLock {
      $0.cancellationRequested = true
      return $0.completion != nil
    }
    guard hasStarted else { return }
    finish(.failure(CancellationError()), cancellingTransport: true)
  }

  func finish(_ result: Result<Data, Error>) {
    finish(result, cancellingTransport: false)
  }

  private func finish(
    _ result: Result<Data, Error>,
    cancellingTransport: Bool
  ) {
    let action:
      (
        session: URLSession?,
        task: URLSessionDataTask?,
        timeoutTask: Task<Void, Never>?,
        completion: @Sendable (Result<Data, Error>) -> Void
      )? = state.withLock {
        guard !$0.isFinished, let completion = $0.completion else {
          return nil
        }
        $0.isFinished = true
        let action = ($0.session, $0.task, $0.timeoutTask, completion)
        $0.session = nil
        $0.task = nil
        $0.timeoutTask = nil
        $0.completion = nil
        return action
      }
    guard let action else { return }
    action.timeoutTask?.cancel()
    if cancellingTransport {
      action.task?.cancel()
      action.session?.invalidateAndCancel()
    }
    action.completion(result)
  }
}

struct BoundedResourceBuffer {
  let maximumBytes: Int
  private(set) var data = Data()

  mutating func validateExpectedLength(_ length: Int64, url: URL) throws {
    guard length > Int64(maximumBytes) else { return }
    let reported = length > Int64(Int.max) ? Int.max : Int(length)
    throw ResourceLoadError.encodedImageTooLarge(url, reported)
  }

  mutating func append(_ chunk: Data, url: URL) throws {
    guard chunk.count <= maximumBytes - data.count else {
      throw ResourceLoadError.encodedImageTooLarge(url, data.count + chunk.count)
    }
    data.append(chunk)
  }
}

private final class RemoteImageDataDelegate: NSObject, URLSessionDataDelegate,
  URLSessionTaskDelegate,
  Sendable
{
  private struct State {
    var buffer = BoundedResourceBuffer(maximumBytes: ResourceLoader.maximumEncodedBytes)
    var failure: ResourceLoadError?
    var completion: (@Sendable (Result<Data, Error>) -> Void)?
    var redirectCount = 0
    var peerValidated = false
  }

  private let url: URL
  private let remoteURLValidator: RemoteImageURLValidator
  private let remotePeerValidator: RemoteImagePeerValidator
  private let requiresPublicPeerValidation: Bool
  private let state: Mutex<State>

  init(
    url: URL,
    remoteURLValidator: @escaping RemoteImageURLValidator,
    remotePeerValidator: @escaping RemoteImagePeerValidator,
    requiresPublicPeerValidation: Bool,
    completion: @escaping @Sendable (Result<Data, Error>) -> Void
  ) {
    self.url = url
    self.remoteURLValidator = remoteURLValidator
    self.remotePeerValidator = remotePeerValidator
    self.requiresPublicPeerValidation = requiresPublicPeerValidation
    state = Mutex(State(completion: completion))
  }

  func urlSession(
    _ session: URLSession,
    dataTask: URLSessionDataTask,
    didReceive response: URLResponse,
    completionHandler: @escaping @Sendable (URLSession.ResponseDisposition) -> Void
  ) {
    let disposition: URLSession.ResponseDisposition = state.withLock {
      guard let http = response as? HTTPURLResponse else {
        $0.failure = .requestFailed(url, "response was not HTTP")
        return .cancel
      }
      guard (200..<300).contains(http.statusCode) else {
        $0.failure = .badHTTPStatus(url, http.statusCode)
        return .cancel
      }
      do {
        try remoteURLValidator(response.url ?? url)
        try $0.buffer.validateExpectedLength(
          response.expectedContentLength,
          url: url
        )
        return .allow
      } catch let error as ResourceLoadError {
        $0.failure = error
        return .cancel
      } catch {
        $0.failure = .requestFailed(url, error.localizedDescription)
        return .cancel
      }
    }
    completionHandler(disposition)
    if disposition == .cancel {
      finishStoredFailure(in: session)
    }
  }

  func urlSession(
    _ session: URLSession,
    dataTask: URLSessionDataTask,
    didReceive data: Data
  ) {
    let shouldCancel = state.withLock {
      guard $0.failure == nil else { return true }
      do {
        try $0.buffer.append(data, url: url)
        return false
      } catch let error as ResourceLoadError {
        $0.failure = error
        return true
      } catch {
        $0.failure = .requestFailed(url, error.localizedDescription)
        return true
      }
    }
    if shouldCancel {
      dataTask.cancel()
      finishStoredFailure(in: session)
    }
  }

  func urlSession(
    _ session: URLSession,
    task: URLSessionTask,
    didFinishCollecting metrics: URLSessionTaskMetrics
  ) {
    guard requiresPublicPeerValidation else {
      state.withLock { $0.peerValidated = true }
      return
    }

    let validationFailure: ResourceLoadError? = {
      guard !metrics.transactionMetrics.isEmpty else {
        return .remoteDestinationBlocked(
          task.currentRequest?.url ?? url,
          "connection metrics were unavailable"
        )
      }
      do {
        for transaction in metrics.transactionMetrics {
          let transactionURL = transaction.request.url ?? task.currentRequest?.url ?? url
          try remoteURLValidator(transactionURL)
          guard !transaction.isProxyConnection else {
            throw ResourceLoadError.remoteDestinationBlocked(
              transactionURL,
              "proxy and Private Relay connections are not supported"
            )
          }
          guard let address = transaction.remoteAddress else {
            throw ResourceLoadError.remoteDestinationBlocked(
              transactionURL,
              "connection peer address was unavailable"
            )
          }
          try remotePeerValidator(address, transactionURL)
        }
        return nil
      } catch let error as ResourceLoadError {
        return error
      } catch {
        return .requestFailed(url, error.localizedDescription)
      }
    }()

    state.withLock {
      if let validationFailure {
        $0.failure = validationFailure
      } else {
        $0.peerValidated = true
      }
    }
  }

  func urlSession(
    _ session: URLSession,
    task: URLSessionTask,
    didCompleteWithError error: Error?
  ) {
    let completionAndResult: ((@Sendable (Result<Data, Error>) -> Void), Result<Data, Error>)? =
      state.withLock {
        guard let completion = $0.completion else { return nil }
        $0.completion = nil
        if let failure = $0.failure {
          return (completion, .failure(failure))
        }
        if let error {
          return (
            completion,
            .failure(ResourceLoadError.requestFailed(url, error.localizedDescription))
          )
        }
        guard !requiresPublicPeerValidation || $0.peerValidated else {
          return (
            completion,
            .failure(
              ResourceLoadError.remoteDestinationBlocked(
                task.currentRequest?.url ?? url,
                "connection peer could not be verified"
              )
            )
          )
        }
        return (completion, .success($0.buffer.data))
      }
    session.finishTasksAndInvalidate()
    guard let (completion, result) = completionAndResult else { return }
    completion(result)
  }

  func urlSession(
    _ session: URLSession,
    task: URLSessionTask,
    willPerformHTTPRedirection response: HTTPURLResponse,
    newRequest request: URLRequest,
    completionHandler: @escaping @Sendable (URLRequest?) -> Void
  ) {
    guard let destination = request.url else {
      state.withLock {
        $0.failure = .requestFailed(url, "redirect had no destination")
      }
      completionHandler(nil)
      finishStoredFailure(in: session)
      return
    }
    do {
      try remoteURLValidator(destination)
      let permitsRedirect = state.withLock {
        $0.redirectCount += 1
        guard $0.redirectCount <= 5 else {
          $0.failure = .requestFailed(url, "remote image exceeded five redirects")
          return false
        }
        return true
      }
      completionHandler(permitsRedirect ? request : nil)
      if !permitsRedirect {
        finishStoredFailure(in: session)
      }
    } catch let error as ResourceLoadError {
      state.withLock { $0.failure = error }
      completionHandler(nil)
      finishStoredFailure(in: session)
    } catch {
      state.withLock {
        $0.failure = .requestFailed(destination, error.localizedDescription)
      }
      completionHandler(nil)
      finishStoredFailure(in: session)
    }
  }

  private func finishStoredFailure(in session: URLSession) {
    let completionAndFailure: ((@Sendable (Result<Data, Error>) -> Void), ResourceLoadError)? =
      state.withLock {
        guard let completion = $0.completion, let failure = $0.failure else {
          return nil
        }
        $0.completion = nil
        return (completion, failure)
      }
    guard let (completion, failure) = completionAndFailure else { return }
    session.invalidateAndCancel()
    completion(.failure(failure))
  }
}
