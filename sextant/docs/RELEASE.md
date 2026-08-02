# Release process

1. Run `Scripts/check.sh` from a clean checkout.
2. Store notarization credentials with `notarytool store-credentials`.
3. Run this command sequence with the profile name and Developer ID identity:

   ```sh
   export NOTARY_KEYCHAIN_PROFILE=swift-tui-sextant
   export CODESIGN_IDENTITY="Developer ID Application: …"
   Scripts/package_release.sh 0.1.0
   ```

4. Wait for the script to build arm64 and x86_64 executables with the pinned
   Swift toolchain.
5. Wait for the script to sign and submit both archives to Apple. The script
   also writes `dist/SHA256SUMS`.
6. Make sure that `codesign` and `spctl` accept the unpacked artifacts on clean
   hosts.
7. Publish SHA-256 checksums and provenance with the GitHub release.
8. Update the `SwiftTUI/homebrew-tap` formula with the matching archive URLs
   and checksums.
9. Run smoke checks for installation, help, version, completions, launch,
   preview, and uninstallation on clean hosts.
10. Tag the final release.

Sextant versions independently from the SwiftTUI framework.
