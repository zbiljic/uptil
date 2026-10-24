# Releasing UpTil

Set the version and build number in `Resources/Info.plist`, then run
`mise run check` and `mise run package`. This creates
`dist/UpTil-VERSION-arm64.zip` and its SHA-256 checksum for the GitHub
release tagged `vVERSION`. The ZIP includes the app and its bundled `uptil`
CLI for Apple silicon Macs running macOS 14 or later; Intel Macs are not
supported. `mise run package:clean` removes `dist`.

To release on GitHub, commit and push the release changes, then tag that
commit with the app version (for example, `0.1.0`):

```sh
git tag v0.1.0
git push origin v0.1.0
```

The [release workflow](.github/workflows/release.yml) checks the tag against
`Resources/Info.plist`, runs `mise run package`, and creates a draft release
with the ZIP, checksum, and a static installation description. It uses ad hoc
signing; no Apple Developer ID or signing secrets are needed, and the build is
not notarized. Review the draft and CI results, then click **Publish release**
on GitHub.

## Release notes

The release description can be edited before or after publishing, on GitHub
or with the local task below. CI does not generate a change summary.

Write the complete release description in `dist/release-notes-v0.1.0.md`,
then update the existing release:

```sh
mise run release-notes v0.1.0 dist/release-notes-v0.1.0.md
```

This requires an authenticated `gh` CLI and replaces the full description,
so keep the installation and signing information in the file. It leaves
assets and the draft/published status unchanged.
