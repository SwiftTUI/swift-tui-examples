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
    let ipv4Status = address.withCString {
      unsafe inet_pton(AF_INET, $0, &ipv4)
    }
    if ipv4Status == 1 {
      return withUnsafeBytes(of: ipv4) { unsafe Array($0.prefix(4)) }
    }
    let ipv6Status = address.withCString {
      unsafe inet_pton(AF_INET6, $0, &ipv6)
    }
    guard ipv6Status == 1 else { return nil }
    return withUnsafeBytes(of: ipv6) { unsafe Array($0.prefix(16)) }
  }

  /// IPv4 blocks that are not public unicast destinations, each matched on
  /// its full prefix length.
  ///
  /// The special-purpose entries are the IANA IPv4 Special-Purpose Address
  /// Registry's (RFC 6890) blocks that are not globally reachable, plus the
  /// deprecated 6to4 relay anycast block; the last two rows are multicast
  /// and the reserved space above it. 192.0.0.9/32 and 192.0.0.10/32, the
  /// registry's globally reachable anycast exceptions inside 192.0.0.0/24,
  /// stay refused with the rest of that block: they are protocol anycast
  /// addresses, not image hosts.
  private static let nonPublicIPv4Blocks: [(network: UInt32, prefixLength: UInt32)] = [
    (0x0000_0000, 8),  // 0.0.0.0/8, "this network" (RFC 791)
    (0x0A00_0000, 8),  // 10.0.0.0/8, private use (RFC 1918)
    (0x6440_0000, 10),  // 100.64.0.0/10, shared address space (RFC 6598)
    (0x7F00_0000, 8),  // 127.0.0.0/8, loopback (RFC 1122)
    (0xA9FE_0000, 16),  // 169.254.0.0/16, link local (RFC 3927)
    (0xAC10_0000, 12),  // 172.16.0.0/12, private use (RFC 1918)
    (0xC000_0000, 24),  // 192.0.0.0/24, IETF protocol assignments (RFC 6890)
    (0xC000_0200, 24),  // 192.0.2.0/24, documentation TEST-NET-1 (RFC 5737)
    (0xC058_6300, 24),  // 192.88.99.0/24, deprecated 6to4 relay anycast (RFC 7526)
    (0xC0A8_0000, 16),  // 192.168.0.0/16, private use (RFC 1918)
    (0xC612_0000, 15),  // 198.18.0.0/15, benchmarking (RFC 2544)
    (0xC633_6400, 24),  // 198.51.100.0/24, documentation TEST-NET-2 (RFC 5737)
    (0xCB00_7100, 24),  // 203.0.113.0/24, documentation TEST-NET-3 (RFC 5737)
    (0xE000_0000, 4),  // 224.0.0.0/4, multicast (RFC 5771)
    (0xF000_0000, 4),  // 240.0.0.0/4, reserved, and 255.255.255.255 (RFC 1112, RFC 919)
  ]

  private static func isPublicIPv4(_ bytes: [UInt8]) -> Bool {
    guard bytes.count == 4 else { return false }
    let address = bytes.reduce(UInt32(0)) { $0 << 8 | UInt32($1) }
    return !nonPublicIPv4Blocks.contains { block in
      let mask = UInt32.max << (32 - block.prefixLength)
      return address & mask == block.network
    }
  }
}
