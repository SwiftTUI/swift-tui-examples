import Foundation

#if canImport(Darwin)
  import Darwin
#elseif canImport(Glibc)
  import Glibc
#endif

typealias RemoteImageURLValidator = @Sendable (URL) throws -> Void
typealias RemoteImagePeerValidator = @Sendable (String, URL) throws -> Void

enum RemoteImageNetworkPolicy {
  static func validate(_ url: URL) throws {
    guard let scheme = url.scheme?.lowercased(),
      scheme == "http" || scheme == "https",
      let rawHost = url.host(percentEncoded: false),
      !rawHost.isEmpty
    else {
      throw ResourceLoadError.remoteDestinationBlocked(
        url,
        "destination must be an HTTP(S) host"
      )
    }
    guard url.user(percentEncoded: false) == nil,
      url.password(percentEncoded: false) == nil
    else {
      throw ResourceLoadError.remoteDestinationBlocked(
        url,
        "embedded credentials are not allowed"
      )
    }
    let port = url.port ?? (scheme == "https" ? 443 : 80)
    guard port == 80 || port == 443 else {
      throw ResourceLoadError.remoteDestinationBlocked(
        url,
        "only standard HTTP and HTTPS ports are allowed"
      )
    }

    let host = rawHost.lowercased()
    guard let address = addressBytes(host) else {
      throw ResourceLoadError.remoteDestinationBlocked(
        url,
        "remote images require a literal public IPv4 or IPv6 host"
      )
    }

    if !isPublicAddress(address) {
      throw ResourceLoadError.remoteDestinationBlocked(
        url,
        "numeric host is not on a public network"
      )
    }
  }

  static func validatePeerAddress(_ address: String, for url: URL) throws {
    guard let bytes = addressBytes(address), isPublicAddress(bytes) else {
      throw ResourceLoadError.remoteDestinationBlocked(
        url,
        "connection peer is not a public IP address"
      )
    }
  }

  static func isPublicAddress(_ bytes: [UInt8]) -> Bool {
    switch bytes.count {
    case 4:
      return isPublicIPv4(bytes)
    case 16:
      if bytes.prefix(10).allSatisfy({ $0 == 0 }),
        bytes[10] == 0xFF,
        bytes[11] == 0xFF
      {
        return isPublicIPv4(Array(bytes.suffix(4)))
      }
      guard bytes[0] & 0xE0 == 0x20 else { return false }
      if bytes[0] == 0x20, bytes[1] == 0x01 {
        if bytes[2] <= 0x01 { return false }
        if bytes[2] == 0x0D, bytes[3] == 0xB8 { return false }
      }
      if bytes[0] == 0x20, bytes[1] == 0x02 { return false }
      if bytes[0] == 0x3F, bytes[1] & 0xF0 == 0xF0 { return false }
      return true
    default:
      return false
    }
  }

  private static func addressBytes(_ address: String) -> [UInt8]? {
    var ipv4 = in_addr()
    var ipv6 = in6_addr()
    let ipv4Status = unsafe address.withCString {
      unsafe inet_pton(AF_INET, $0, &ipv4)
    }
    if ipv4Status == 1 {
      return unsafe withUnsafeBytes(of: ipv4) { unsafe Array($0.prefix(4)) }
    }
    let ipv6Status = unsafe address.withCString {
      unsafe inet_pton(AF_INET6, $0, &ipv6)
    }
    guard ipv6Status == 1 else { return nil }
    return unsafe withUnsafeBytes(of: ipv6) { unsafe Array($0.prefix(16)) }
  }

  private static func isPublicIPv4(_ bytes: [UInt8]) -> Bool {
    guard bytes.count == 4 else { return false }
    let first = bytes[0]
    let second = bytes[1]
    switch first {
    case 0, 10, 127:
      return false
    case 100 where (64...127).contains(second):
      return false
    case 169 where second == 254:
      return false
    case 172 where (16...31).contains(second):
      return false
    case 192 where second == 0 || second == 168:
      return false
    case 192 where second == 88 && bytes[2] == 99:
      return false
    case 198 where second == 18 || second == 19 || second == 51:
      return false
    case 203 where second == 0 && bytes[2] == 113:
      return false
    case 224...255:
      return false
    default:
      return true
    }
  }
}
