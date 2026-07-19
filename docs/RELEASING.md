# Releasing Agent Island

1. Bump `CFBundleShortVersionString` (X.Y.Z) and `CFBundleVersion` in `packaging/Info.plist`.
2. Commit and push to `main`.
3. Tag matching the plist version: `git tag v0.3.0` (tag must be `v` + CFBundleShortVersionString).
4. Push the tag: `git push origin v0.3.0`.
5. CI (`.github/workflows/release.yml`) builds the universal dmg, signs it with the
   `SPARKLE_ED_PRIVATE_KEY` repo secret, regenerates `appcast.xml`, pushes it to `main`,
   and publishes the GitHub release with `dist/AgentIsland-vX.Y.Z.dmg` attached.

Local fallback: `scripts/make-dmg.sh`, then `scripts/make-appcast.sh` (uses the keychain key),
commit+push `appcast.xml`, then `gh release create vX.Y.Z dist/AgentIsland-vX.Y.Z.dmg --generate-notes`.
