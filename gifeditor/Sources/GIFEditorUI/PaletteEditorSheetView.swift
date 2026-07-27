import Foundation
import GIFEditorCore
import SwiftTUI

/// Modal sheet for editing the document palette: pick a slot, retype its
/// colour as hex or as three channels, add and remove slots, sort or
/// compact the whole thing, or replace it from a Lospec `.hex` / GIMP
/// `.gpl` file.
///
/// Every action here calls straight through to `EditorViewModel`, so each
/// one is a single undoable edit that has already remapped every
/// `PaletteIndex` in the document. The sheet holds no copy of the
/// palette — it renders `model.document.palette` — so an undo taken from
/// under it (or a status line it did not write) shows up immediately.
///
/// Hex and RGB are deliberately *two* commit paths with their own
/// buttons rather than one pair of mirrored fields. Cross-syncing them
/// rewrites the field the author is mid-way through typing; two buttons
/// cost one extra click and never surprise anyone.
struct PaletteEditorSheetView: View {
  let model: EditorViewModel
  let refresh: @MainActor @Sendable () -> Void
  let onClose: @MainActor @Sendable () -> Void

  @State private var selectedSlot: Int = 0
  @State private var hexText: String = ""
  @State private var redText: String = ""
  @State private var greenText: String = ""
  @State private var blueText: String = ""
  @State private var importPath: String = ""

  /// Swatches per grid row, and rows per page. 16 × 8 shows a full
  /// 128-colour palette without scrolling; a 256-slot palette pages.
  private static let columns = 16
  private static let rowsPerPage = 8
  private static var slotsPerPage: Int { columns * rowsPerPage }

  var body: some View {
    let palette = model.document.palette
    let slot = clampedSlot(in: palette)
    return VStack(alignment: .leading, spacing: 0) {
      Text("\(palette.usedCount) of \(ColorPalette.capacity) slots in use")
        .foregroundStyle(.muted)
      grid(palette: palette, selected: slot)
      Divider()
      slotEditor(palette: palette, slot: slot)
      Divider()
      structureActions(palette: palette, slot: slot)
      importRow
      Divider()
      HStack(spacing: 1) {
        Text(model.statusMessage).foregroundStyle(.muted)
        Spacer(minLength: 1)
        Button("Close", action: onClose)
          .systemHint("Esc")
      }
    }
    .padding(1)
    .onAppear {
      selectedSlot = Int(model.primaryColorIndex)
      loadFields(from: model.document.palette)
    }
  }

  // MARK: - Slot grid

  private func grid(palette: ColorPalette, selected: Int) -> some View {
    let page = selected / Self.slotsPerPage
    let first = page * Self.slotsPerPage
    let last = min(palette.usedCount, first + Self.slotsPerPage)
    let rows = max(1, (last - first + Self.columns - 1) / Self.columns)
    return VStack(alignment: .leading, spacing: 0) {
      if palette.usedCount > Self.slotsPerPage {
        Text("Slots \(first)–\(last - 1) of \(palette.usedCount)")
          .foregroundStyle(.separator)
      }
      ForEach(0..<rows, id: \.self) { row in
        HStack(spacing: 0) {
          ForEach(0..<Self.columns, id: \.self) { column in
            swatch(at: first + row * Self.columns + column, palette: palette, selected: selected)
          }
        }
      }
    }
  }

  @ViewBuilder
  private func swatch(at index: Int, palette: ColorPalette, selected: Int) -> some View {
    if index < palette.usedCount {
      Button {
        select(index, in: palette)
      } label: {
        ZStack(alignment: .leading) {
          Rectangle()
            .fill(palette[PaletteIndex(index)].toTerminalColor())
            .frame(width: 2, height: 1)
          Text(index == selected ? "▮" : " ")
            .foregroundStyle(.foreground)
        }
      }
      .buttonStyle(.plain)
    } else {
      Text("  ").foregroundStyle(.separator)
    }
  }

  // MARK: - Selected slot

