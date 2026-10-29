# Publishing Brim updates

Brim uses Sparkle 2.10.1 to install updates from GitHub Releases. The app reads
`https://github.com/CezarProX/brim/releases/latest/download/appcast.xml` and verifies downloaded
archives with the Ed25519 public key embedded in `Resources/Info.plist`. Updates replace the app
and relaunch it through Sparkle's installer. Publishing source changes to `main` alone does not
publish an update: users receive a new version after its signed release is published.

## Signing key

The release key is stored in the maintainer's login Keychain under Sparkle account `brim`.
It is separate from the Apple code-signing identity. Do not export it into the repository,
logs, shell arguments, release assets, or GitHub issues. Keep a secure backup of the Keychain.
Losing this key can prevent existing installations from accepting future updates.

For a new fork, create a key once with Sparkle's `generate_keys --account <fork-account>` tool,
then put only the public key into `SUPublicEDKey`. Do not replace Brim's key when preparing a
normal release. Sparkle's tools are downloaded by SwiftPM to
`.build/artifacts/sparkle/Sparkle/bin`.

## Prepare and inspect

1. Increase `CFBundleShortVersionString` and the monotonically increasing `CFBundleVersion` in
   `Resources/Info.plist`. Keep the updater public key and feed URL unchanged.
2. Run `swift test --no-parallel` and review the diff.
3. Commit the changes and push the exact release commit to `origin/main`.
4. Prepare artifacts using the matching version tag and a Markdown release-notes file:

   ```bash
   BRIM_PUBLIC_RELEASE_ADHOC=1 ./scripts/release.sh --notes /path/to/notes.md v1.0.1
   ```

The public build is currently ad-hoc signed and not notarized, like the initial release.
`BRIM_PUBLIC_RELEASE_ADHOC=1` explicitly selects that distribution identity. Normal development
builds continue to use an existing stable local or Apple Development identity so the release
process does not silently change local privacy identity. When a Developer ID certificate is
available, use `BRIM_SIGNING_IDENTITY` instead and notarize the app before distribution.

The script produces `build/releases/v1.0.1/Brim.dmg`, `appcast.xml`, `SHA256SUMS` and the release
notes. It verifies the built version, Keychain/public-key match, archive URL and length,
minimum macOS version, archive signature and signed appcast. No private key is exported.
The archive contains `Brim.app` and an `Applications` shortcut; Sparkle's framework, installer
and helper services are embedded and signed inside the app.

Inspect the app and the update UI before publishing. To repeat preparation, first move the
previous `build/releases/v<version>` folder aside; artifacts are not overwritten silently.
The `SPARKLE_TOOLS_DIR` environment variable can point to an extracted official Sparkle release's
`bin` directory when needed.

## Publish

To publish in one run after preparation has been reviewed, run the same command with
`--publish` (move the already prepared output directory aside first):

```bash
BRIM_PUBLIC_RELEASE_ADHOC=1 ./scripts/release.sh --notes /path/to/notes.md --publish v1.0.1
```

Publication requires a clean working tree and the exact commit already on `origin/main`.
The script creates the GitHub release/tag at that commit, attaches `Brim.dmg`, `appcast.xml`
and `SHA256SUMS`, and marks it latest. It refuses to overwrite an existing published release.
Alternatively upload those exact, already verified files with `gh release create`, using the
matching version tag and release commit. Do not edit an appcast after signing it.

Users with the updater can check from the island, menu bar or Settings and install without
opening GitHub or dragging the app into Applications again. The initial 1.0.0 release has no
installer, so its users need to download an updater-enabled release once. The app must be
copied out of the disk image into a writable Applications folder before it can update.

## References

- [Sparkle setup and signing](https://sparkle-project.org/documentation/)
- [Publishing an update](https://sparkle-project.org/documentation/publishing/)
- [Sparkle programmatic setup](https://sparkle-project.org/documentation/programmatic-setup/)
