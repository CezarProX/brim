# Contributing to Brim

Thanks for wanting to help. Brim is a small project, so the process is light.

## Before you start

- For anything bigger than a small fix, open an issue first so we can agree on the approach.
- Brim is a Swift Package with one external dependency: Sparkle, for signed in-app updates.
  Keep dependencies minimal; propose additional dependencies in an issue first.

## Building and testing

Requirements: macOS 14 or later to run; Xcode 26 or later to build (the Liquid Glass code needs the macOS 26 SDK).

```bash
swift build                          # debug build
swift test --no-parallel             # the full test suite (Swift Testing)
./build_app.sh                       # build/Brim.app with the pinned stable identity
open build/Brim.app
```

App bundles use the existing certificate pinned in `scripts/signing-policy.conf`; ad-hoc builds
are refused because their changing identity resets macOS privacy permissions. The protected signing
Keychain must be available before packaging. No identity is generated or changed automatically.
See [Releasing](docs/RELEASING.md) for the current self-signed distribution limits and signing tests.

Some tests render views and compare pixels, or need a display; if one of those fails on your
machine, mention it in the pull request rather than changing the threshold.

## Releases

See [docs/RELEASING.md](docs/RELEASING.md) for building and publishing the signed update feed.
Public and local bundles use the same pinned certificate. `BRIM_PUBLIC_RELEASE_ADHOC` and
`BRIM_ALLOW_ADHOC` are refused; no release can silently switch back to a changing ad-hoc identity.

## Pull requests

- One topic per pull request, with a short description of what changed and how you checked it.
- Add or update tests for behaviour changes and bug fixes (Swift Testing, in `Tests/BrimTests`).
- Every user-visible string goes into **both** `Resources/en.lproj/Localizable.strings` and
  `Resources/ro.lproj/Localizable.strings`; `LocalizationTests` enforces this.
- Match the style of the surrounding code. Keep files focused; split large ones.
- Commit messages use conventional prefixes: `feat:`, `fix:`, `refactor:`, `docs:`, `test:`, `chore:`.

## License

By contributing, you agree that your contributions are licensed under the
[GNU General Public License v3.0](LICENSE), the same license as the project.