  private func slotEditor(palette: ColorPalette, slot: Int) -> some View {
    let color = palette[PaletteIndex(slot)]
    return VStack(alignment: .leading, spacing: 0) {
      HStack(spacing: 1) {
        Button("‹") { select(slot - 1, in: palette) }
          .buttonStyle(.plain)
          .disabled(slot == 0)
        Text("Slot \(slot)").foregroundStyle(.foreground)
        Button("›") { select(slot + 1, in: palette) }
          .buttonStyle(.plain)
          .disabled(slot >= palette.usedCount - 1)
        Rectangle()
          .fill(color.toTerminalColor())
          .frame(width: 4, height: 1)
        Text(slot == Int(ColorPalette.transparentSlot) ? "transparency sentinel" : "")
          .foregroundStyle(.muted)
      }
      HStack(spacing: 1) {
        Text("Hex").foregroundStyle(.muted)
        TextField("RRGGBB", text: $hexText)
          .textFieldStyle(.plain)
          .frame(width: 8, alignment: .leading)
        Button("Apply hex") {
          guard let parsed = Self.color(fromHex: hexText) else {
            model.announce("Hex needs six digits, e.g. FF8800")
            refresh()
            return
          }
          model.setPaletteColor(parsed, at: PaletteIndex(slot))
          loadFields(from: model.document.palette)
          refresh()
        }
        .disabled(Self.color(fromHex: hexText) == nil)
      }
      HStack(spacing: 1) {
        channelField("R", text: $redText)
        channelField("G", text: $greenText)
        channelField("B", text: $blueText)
        Button("Apply RGB") {
          guard let parsed = Self.color(red: redText, green: greenText, blue: blueText) else {
            model.announce("Each channel needs a whole number in 0–255")
            refresh()
            return
          }
          model.setPaletteColor(parsed, at: PaletteIndex(slot))
          loadFields(from: model.document.palette)
          refresh()
        }
        .disabled(Self.color(red: redText, green: greenText, blue: blueText) == nil)
      }
    }
  }

  private func channelField(_ label: String, text: Binding<String>) -> some View {
    HStack(spacing: 0) {
      Text(label).foregroundStyle(.muted)
      TextField(label, text: text)
        .textFieldStyle(.plain)
        .frame(width: 5, alignment: .leading)
    }
  }

  // MARK: - Structural actions

  private func structureActions(palette: ColorPalette, slot: Int) -> some View {
    HStack(spacing: 1) {
      Button("Add") {
        model.appendPaletteColor(Self.color(fromHex: hexText) ?? .black)
        select(Int(model.primaryColorIndex), in: model.document.palette)
        refresh()
      }
      .disabled(palette.usedCount >= ColorPalette.capacity)
      Button("Remove") {
        model.removePaletteSlot(at: PaletteIndex(slot))
        select(min(slot, model.document.palette.usedCount - 1), in: model.document.palette)
        refresh()
      }
      .disabled(slot == Int(ColorPalette.transparentSlot) || palette.usedCount <= 1)
      Button("Sort") {
        model.sortPalette()
        loadFields(from: model.document.palette)
        refresh()
      }
      Button("Compact") {
        model.compactPalette()
        select(min(slot, model.document.palette.usedCount - 1), in: model.document.palette)
        refresh()
      }
    }
  }

  private var importRow: some View {
    HStack(spacing: 1) {
      Text("Import").foregroundStyle(.muted)
      TextField("path.hex or path.gpl", text: $importPath)
        .textFieldStyle(.plain)
        .frame(width: 34, alignment: .leading)
      Button("Load") {
        if model.importPalette(fromPath: importPath) {
          select(Int(model.primaryColorIndex), in: model.document.palette)
        }
        refresh()
      }
    }
  }

  // MARK: - Selection & field sync

  /// Keeps the rendered selection inside the palette even when an edit
  /// made elsewhere (an undo, a compact) shortened it under the sheet.
  private func clampedSlot(in palette: ColorPalette) -> Int {
    min(max(0, selectedSlot), palette.usedCount - 1)
  }

  private func select(_ index: Int, in palette: ColorPalette) {
    let clamped = min(max(0, index), palette.usedCount - 1)
    selectedSlot = clamped
    loadFields(from: palette)
  }

  /// Refills the hex and channel fields from the selected slot. Called
  /// whenever the selection moves or an action rewrites the palette, so
  /// the fields always describe what the swatch shows.
  private func loadFields(from palette: ColorPalette) {
    let color = palette[PaletteIndex(clampedSlot(in: palette))]
    hexText = EditorViewModel.hexLabel(for: color)
    redText = String(color.red)
    greenText = String(color.green)
    blueText = String(color.blue)
  }

  // MARK: - Parsing

  /// `RRGGBB`, with an optional leading `#`.
  ///
  /// Exactly six digits: eight-digit `RRGGBBAA` is rejected rather than
  /// truncated, matching `PaletteImport.lospecHex` — an accidental alpha
  /// must not silently rewrite a slot's opacity.
  static func color(fromHex text: String) -> EditorColor? {
    var digits = text.trimmingCharacters(in: .whitespaces)
    if digits.hasPrefix("#") {
      digits.removeFirst()
    }
    guard digits.count == 6, let value = UInt32(digits, radix: 16) else { return nil }
    return EditorColor(rgbHex: value)
  }

  /// Three decimal channels in `0...255`. Alpha is not offered: only
  /// slot 0 is transparent, and it is pinned.
  static func color(red: String, green: String, blue: String) -> EditorColor? {
    guard
      let r = channel(red),
      let g = channel(green),
      let b = channel(blue)
    else { return nil }
    return EditorColor(red: r, green: g, blue: b)
  }

  private static func channel(_ text: String) -> UInt8? {
    guard let value = Int(text.trimmingCharacters(in: .whitespaces)),
      (0...255).contains(value)
    else { return nil }
    return UInt8(value)
  }
}
