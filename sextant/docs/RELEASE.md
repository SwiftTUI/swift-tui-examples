# Release process

1. Run `Scripts/check.sh` from a clean checkout.
2. Store notarization credentials with `notarytool store-credentials`, then
   export the profile name and Developer ID identity:

   ```sh
   export NOTARY_KEYCHAIN_PROFILE=swift-tui-sextant
   export CODESIGN_IDENTITY="Developer ID Application: …"
   Scripts/package_release.sh 0.1.0
   ```

3. The packaging script builds separate macOS arm64 and x86_64 executables
   with the pinned Swift toolchain, applies hardened-runtime signatures,
   submits both archives to Apple, and writes `dist/SHA256SUMS`. Verify the
   unpacked artifacts on clean hosts with `codesign` and `spctl`.
4. Publish SHA-256 checksums and provenance with the GitHub release.
5. Update the `SwiftTUI/homebrew-tap` formula with the matching archive URLs
   and checksums.
6. Smoke install, help, version, completions, launch, preview, and uninstall on
   clean hosts before tagging the release final.

Sextant versions independently from the SwiftTUI framework.
