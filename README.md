# Teleport Bread

A triage surface over Apple Reminders. See `AGENTS.md` for the product idea and vocabulary, `make help` for the build targets.

## Releasing

There are two Mac channels built from the same code. iOS ships through TestFlight and the App Store as usual.

### Direct download (teleportbread.com)

Fully automated. From a clean `main`:

```bash
git tag v1.2.0
git push origin v1.2.0
```

That triggers `.github/workflows/release-direct.yml`, which:

1. archives the `TeleportBreadMacDirect` target with the Developer ID certificate,
2. notarizes and staples it with Apple,
3. signs the zip for Sparkle and appends it to `website/public/appcast.xml`,
4. publishes a GitHub Release with the zip,
5. commits the appcast to `main`, which Railway deploys to teleportbread.com.

Automatic checks are on by default: once at launch and once a day after that. Users can turn them off in Settings or use "Check for Updates…" at any time. Watch a run with `gh run watch`.

Version numbers come from the tag. The build number is the workflow run number and must only go up, so never delete and recreate a tag after a release has shipped.

### Mac App Store

Manual, through Xcode:

1. Open `app/TeleportBread.xcodeproj` (run `make gen` first if it is missing).
2. Set `MARKETING_VERSION` to the release version and increment `CURRENT_PROJECT_VERSION` in `app/project.yml`, then run `make gen`.
3. Select the `TeleportBreadMac` scheme, then Product → Archive.
4. In Organizer: Distribute App → App Store Connect → Upload.
5. On appstoreconnect.apple.com, create the new macOS version, attach the build, fill in what's new, and submit for review.

This target never contains Sparkle. Apple delivers its updates.

### iOS / TestFlight

One click. Run the "TestFlight (iOS)" workflow from the Actions tab or:

```bash
gh workflow run testflight.yml
```

`.github/workflows/testflight.yml` archives the `TeleportBread` target with the Apple Distribution certificate and uploads it to App Store Connect, which processes it into TestFlight. The version is `MARKETING_VERSION` from `app/project.yml` (override with the `version` input); the build number is the UTC minute of the upload, so it always goes up. Signing is manual with the Apple Distribution certificate and the "TeleportBread iOS App Store" profile, which xcodebuild downloads from App Store Connect on demand, so no profile lives in the repo.

Locally, `scripts/release-ios.sh <version> $(date -u +%Y%m%d%H%M) dist` does the same with `ASC_KEY_ID`, `ASC_ISSUER_ID` and `ASC_KEY_PATH` set and the distribution certificate in the keychain.

### Minimum supported versions

`website/public/app-version.json` is deployed to teleportbread.com with the site. Each native app fetches it at launch and then at most once a day (on foreground return or from a daily timer), with no retry. An unavailable or invalid file leaves the app usable.

The `ios` and `mac` entries each specify `minimum`, `latest`, an optional `store` URL, and an optional `message` explaining a required update. iOS also has a `testflight` URL. The Mac entry gets a `store` URL once the Mac App Store page exists; until then its Update button falls back to teleportbread.com.

To require an update, first make the replacement available through the affected stores and the Mac direct appcast, then bump that platform's `minimum` (and `latest` if needed), and commit the file to `main`. The site deployment makes the gate effective on the next app launch. Keep `latest` at least as high as `minimum`; bumping only `latest` shows a dismissable iOS banner. The Mac entry applies to both Mac channels.

The gate reads `CFBundleShortVersionString`, so `MARKETING_VERSION` must match the version being shipped. Builds predating the gate cannot enforce it. Debug builds can use `TELEPORTBREAD_VERSION_URL` to fetch a local policy for testing.

### Secrets and keys

The workflows need these repository secrets: `DEVELOPER_ID_P12_BASE64`, `DEVELOPER_ID_P12_PASSWORD`, `NOTARY_KEY_ID`, `NOTARY_ISSUER_ID`, `NOTARY_KEY_P8`, `SPARKLE_PRIVATE_KEY`, and for TestFlight `APPLE_DISTRIBUTION_P12_BASE64`, `APPLE_DISTRIBUTION_P12_PASSWORD`, `ASC_KEY_ID`, `ASC_ISSUER_ID`, `ASC_KEY_P8`. The `ASC_*` key has the Admin role so it can mint provisioning profiles; the notary key does not. Backups of the underlying files, plus the API key id and issuer id, are in Ev's iCloud Drive under `Documents/Business/Personal/codes/teleport-bread-release`.

The Sparkle private key is the one thing that cannot be rotated quietly: every shipped app trusts it. Guard it.

### Rehearsing an update locally

Build two versions of the Direct target, zip the newer one, run `scripts/appcast.sh` on it with a loopback URL prefix, serve that folder with `python3 -m http.server`, and launch the older build with `TELEPORTBREAD_FEED_URL` pointing at the local appcast. Debug builds only.
