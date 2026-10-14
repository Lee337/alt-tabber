# Update signing and channels

The package pins Sparkle 2.9.6. Every build embeds and signs the updater framework, scripting dictionary, and `alttabber` command. With no AltTabber EdDSA key and HTTPS feed configured, **Check for Updates** opens the AltTabber releases page and automatic checks stay inactive. The two network features, update checks and LRCLIB lyrics, have separate preferences and default to off.

For a release, generate a new AltTabber-specific EdDSA key using Sparkle's `generate_keys` tool, store its private key outside the repository, and put its public key in the build. Use separate stable and nightly HTTPS feeds. Never reuse another application's feed, key, or bundle identifier. The feed URL and public key are inserted at build time:

```sh
ALT_TABBER_UPDATE_PUBLIC_KEY='base64-public-key' \
ALT_TABBER_STABLE_FEED_URL='https://example.com/alttabber/stable/appcast.xml' \
ALT_TABBER_NIGHTLY_FEED_URL='https://example.com/alttabber/nightly/appcast.xml' \
make release-artifacts

ALT_TABBER_UPDATE_KEY_FILE='/secure/location/alttabber-ed25519.key' \
ALT_TABBER_UPDATE_DOWNLOAD_PREFIX='https://example.com/alttabber/stable/' \
scripts/generate-appcast.sh stable
```

Run `generate-appcast.sh nightly` with the nightly prefix and build archive to produce the second feed. Publish only after verifying each appcast enclosure's EdDSA signature against its archive with Sparkle's `sign_update --verify` and testing a clean install. Verify that a modified archive is rejected. The generated feed, archive URLs, public key, signing identity, notarization, and release hosting must be configured together. CI does not have those credentials in this checkout, so no production update feed is published here.

`generate-appcast.sh` refuses to create a feed from an app without `SUPublicEDKey`, then checks that every generated enclosure has an EdDSA signature. A temporary key and app bundle were used to exercise the signing and rejection paths locally; this is separate from a production release key.

See [Sparkle's official packaging documentation](https://sparkle-project.org/documentation/) for key handling, signing, feed publication, and notarization requirements.
