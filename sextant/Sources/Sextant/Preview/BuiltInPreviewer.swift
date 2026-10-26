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
    let listed = snapshot.items.prefix(DirectorySummary.listedEntryLimit)
    return DirectorySummary(
      itemCount: snapshot.items.count,
      directoryCount: directories,
      fileCount: files,
      specialCount: special,
      totalKnownBytes: bytes,
      entryNames: listed.map {
        sanitizedDisplayName($0.name) + ($0.kind.isDirectoryLike ? "/" : "")
      },
      hiddenEntryCount: snapshot.items.count - listed.count
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

  /// Replaces terminal and format controls with U+FFFD, keeping the joiners
  /// and tag characters that belong to emoji sequences.
  ///
  /// Every Cc scalar is replaced. A Cf scalar (bidi controls, invisible
  /// separators, ZWJ, tags, ...) is replaced unless it is part of an emoji
  /// sequence (UTS #51): a ZWJ between an emoji element and an emoji
  /// (section 2.3), or a run of tag characters U+E0020-E007E that follows an
  /// emoji element and ends in U+E007F (ED-14a). Variation selectors and
  /// skin-tone modifiers are not Cf and are always kept.
  private func sanitizedDisplayName(_ name: String) -> String {
    let scalars = Array(name.unicodeScalars)
    var kept = String.UnicodeScalarView()
    var index = 0
    while index < scalars.count {
      let scalar = scalars[index]
      if tagCharacters.contains(scalar.value) || scalar.value == cancelTag {
        var end = index
        while end < scalars.count, tagCharacters.contains(scalars[end].value) {
          end += 1
        }
        let isTagSequence =
          end > index && end < scalars.count && scalars[end].value == cancelTag
          && index > 0 && endsEmojiElement(scalars[index - 1])
        let runEnd = end < scalars.count && scalars[end].value == cancelTag ? end + 1 : end
        for tag in scalars[index..<runEnd] {
          kept.append(isTagSequence ? tag : replacementCharacter)
        }
        index = runEnd
        continue
      }
      switch scalar.properties.generalCategory {
      case .control:
        kept.append(replacementCharacter)
      case .format:
        let joinsEmoji =
          scalar.value == zeroWidthJoiner
          && index > 0 && endsEmojiElement(scalars[index - 1])
          && index + 1 < scalars.count && isEmoji(scalars[index + 1])
        kept.append(joinsEmoji ? scalar : replacementCharacter)
      default:
        kept.append(scalar)
      }
      index += 1
    }
    return String(kept)
  }
}

private let replacementCharacter: Unicode.Scalar = "\u{FFFD}"
private let zeroWidthJoiner: UInt32 = 0x200D
private let tagCharacters: ClosedRange<UInt32> = 0xE0020...0xE007E
private let cancelTag: UInt32 = 0xE007F

/// An emoji character outside ASCII: `#`, `*` and the digits have the Emoji
/// property only as keycap bases, and never join with ZWJ.
private func isEmoji(_ scalar: Unicode.Scalar) -> Bool {
  scalar.value > 0x7F && scalar.properties.isEmoji
}

/// Whether `scalar` can end an emoji element: an emoji (skin-tone modifiers
/// included), the emoji presentation selector U+FE0F, or the end of a tag
/// sequence.
private func endsEmojiElement(_ scalar: Unicode.Scalar) -> Bool {
  isEmoji(scalar) || scalar.value == 0xFE0F || scalar.value == cancelTag
}
