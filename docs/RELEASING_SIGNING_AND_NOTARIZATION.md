# Release Signing & Notarization

This repository’s release workflow builds, codesigns, notarizes, staples, and uploads a macOS app when a tag like `v1.2.3` is pushed.

## Required GitHub Secrets

Configure these in **Settings → Secrets and variables → Actions**.

### Code signing

- `MACOS_CERT_P12` — Base64-encoded Developer ID Application certificate (.p12)
- `MACOS_CERT_PASSWORD` — Password for the .p12 file
- `MACOS_KEYCHAIN_PASSWORD` — Temporary keychain password (any strong value)
- `MACOS_CODE_SIGN_IDENTITY` — Full identity string (e.g., `Developer ID Application: Company Name (TEAMID)`)
- `MACOS_TEAM_ID` — Apple Developer Team ID

### Notarization (App Store Connect API key)

- `MACOS_NOTARY_KEY` — Base64-encoded App Store Connect API key (.p8)
- `MACOS_NOTARY_KEY_ID` — Key ID from App Store Connect
- `MACOS_NOTARY_ISSUER_ID` — Issuer ID from App Store Connect

## How to create the secrets

### Export and encode the signing certificate

1. In Keychain Access, export the **Developer ID Application** certificate as `.p12`.
2. Base64-encode it:

```
base64 -i path/to/certificate.p12 | pbcopy
```

3. Paste the clipboard into `MACOS_CERT_P12`.

### Encode the notarization key

1. Download the App Store Connect API key (.p8).
2. Base64-encode it:

```
base64 -i path/to/AuthKey_XXXXXXXXXX.p8 | pbcopy
```

3. Paste the clipboard into `MACOS_NOTARY_KEY`.

## Creating a release

This repo is set up so you can write your release notes/changelog in GitHub, and the CI workflow will upload the built artifacts to that release.

1. Create a GitHub Release first (draft or published) with your changelog.

2. Ensure the release tag exists (e.g. `v1.0.0`). When a matching tag is pushed, the workflow will build, sign, notarize, staple, and upload:

- `PodcastTransfer.dmg` (drag-and-drop installer)
- `PodcastTransfer.zip` (a zipped `.app`, useful for notarization/debugging)

If the workflow can’t find an existing GitHub Release for the tag, it will fail with instructions.

The DMG uses `docs/marketing/dmg.png` as its background image.

Note: `create-dmg` does not do Retina scaling for the background image. The background should match the configured `--window-size` in pixels (currently 660×440). If you want a higher-resolution source image for editing, keep `docs/marketing/dmg@2x.png` and downscale it to `dmg.png` for the actual DMG.

## Testing the release pipeline (recommended)

Before pushing a real tag, run the workflow manually:

1. Configure the required secrets (signing + notarization).
2. In GitHub Actions, run the **Release** workflow via **Run workflow**.
3. Download the produced artifacts (`PodcastTransfer.dmg` and `PodcastTransfer.zip`) from the workflow run.

Manual runs do not upload to a GitHub Release; they upload artifacts to the workflow run.

## Troubleshooting

If signing or notarization fails, the workflow prints:

- keychain and signing identities
- `codesign` details
- `spctl` assessment
- notary submission output and logs (when available)
