# AGENTS.md

Sextant is a read-only, preview-first terminal inspector.

- Use `swiftly run swift`. `.swift-version` pins the toolchain.
- Run `Scripts/check.sh` before publishing.
- `BrowserModel.send` is the semantic interface. Views render state and send
  actions. They do not own filesystem, preview, search, or handoff effects.
- Keep filesystem work typed, bounded, cancellable, and generation-safe.
- Public dependencies use tagged HTTPS URLs. Untagged cross-repo integration
  belongs in the SwiftTUI coordination root.
- `docs/` describes `HEAD`. Future plans live in the coordination root.
