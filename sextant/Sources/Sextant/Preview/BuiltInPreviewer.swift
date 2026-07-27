import Foundation

struct BuiltInPreviewer: Sendable {
  private let fileSystem: any FileSystemClient
  private let formatter: BuiltInPreviewFormatter

  init(
    fileSystem: any FileSystemClient,
    formatter: BuiltInPreviewFormatter = BuiltInPreviewFormatter()
  ) {
    self.fileSystem = fileSystem
    self.formatter = formatter
  }

  func preview(
    item: BrowserItem,
    directorySnapshot: DirectorySnapshot? = nil
  ) async -> BuiltInPreview {
    let metadataResult = await fileSystem.metadata(
      at: item.url,
      followingSymbolicLinks: true
    )
    let metadata =
      switch metadataResult {
      case .success(let metadata):
        metadata
      case .failure:
        item.listingMetadata
      }
    let previewMetadata = PreviewMetadata(
      displayName: sanitizedDisplayName(item.name),
      path: item.url.path,
      kind: kindLabel(item.kind),
      size: metadata.byteCount,
      modificationDate: metadata.modificationDate
    )

    switch item.kind {
    case .directory, .symbolicLinkToDirectory, .package:
      guard let directorySnapshot else {
        return BuiltInPreview(
          metadata: previewMetadata,
          body: .metadataOnly
        )
      }
      return BuiltInPreview(
        metadata: previewMetadata,
        body: .directorySummary(summary(directorySnapshot))
      )

    case .special, .symbolicLinkToSpecial:
      return BuiltInPreview(
        metadata: previewMetadata,
        body: .unavailable(.specialFile)
      )

    case .brokenSymbolicLink:
      return BuiltInPreview(
        metadata: previewMetadata,
        body: .unavailable(.unsupported("Broken symbolic link"))
      )

    case .file, .symbolicLinkToFile:
      let prefix = await fileSystem.readPrefix(
        at: item.url,
        maximumBytes: BuiltInPreviewFormatter.requestedReadBytes
      )
      switch prefix {
      case .success(let prefix):
        return BuiltInPreview(
          metadata: previewMetadata,
          body: formatter.format(prefix: prefix)
        )
      case .failure(let failure):
        return BuiltInPreview(
          metadata: previewMetadata,
          body: .failed(previewFailure(failure))
        )
      }
    }
  }

  private func summary(_ snapshot: DirectorySnapshot) -> DirectorySummary {
    var directories = 0
    var files = 0
    var special = 0
    var bytes: UInt64 = 0
    for item in snapshot.items {
      switch item.kind {
      case .directory, .symbolicLinkToDirectory, .package:
        directories += 1
      case .file, .symbolicLinkToFile:
        files += 1
      case .symbolicLinkToSpecial, .brokenSymbolicLink, .special:
        special += 1
      }
      bytes &+= item.listingMetadata.byteCount ?? 0
    }
    return DirectorySummary(
      itemCount: snapshot.items.count,
      directoryCount: directories,
      fileCount: files,
      specialCount: special,
      totalKnownBytes: bytes
    )
  }

  private func previewFailure(_ failure: FileSystemFailure) -> PreviewFailure {
    switch failure {
    case .permissionDenied:
      .permissionDenied
    case .notFound, .stale:
      .missing
    case .cancelled:
      .unreadable("Preview cancelled")
    case .superseded:
      .unreadable("Preview superseded")
    case .notDirectory, .unsupported, .io:
      .unreadable(failure.description)
    }
  }

  private func kindLabel(_ kind: BrowserItemKind) -> String {
    switch kind {
    case .file:
      "File"
    case .directory:
      "Directory"
    case .symbolicLinkToFile:
      "Symbolic link to file"
    case .symbolicLinkToDirectory:
      "Symbolic link to directory"
    case .symbolicLinkToSpecial(let kind):
      "Symbolic link to \(specialKindLabel(kind))"
    case .brokenSymbolicLink:
      "Broken symbolic link"
    case .package:
      "Package"
    case .special(let kind):
      specialKindLabel(kind)
    }
  }

  private func specialKindLabel(_ kind: SpecialFileKind) -> String {
    switch kind {
    case .fifo:
      "FIFO"
    case .socket:
      "Socket"
    case .characterDevice:
      "Character device"
    case .blockDevice:
      "Block device"
    case .other:
      "Special file"
    }
  }

  private func sanitizedDisplayName(_ name: String) -> String {
    name.unicodeScalars.map { scalar in
      if CharacterSet.controlCharacters.contains(scalar) {
        return "�"
      }
      return String(scalar)
    }.joined()
  }
}
