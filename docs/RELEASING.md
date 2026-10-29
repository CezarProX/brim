# Publishing Brim updates

Brim uses Sparkle to install signed updates from GitHub Releases. Source pushes alone do not
publish an update. The app reads the signed `appcast.xml` attached to the latest release and
verifies archives with the Ed25519 public key in `Resources/Info.plist` before extraction.

## Two independent signatures

The Sparkle Ed25519 key authenticates the update archive and feed. It does not preserve macOS
privacy permissions by itself. Those permissions depend on the application's code-signing
identity and designated requirement (DR).

`scripts/signing-policy.conf` pins Brim's bundle ID and the SHA-1 fingerprint of its existing
code-signing certificate. The fingerprint is public; the private key stays in the maintainer's
isolated Keychain. Every application is signed with the exact requirement:

```
identifier "io.github.cezarprox.brim" and certificate leaf = H"574d221fc8ec86933d704232bfce12f78ca193cb"
```

The build and release scripts fail if the certificate is missing, expired, has changed, or an
ad-hoc signing flag is requested. They never create a new identity or silently select another
Apple certificate. Exact DR equality lets different versions signed by the same certificate
satisfy each other's identity requirement even though their binary hashes differ.

Releases up to 1.0.4 were ad-hoc signed: their DR changed with each binary. Moving from one of
those releases to the stable certificate may require one final permission grant. After that,
updates using this same bundle ID and certificate retain the same code identity. macOS still
owns permission decisions; do not edit TCC databases or system certificate trust to force them.

## Distribution status

The current persistent certificate is self-signed. Brim remains unnotarized and is not an
Apple-verified Developer ID application. First installation can still require **Open Anyway**
in System Settings → Privacy & Security. Apple recommends Developer ID signing and notarization
for public distribution; this stable certificate addresses identity continuity, not Gatekeeper
trust or notarization.

Current public binaries did not enable Hardened Runtime. The self-signed channel retains that
baseline because Sparkle's dynamic framework cannot rely on an Apple-issued Team ID here.
No library-validation bypass entitlement or global trust change is added. A future Apple-issued
signing channel is a deliberate migration: update the pinned certificate, import that identity
into the protected signing Keychain and use `BRIM_APPLE_SIGNING=1`, which enables Hardened Runtime
and requires an Apple trust anchor. Do not use this switch with the self-signed certificate.

## Keep both private keys safe

The code-signing identity is stored in:

```
~/Library/Application Support/Brim/DevelopmentSigning/
```

That directory must be a real directory with mode `700`. Its `certificate.der`,
`signing.keychain-db` and `keychain-password` files must be regular, non-symlink files with mode
`600`. `BRIM_LOCAL_SIGNING_DIR` may point to the same protected identity in another location;
the pinned fingerprint must still match. The scripts temporarily unlock and add that Keychain
for signing, then lock it and remove only their own search-list addition.

The separate Sparkle release key stays in the login Keychain under account `brim`. Never export
either private key into the repository, logs, shell arguments, artifacts or GitHub secrets.
Keep a secure Keychain backup: losing a signing key can break update continuity.

## Build and verify

For a normal bundle, run:

```bash
./build_app.sh
./scripts/sign_app.sh --verify build/Brim.app
```

To re-sign an existing pristine app without compiling source, use:

```bash
./scripts/sign_app.sh /path/to/Brim.app
./scripts/sign_app.sh --verify /path/to/Brim.app
```

The helper signs Sparkle's nested executable, updater, XPC helpers and framework from the inside
out, preserving helper entitlements. Brim's entitlements apply only to the outer application.
`--bundle-id ID` supports explicitly named isolated test harnesses; normal builds and release
verification always enforce the production ID from the signing policy.

Run the fail-closed signing checks with `./tests/scripts/test_signing.sh`. Before changing the
signing channel, also test reciprocal DR checks between genuinely different binaries, rejection
of an ad-hoc or differently signed app, a real app launch, and Sparkle install/relaunch.

## Prepare and publish

1. Increment `CFBundleShortVersionString` and `CFBundleVersion` in `Resources/Info.plist` and update
   README's version badge/current-release text. Preserve the signer policy and updater public key.
2. Run the relevant tests, inspect the diff, commit, and push the exact release commit to `origin/main`.
3. Prepare artifacts using the matching version and a release-notes file:

   ```bash
   ./scripts/release.sh --notes /path/to/notes.md v1.0.5
   ```

The output is `build/releases/v1.0.5/Brim.dmg`, the signed `appcast.xml`, `SHA256SUMS` and notes.
The script verifies the code-signing policy before packaging, the bundle version, Sparkle key,
archive URL/length/minimum macOS version, and the archive and feed signatures.

Review those artifacts before publishing. To prepare and publish in one run, use `--publish`
(move any previously prepared output directory aside first):

```bash
./scripts/release.sh --notes /path/to/notes.md --publish v1.0.5
```

Publication requires a clean working tree and the exact commit already on `origin/main`.
Existing public releases are immutable. Alternatively upload those same verified artifacts with
`gh release create` at the full release commit SHA. Do not edit an appcast after signing it.

Users with Sparkle update from the island, menu bar or Settings. The initial 1.0.0 release has no
installer and needs one manual upgrade. Install into a writable location outside the disk image.

## References

- [Apple: code-signing requirements and identity](https://developer.apple.com/documentation/technotes/tn3127-inside-code-signing-requirements)
- [Apple: code-signing procedures and self-signed certificates](https://developer.apple.com/library/archive/documentation/Security/Conceptual/CodeSigningGuide/Procedures/Procedures.html)
- [Sparkle setup and signing](https://sparkle-project.org/documentation/)
