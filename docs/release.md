# Release Guide

PrintScreen is distributed outside the App Store as a Developer ID-signed, Apple-notarized `.zip` on [GitHub Releases](https://github.com/morishin/printscreen/releases).

## How it works

Pushing a `v*` tag runs [`.github/workflows/release.yml`](../.github/workflows/release.yml) on a GitHub-hosted `macos-26` runner:

1. Import the Developer ID certificate into a temporary keychain.
2. Archive the Release build with Hardened Runtime and a secure timestamp.
3. Export it with [`ExportOptions.plist`](../ExportOptions.plist).
4. Submit it for notarization and staple the ticket.
5. Create a GitHub Release with `PrintScreen.zip` attached.

The About tab compares the app version with the latest release through the redirect of `https://github.com/morishin/printscreen/releases/latest`. This only works while the repository is public.

## Prerequisites

- Apple Developer Program membership (Team ID `4GERXBURZN`)
- A **Developer ID Application** certificate and its private key

## GitHub Secrets

Register these under **Settings → Secrets and variables → Actions**. GitHub does not pass them to pull requests from forks.

| Secret | Content | How to create |
|---|---|---|
| `BUILD_CERTIFICATE_BASE64` | Base64-encoded Developer ID Application `.p12` | Export it from Keychain Access, then run `base64 -i cert.p12 \| pbcopy` |
| `P12_PASSWORD` | Password of the `.p12` | Set in the export dialog |
| `KEYCHAIN_PASSWORD` | Password of the temporary CI keychain | Any random string |
| `APPLE_ID` | Apple ID used for notarization | Developer account email |
| `APPLE_APP_PASSWORD` | App-specific password | [appleid.apple.com](https://appleid.apple.com) → Sign-In and Security → App-Specific Passwords |
| `APPLE_TEAM_ID` | Team ID | `4GERXBURZN` |

## Releasing

```sh
git switch main && git pull
git tag v1.0
git push origin v1.0
```

Watch the `Release` workflow in the **Actions** tab, then confirm that `PrintScreen.zip` is attached to the release.

The workflow sets `MARKETING_VERSION` from the tag (`v1.2` → `1.2`) and `CURRENT_PROJECT_VERSION` from the run number, so `project.pbxproj` does not need a version bump.

## Verifying a release

Download the zip, extract it outside the build directory, and check:

```sh
spctl -a -vv -t exec PrintScreen.app
xcrun stapler validate PrintScreen.app
```

Then launch it and confirm that screenshots, recording, and WebM conversion work.

## Troubleshooting

- **Signing fails:** The certificate may be expired, or its private key may be missing. Check with `security find-identity -v -p codesigning`.
- **Notarization returns `Invalid`:** Read the log.
  ```sh
  xcrun notarytool log <submission-id> --apple-id "$APPLE_ID" \
    --password "$APPLE_APP_PASSWORD" --team-id 4GERXBURZN
  ```
- **`macos-26` runner not found:** Check [actions/runner-images](https://github.com/actions/runner-images) and update `runs-on`.
- **The app does not detect an update:** Confirm the repository is public and the release tag has the `vX.Y` format.
