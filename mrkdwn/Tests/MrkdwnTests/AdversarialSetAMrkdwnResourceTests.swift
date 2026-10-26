import Foundation
import Testing

@testable import Mrkdwn

/// Campaign two E1 pass 2: mrkdwn image-header, remote-image address and
/// link contracts (e1s195–e1s200). Byte fixtures are written from the
/// JPEG (ITU-T T.81) and PNG specifications; address oracles come from the
/// IANA IPv4 Special-Purpose Address Registry.
@Suite("Campaign E1 pass 2 mrkdwn resource contracts", .serialized)
struct AdversarialSetAMrkdwnResourceTests {
  @Test(arguments: Array(195...200))
  func resource(id: Int) throws {
    let inspector = ImageHeaderInspector()
    switch id {
    case 195:
      // SOI, then an APP1 segment whose payload holds a thumbnail SOF0
      // (1x1), then the primary SOF0 (300x200), then EOI.
      let thumbnailSOF: [UInt8] = [0xFF, 0xC0, 0x00, 0x0B, 8, 0, 1, 0, 1, 1, 1, 0x11, 0]
      let app1Payload = Array("Exif\0\0".utf8) + thumbnailSOF
      let app1: [UInt8] =
        [0xFF, 0xE1] + e1BigEndian16(app1Payload.count + 2) + app1Payload
      let sof0: [UInt8] =
        [0xFF, 0xC0, 0x00, 0x0B, 8] + e1BigEndian16(200) + e1BigEndian16(300) + [1, 1, 0x11, 0]
      let jpeg = Data([0xFF, 0xD8] + app1 + sof0 + [0xFF, 0xD9])
      #expect(
        try inspector.inspect(jpeg)
          == InspectedImage(format: .jpeg, dimensions: .init(width: 300, height: 200)))
    case 196:
      #expect(try inspector.inspect(e1PNG(width: 4_096, height: 4_096)).dimensions.width == 4_096)
      #expect(throws: ImageInspectionError.decodedImageTooLarge(4_096 * 4_097 * 4)) {
        try inspector.inspect(e1PNG(width: 4_096, height: 4_097))
      }
    case 197, 198:
      let url = try #require(
        URL(string: id == 197 ? "http://192.0.32.10/a.png" : "http://198.51.0.1/a.png"))
      // IANA IPv4 Special-Purpose Address Registry (RFC 6890, RFC 5737): the
      // reservations are /24s (STUI-1348, promoted by repair wave 4).
      try RemoteImageNetworkPolicy.validate(url)
      // The adjacent reservations themselves stay blocked.
      for reserved in [
        "http://192.0.2.1/a.png", "http://198.51.100.1/a.png", "http://192.0.0.8/a.png",
      ] {
        #expect(throws: ResourceLoadError.self) {
          try RemoteImageNetworkPolicy.validate(URL(string: reserved)!)
        }
      }
    case 199:
      #expect(throws: ResourceLoadError.self) {
        try RemoteImageNetworkPolicy.validate(URL(string: "https://[::ffff:10.0.0.1]/a.png")!)
      }
      try RemoteImageNetworkPolicy.validate(URL(string: "https://[2606:4700::1111]/a.png")!)
    default:
      let document = URL(fileURLWithPath: "/e1/doc.md")
      #expect(
        LinkResolver().resolve("notes#1.md", relativeTo: document)
          == .file(URL(fileURLWithPath: "/e1/notes")))
    }
  }
}

private func e1BigEndian16(_ value: Int) -> [UInt8] {
  [UInt8(truncatingIfNeeded: value >> 8), UInt8(truncatingIfNeeded: value)]
}

/// Signature plus an IHDR chunk; the inspector reads no further.
private func e1PNG(width: Int, height: Int) -> Data {
  let be32 = { (value: Int) in (0..<4).map { UInt8(truncatingIfNeeded: value >> (24 - 8 * $0)) } }
  return Data(
    [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A] + be32(13) + Array("IHDR".utf8) + be32(width)
      + be32(height) + [8, 6, 0, 0, 0] + [0, 0, 0, 0])
}
