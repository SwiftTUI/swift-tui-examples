public import Foundation

public struct ImageDimensions: Equatable, Hashable, Sendable {
  public var width: Int
  public var height: Int

  public init(width: Int, height: Int) {
    self.width = width
    self.height = height
  }

  public var decodedRGBABytes: Int? {
    let (pixels, pixelOverflow) = width.multipliedReportingOverflow(by: height)
    guard !pixelOverflow else { return nil }
    let (bytes, byteOverflow) = pixels.multipliedReportingOverflow(by: 4)
    return byteOverflow ? nil : bytes
  }
}

public enum InspectedImageFormat: Equatable, Hashable, Sendable {
  case png
  case jpeg
}

public struct InspectedImage: Equatable, Hashable, Sendable {
  public var format: InspectedImageFormat
  public var dimensions: ImageDimensions
}

public enum ImageInspectionError: Error, Equatable, Sendable, LocalizedError {
  case unsupportedFormat
  case truncated
  case invalidDimensions(width: Int, height: Int)
  case decodedImageTooLarge(Int?)

  public var errorDescription: String? {
    switch self {
    case .unsupportedFormat:
      "only PNG and JPEG images are supported"
    case .truncated:
      "image header is truncated or malformed"
    case .invalidDimensions(let width, let height):
      "image dimensions \(width)×\(height) are outside 1...8192"
    case .decodedImageTooLarge(let bytes):
      "decoded image requires \(bytes.map(String.init) ?? "an overflowing number of") bytes; maximum is 64 MiB"
    }
  }
}

public struct ImageHeaderInspector: Sendable {
  public static let maximumDimension = 8_192
  public static let maximumDecodedBytes = 64 * 1_024 * 1_024

  public init() {}

  public func inspect(_ data: Data) throws -> InspectedImage {
    let bytes = [UInt8](data)
    let image: InspectedImage
    if bytes.starts(with: [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]) {
      image = try inspectPNG(bytes)
    } else if bytes.starts(with: [0xFF, 0xD8]) {
      image = try inspectJPEG(bytes)
    } else {
      throw ImageInspectionError.unsupportedFormat
    }
    try validate(image.dimensions)
    return image
  }

  private func inspectPNG(_ bytes: [UInt8]) throws -> InspectedImage {
    guard bytes.count >= 24,
      bytes[12...15].elementsEqual([0x49, 0x48, 0x44, 0x52])
    else {
      throw ImageInspectionError.truncated
    }
    let width = int32(bytes, at: 16)
    let height = int32(bytes, at: 20)
    return InspectedImage(
      format: .png,
      dimensions: ImageDimensions(width: width, height: height)
    )
  }

  private func inspectJPEG(_ bytes: [UInt8]) throws -> InspectedImage {
    let startOfFrame: Set<UInt8> = [
      0xC0, 0xC1, 0xC2, 0xC3, 0xC5, 0xC6, 0xC7,
      0xC9, 0xCA, 0xCB, 0xCD, 0xCE, 0xCF,
    ]
    var index = 2
    while index + 3 < bytes.count {
      while index < bytes.count, bytes[index] != 0xFF { index += 1 }
      while index < bytes.count, bytes[index] == 0xFF { index += 1 }
      guard index < bytes.count else { break }
      let marker = bytes[index]
      index += 1
      if marker == 0xD9 || marker == 0xDA { break }
      if marker == 0x01 || (0xD0...0xD7).contains(marker) { continue }
      guard index + 1 < bytes.count else { throw ImageInspectionError.truncated }
      let length = Int(bytes[index]) << 8 | Int(bytes[index + 1])
      guard length >= 2, index <= bytes.count - length else {
        throw ImageInspectionError.truncated
      }
      if startOfFrame.contains(marker) {
        guard length >= 7 else { throw ImageInspectionError.truncated }
        let height = Int(bytes[index + 3]) << 8 | Int(bytes[index + 4])
        let width = Int(bytes[index + 5]) << 8 | Int(bytes[index + 6])
        return InspectedImage(
          format: .jpeg,
          dimensions: ImageDimensions(width: width, height: height)
        )
      }
      index += length
    }
    throw ImageInspectionError.truncated
  }

  private func validate(_ dimensions: ImageDimensions) throws {
    guard (1...Self.maximumDimension).contains(dimensions.width),
      (1...Self.maximumDimension).contains(dimensions.height)
    else {
      throw ImageInspectionError.invalidDimensions(
        width: dimensions.width,
        height: dimensions.height
      )
    }
    guard let bytes = dimensions.decodedRGBABytes, bytes <= Self.maximumDecodedBytes else {
      throw ImageInspectionError.decodedImageTooLarge(dimensions.decodedRGBABytes)
    }
  }

  private func int32(_ bytes: [UInt8], at offset: Int) -> Int {
    Int(bytes[offset]) << 24
      | Int(bytes[offset + 1]) << 16
      | Int(bytes[offset + 2]) << 8
      | Int(bytes[offset + 3])
  }
}
