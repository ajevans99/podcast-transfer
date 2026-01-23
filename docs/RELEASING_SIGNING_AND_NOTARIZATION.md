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

1. Push a tag matching `v*`:

```
git tag v1.0.0
git push origin v1.0.0
```

2. The workflow will build, sign, notarize, staple, and attach `PodcastTransfer.zip` to the GitHub Release.

## Troubleshooting

If signing or notarization fails, the workflow prints:

- keychain and signing identities
- `codesign` details
- `spctl` assessment
- notary submission output and logs (when available)
