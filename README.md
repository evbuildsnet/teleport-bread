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

Users with automatic checks on see the update within a day. Everyone else sees it on "Check for Updates…". Watch a run with `gh run watch`.

Version numbers come from the tag. The build number is the workflow run number and must only go up, so never delete and recreate a tag after a release has shipped.

### Mac App Store

Manual, through Xcode:

1. Open `app/TeleportBread.xcodeproj` (run `make gen` first if it is missing).
2. Select the `TeleportBreadMac` scheme, then Product → Archive.
3. In Organizer: Distribute App → App Store Connect → Upload.
4. On appstoreconnect.apple.com, create the new macOS version, attach the build, fill in what's new, and submit for review.

This target never contains Sparkle. Apple delivers its updates.

### Secrets and keys

The workflow needs these repository secrets: `DEVELOPER_ID_P12_BASE64`, `DEVELOPER_ID_P12_PASSWORD`, `NOTARY_KEY_ID`, `NOTARY_ISSUER_ID`, `NOTARY_KEY_P8`, `SPARKLE_PRIVATE_KEY`. Backups of the underlying files are in Ev's iCloud under Business/Personal/codes.

The Sparkle private key is the one thing that cannot be rotated quietly: every shipped app trusts it. Guard it.

### Rehearsing an update locally

Build two versions of the Direct target, zip the newer one, run `scripts/appcast.sh` on it with a loopback URL prefix, serve that folder with `python3 -m http.server`, and launch the older build with `TELEPORTBREAD_FEED_URL` pointing at the local appcast. Debug builds only.
